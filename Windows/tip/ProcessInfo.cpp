#include "ProcessInfo.h"

#include <aclapi.h>
#include <appmodel.h>
#include <sddl.h>

#include <memory>
#include <vector>

#include "Log.h"
#include "wire/Wire.h"

namespace aio {

namespace {

struct HandleCloser {
    void operator()(HANDLE h) const noexcept {
        if (h && h != INVALID_HANDLE_VALUE) CloseHandle(h);
    }
};
using UniqueHandle = std::unique_ptr<void, HandleCloser>;

std::vector<BYTE> TokenInfo(HANDLE token, TOKEN_INFORMATION_CLASS cls) {
    DWORD size = 0;
    GetTokenInformation(token, cls, nullptr, 0, &size);
    if (size == 0) return {};
    std::vector<BYTE> buffer(size);
    if (!GetTokenInformation(token, cls, buffer.data(), size, &size)) return {};
    return buffer;
}

std::wstring SidString(PSID sid) {
    if (!sid || !IsValidSid(sid)) return {};
    LPWSTR text = nullptr;
    if (!ConvertSidToStringSidW(sid, &text)) return {};
    std::wstring out(text);
    LocalFree(text);
    return out;
}

std::wstring ObjectName(HANDLE object) {
    wchar_t name[256] = {};
    DWORD needed = 0;
    if (!GetUserObjectInformationW(object, UOI_NAME, name, sizeof name - sizeof(wchar_t), &needed)) return {};
    return name;
}

std::wstring Lowercase(std::wstring text) {
    if (!text.empty()) {
        LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE, text.data(), static_cast<int>(text.size()), text.data(),
                      static_cast<int>(text.size()), nullptr, nullptr, 0);
    }
    return text;
}

bool IsSid(const std::wstring& sid, WELL_KNOWN_SID_TYPE type) {
    BYTE buffer[SECURITY_MAX_SID_SIZE];
    DWORD size = sizeof buffer;
    if (!CreateWellKnownSid(type, nullptr, buffer, &size)) return false;
    return SidString(buffer) == sid;
}

ProcessInfo Compute() {
    ProcessInfo info;
    ProcessIdToSessionId(GetCurrentProcessId(), &info.sessionId);

    HANDLE raw = nullptr;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw)) {
        UniqueHandle token(raw);
        info.userSid = TokenUserSid(raw);
        info.integrity = TokenIntegrity(raw);
        DWORD isAppContainer = 0, size = 0;
        if (GetTokenInformation(raw, TokenIsAppContainer, &isAppContainer, sizeof isAppContainer, &size)) {
            info.appContainer = isAppContainer != 0;
        }
        auto groups = TokenInfo(raw, TokenGroups);
        if (!groups.empty()) {
            auto* tg = reinterpret_cast<TOKEN_GROUPS*>(groups.data());
            for (DWORD i = 0; i < tg->GroupCount; ++i) {
                if ((tg->Groups[i].Attributes & SE_GROUP_ENABLED) &&
                    IsWellKnownSid(tg->Groups[i].Sid, WinServiceSid)) {
                    info.service = true;
                }
            }
        }
    }
    info.systemAccount = IsSid(info.userSid, WinLocalSystemSid) || IsSid(info.userSid, WinLocalServiceSid) ||
                         IsSid(info.userSid, WinNetworkServiceSid);
    if (info.sessionId == 0) info.service = true;
    info.windowStation = ObjectName(GetProcessWindowStation());

    wchar_t path[MAX_PATH * 2] = {};
    DWORD n = static_cast<DWORD>(std::size(path));
    std::wstring exe;
    if (QueryFullProcessImageNameW(GetCurrentProcess(), 0, path, &n)) {
        exe.assign(path, n);
        const auto slash = exe.find_last_of(L"\\/");
        if (slash != std::wstring::npos) exe.erase(0, slash + 1);
        exe = Lowercase(exe);
    }
    info.exeName = wire::ToUtf8(exe);

    wchar_t aumid[APPLICATION_USER_MODEL_ID_MAX_LENGTH] = {};
    UINT32 len = static_cast<UINT32>(std::size(aumid));
    if (GetCurrentApplicationUserModelId(&len, aumid) == ERROR_SUCCESS && aumid[0]) {
        info.app = "win:" + wire::ToUtf8(aumid);
    } else {
        info.app = "win:" + info.exeName;
    }
    return info;
}

} // namespace

const ProcessInfo& CurrentProcess() noexcept {
    // A function-local static: its initialization is thread-safe. Without a user SID the DLL stays passive.
    static const ProcessInfo info = [] {
        try {
            return Compute();
        } catch (...) {
            return ProcessInfo{};
        }
    }();
    return info;
}

std::wstring ThreadDesktopName() {
    return ObjectName(GetThreadDesktop(GetCurrentThreadId()));
}

bool MayConnect(const char** why) {
    const auto& me = CurrentProcess();
    if (me.userSid.empty()) {
        *why = "no user SID";
        return false;
    }
    if (me.systemAccount) {
        *why = "a system account";
        return false;
    }
    if (me.service) {
        *why = "a service (or session 0)";
        return false;
    }
    if (_wcsicmp(me.windowStation.c_str(), L"WinSta0") != 0) {
        *why = "not on the interactive window station";
        return false;
    }
    if (_wcsicmp(ThreadDesktopName().c_str(), L"Default") != 0) {
        *why = "not on the Default desktop";
        return false;
    }
    *why = "";
    return true;
}

std::wstring PipeName(const std::wstring& userSid) {
    return L"\\\\.\\pipe\\AllInOneIME-" + userSid + L"-v1";
}

std::wstring EngineMutexName(const std::wstring& userSid) {
    return L"Local\\AllInOneIME-Engine-" + userSid;
}

DWORD TokenIntegrity(HANDLE token) {
    auto label = TokenInfo(token, TokenIntegrityLevel);
    if (label.empty()) return 0;
    PSID sid = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(label.data())->Label.Sid;
    if (!IsValidSid(sid) || *GetSidSubAuthorityCount(sid) == 0) return 0;
    return *GetSidSubAuthority(sid, *GetSidSubAuthorityCount(sid) - 1);
}

std::wstring TokenUserSid(HANDLE token) {
    auto user = TokenInfo(token, TokenUser);
    if (user.empty()) return {};
    return SidString(reinterpret_cast<TOKEN_USER*>(user.data())->User.Sid);
}

bool VerifyServer(HANDLE pipe, const char** why) {
    const auto& me = CurrentProcess();

    ULONG serverSession = 0;
    if (!GetNamedPipeServerSessionId(pipe, &serverSession) || serverSession != me.sessionId) {
        *why = "the server is in another session";
        return false;
    }

    PSID owner = nullptr;
    PACL sacl = nullptr;
    PSECURITY_DESCRIPTOR sd = nullptr;
    const DWORD err = GetSecurityInfo(pipe, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION | LABEL_SECURITY_INFORMATION,
                                      &owner, nullptr, nullptr, &sacl, &sd);
    if (err != ERROR_SUCCESS) {
        *why = "the pipe's security can't be read";
        return false;
    }
    const bool ownerOk = SidString(owner) == me.userSid;
    DWORD labelRid = SECURITY_MANDATORY_MEDIUM_RID; // no label is medium
    if (sacl) {
        for (WORD i = 0; i < sacl->AceCount; ++i) {
            ACE_HEADER* ace = nullptr;
            if (GetAce(sacl, i, reinterpret_cast<void**>(&ace)) && ace->AceType == SYSTEM_MANDATORY_LABEL_ACE_TYPE) {
                PSID labelSid = &reinterpret_cast<SYSTEM_MANDATORY_LABEL_ACE*>(ace)->SidStart;
                labelRid = *GetSidSubAuthority(labelSid, *GetSidSubAuthorityCount(labelSid) - 1);
            }
        }
    }
    LocalFree(sd);
    if (!ownerOk) {
        *why = "the pipe's owner is not this user";
        return false;
    }
    // The spec's SDDL labels the pipe low on purpose (so low-integrity apps can write), and a low-integrity squatter's
    // pipe is labelled low too: the label can't tell them apart. The integrity of the server process does.
    Log("server check: pipe label rid 0x%lx", labelRid);

    ULONG serverPid = 0;
    if (!GetNamedPipeServerProcessId(pipe, &serverPid)) {
        *why = "no server process id";
        return false;
    }
    // A low-integrity or AppContainer client can't open a medium process; it has only the checks above.
    const bool mayBeBlind = me.appContainer || me.integrity < SECURITY_MANDATORY_MEDIUM_RID;
    UniqueHandle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, serverPid));
    HANDLE rawToken = nullptr;
    if (!process || !OpenProcessToken(process.get(), TOKEN_QUERY, &rawToken)) {
        if (mayBeBlind && GetLastError() == ERROR_ACCESS_DENIED) {
            Log("server check: can't open the server process from this sandbox; owner and session only");
            *why = "";
            return true;
        }
        *why = "the server process can't be opened";
        return false;
    }
    UniqueHandle token(rawToken);
    if (TokenUserSid(rawToken) != me.userSid) {
        *why = "the server runs as another user";
        return false;
    }
    if (TokenIntegrity(rawToken) < SECURITY_MANDATORY_MEDIUM_RID) {
        *why = "the server runs below medium integrity";
        return false;
    }
    DWORD isAppContainer = 0, size = 0;
    if (GetTokenInformation(rawToken, TokenIsAppContainer, &isAppContainer, sizeof isAppContainer, &size) &&
        isAppContainer) {
        *why = "the server is in an AppContainer";
        return false;
    }
    *why = "";
    return true;
}

} // namespace aio
