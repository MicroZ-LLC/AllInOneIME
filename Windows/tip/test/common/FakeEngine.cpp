#include "FakeEngine.h"

#include <sddl.h>

#include <chrono>

namespace aio::test {

using nlohmann::json;

namespace {

constexpr DWORD kBuffer = 64 * 1024;
constexpr DWORD kReadTimeoutMs = 5000;
constexpr DWORD kSilenceMs = 1500;
constexpr DWORD kStrayMs = 600; // after the last line, how long the engine watches for frames the golden doesn't list

std::wstring Widen(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}

// Replaces the golden's "$any" placeholders in an outgoing `<` frame with concrete values the DLL can decode.
void FillAny(json& body) {
    for (auto it = body.begin(); it != body.end(); ++it) {
        if (it->is_string() && it->get<std::string>() == "$any") {
            if (it.key() == "enginePid") *it = static_cast<uint32_t>(GetCurrentProcessId());
            else *it = "fake";
        } else if (it->is_structured()) {
            FillAny(*it);
        }
    }
}

} // namespace

std::wstring FakeEngine::CurrentUserSid() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    std::vector<BYTE> buf(size);
    std::wstring sid;
    if (size && GetTokenInformation(token, TokenUser, buf.data(), size, &size)) {
        LPWSTR text = nullptr;
        if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buf.data())->User.Sid, &text)) {
            sid = text;
            LocalFree(text);
        }
    }
    CloseHandle(token);
    return sid;
}

std::wstring FakeEngine::RealPipeName(const std::wstring& userSid) {
    return L"\\\\.\\pipe\\AllInOneIME-" + userSid + L"-v1";
}

FakeEngine::FakeEngine(Transcript transcript, std::wstring pipeName, std::wstring userSid)
    : transcript_(std::move(transcript)), pipeName_(std::move(pipeName)), userSid_(std::move(userSid)) {
    if (userSid_.empty()) userSid_ = CurrentUserSid();
    if (pipeName_.empty()) pipeName_ = RealPipeName(userSid_);
    readEvent_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    writeEvent_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
}

FakeEngine::~FakeEngine() {
    Stop();
    if (thread_.joinable()) thread_.join();
    if (pipe_ != INVALID_HANDLE_VALUE) CloseHandle(pipe_);
    if (readEvent_) CloseHandle(readEvent_);
    if (writeEvent_) CloseHandle(writeEvent_);
}

void FakeEngine::Note(const std::string& s) {
    result_.notes.push_back(s);
}

HANDLE FakeEngine::CreateInstance(bool first) {
    // §2.1 security descriptor, with the owner set to this user so the DLL's server check (owner == user) passes.
    std::wstring sddl = L"O:" + userSid_ + L"D:P(A;;GA;;;" + userSid_ +
                        L")(A;;GA;;;SY)(A;;GRGW;;;AC)(A;;GRGW;;;S-1-15-2-2)S:(ML;;NW;;;LW)";
    PSECURITY_DESCRIPTOR sd = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &sd, nullptr)) {
        Note("ConvertStringSecurityDescriptor failed: " + std::to_string(GetLastError()));
        return INVALID_HANDLE_VALUE;
    }
    SECURITY_ATTRIBUTES sa = {sizeof sa, sd, FALSE};
    DWORD open = PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED;
    if (first) open |= FILE_FLAG_FIRST_PIPE_INSTANCE;
    HANDLE pipe = CreateNamedPipeW(pipeName_.c_str(), open,
                                   PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_REJECT_REMOTE_CLIENTS,
                                   PIPE_UNLIMITED_INSTANCES, kBuffer, kBuffer, 0, &sa);
    LocalFree(sd);
    if (pipe == INVALID_HANDLE_VALUE) Note("CreateNamedPipe failed: " + std::to_string(GetLastError()));
    return pipe;
}

bool FakeEngine::AcceptClient(HANDLE pipe) {
    constexpr DWORD kAcceptTimeoutMs = 15000; // the DLL connects well within this, or the test host can't reach us
    OVERLAPPED ov = {};
    ov.hEvent = readEvent_;
    ResetEvent(readEvent_);
    BOOL ok = ConnectNamedPipe(pipe, &ov);
    DWORD err = ok ? ERROR_SUCCESS : GetLastError();
    if (err == ERROR_PIPE_CONNECTED) return true;
    if (err == ERROR_IO_PENDING) {
        const ULONGLONG end = GetTickCount64() + kAcceptTimeoutMs;
        while (!stop_.load() && GetTickCount64() < end) {
            if (WaitForSingleObject(readEvent_, 200) == WAIT_OBJECT_0) {
                DWORD n = 0;
                return GetOverlappedResult(pipe, &ov, &n, FALSE) != 0;
            }
        }
        CancelIoEx(pipe, &ov);
        return false;
    }
    return err == ERROR_SUCCESS;
}

bool FakeEngine::VerifyClient(HANDLE pipe) {
    DWORD mySession = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &mySession);
    ULONG clientSession = 0;
    if (!GetNamedPipeClientSessionId(pipe, &clientSession) || clientSession != mySession) {
        Note("client check: the client is in another session");
        return false;
    }
    ULONG pid = 0;
    if (!GetNamedPipeClientProcessId(pipe, &pid)) {
        Note("client check: no client process id");
        return false;
    }
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    HANDLE token = nullptr;
    if (!process || !OpenProcessToken(process, TOKEN_QUERY, &token)) {
        if (process) CloseHandle(process);
        Note("client check: can't open the client's token");
        return false;
    }
    CloseHandle(process);
    std::wstring user;
    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);
    std::vector<BYTE> buf(size ? size : 1);
    if (size && GetTokenInformation(token, TokenUser, buf.data(), size, &size)) {
        LPWSTR text = nullptr;
        if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buf.data())->User.Sid, &text)) {
            user = text;
            LocalFree(text);
        }
    }
    DWORD integrity = 0;
    size = 0;
    GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
    std::vector<BYTE> label(size ? size : 1);
    if (size && GetTokenInformation(token, TokenIntegrityLevel, label.data(), size, &size)) {
        PSID sid = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(label.data())->Label.Sid;
        integrity = *GetSidSubAuthority(sid, *GetSidSubAuthorityCount(sid) - 1);
    }
    DWORD appContainer = 0;
    GetTokenInformation(token, TokenIsAppContainer, &appContainer, sizeof appContainer, &size);
    CloseHandle(token);
    if (user != userSid_) {
        Note("client check: the client runs as another user");
        return false;
    }
    const bool trusted = integrity >= SECURITY_MANDATORY_MEDIUM_RID && !appContainer;
    char note[96];
    snprintf(note, sizeof note, "client check: same session and user, integrity 0x%lx, %s", integrity,
             trusted ? "trusted" : "untrusted");
    Note(note);
    return true;
}

bool FakeEngine::ReadFrame(HANDLE pipe, std::string& body, DWORD timeoutMs) {
    std::string buffer(kBuffer, '\0');
    OVERLAPPED ov = {};
    ov.hEvent = readEvent_;
    ResetEvent(readEvent_);
    DWORD n = 0;
    BOOL ok = ReadFile(pipe, buffer.data(), (DWORD)buffer.size(), nullptr, &ov);
    DWORD err = ok ? ERROR_SUCCESS : GetLastError();
    if (!ok && err != ERROR_IO_PENDING) return false;
    if (err == ERROR_IO_PENDING) {
        DWORD w = WaitForSingleObject(readEvent_, timeoutMs);
        if (w != WAIT_OBJECT_0) {
            CancelIoEx(pipe, &ov);
            return false;
        }
    }
    if (!GetOverlappedResult(pipe, &ov, &n, FALSE)) return false;
    if (n < 4) return false;
    const auto* p = reinterpret_cast<const unsigned char*>(buffer.data());
    uint32_t len = p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24);
    if (len != n - 4) return false;
    body.assign(buffer.data() + 4, len);
    return true;
}

bool FakeEngine::SendFrame(HANDLE pipe, const json& bodyIn) {
    json body = bodyIn;
    FillAny(body);
    std::string text = body.dump();
    std::string frame;
    uint32_t len = (uint32_t)text.size();
    frame.push_back((char)(len & 0xFF));
    frame.push_back((char)((len >> 8) & 0xFF));
    frame.push_back((char)((len >> 16) & 0xFF));
    frame.push_back((char)((len >> 24) & 0xFF));
    frame += text;
    OVERLAPPED ov = {};
    ov.hEvent = writeEvent_;
    ResetEvent(writeEvent_);
    DWORD n = 0;
    BOOL ok = WriteFile(pipe, frame.data(), (DWORD)frame.size(), nullptr, &ov);
    if (!ok && GetLastError() != ERROR_IO_PENDING) return false;
    if (WaitForSingleObject(writeEvent_, kReadTimeoutMs) != WAIT_OBJECT_0) {
        CancelIoEx(pipe, &ov);
        return false;
    }
    return GetOverlappedResult(pipe, &ov, &n, FALSE) && n == frame.size();
}

void FakeEngine::Start() {
    thread_ = std::thread([this] { Run(); });
}

void FakeEngine::Stop() {
    stop_.store(true);
    if (readEvent_) SetEvent(readEvent_);
}

void FakeEngine::Join() {
    if (thread_.joinable()) thread_.join();
}

void FakeEngine::Run() {
    if (transcript_.noEngine) {
        result_.ok = true;
        result_.summary = "no engine (keys pass through)";
        pipeReady_.store(true);
        return;
    }

    pipe_ = CreateInstance(true);
    if (pipe_ == INVALID_HANDLE_VALUE) {
        result_.summary = "could not create the pipe";
        pipeReady_.store(true);
        return;
    }
    pipeReady_.store(true);
    if (!AcceptClient(pipe_)) {
        result_.summary = "no client connected";
        return;
    }
    Note("client connected");
    if (!VerifyClient(pipe_)) {
        result_.summary = "the client failed the client check";
        return;
    }

    bool failed = false;
    for (size_t i = 0; i < transcript_.lines.size() && !stop_.load(); ++i) {
        const Line& line = transcript_.lines[i];
        if (line.kind == Line::Kind::comment) continue;
        if (line.kind == Line::Kind::directive) {
            if (line.directive == "drop" || line.directive == "reconnect") {
                // §2.5: drop the connection; the DLL should reconnect to a fresh instance.
                DisconnectNamedPipe(pipe_);
                CloseHandle(pipe_);
                pipe_ = CreateInstance(false);
                if (pipe_ == INVALID_HANDLE_VALUE || !AcceptClient(pipe_)) {
                    result_.summary = "the DLL did not reconnect";
                    failed = true;
                    break;
                }
                Note("client reconnected");
                if (!VerifyClient(pipe_)) {
                    result_.summary = "the client failed the client check";
                    failed = true;
                    break;
                }
            }
            continue;
        }
        if (line.kind == Line::Kind::fromEngine) {
            if (!SendFrame(pipe_, line.body)) {
                result_.summary = "failed to send " + Brief(line.body);
                failed = true;
                break;
            }
            continue;
        }
        // fromDll: read and compare.
        ++result_.expected;
        std::string body;
        if (!ReadFrame(pipe_, body, kReadTimeoutMs)) {
            result_.summary = "timed out waiting for " + Brief(line.body);
            failed = true;
            break;
        }
        json actual = json::parse(body, nullptr, false);
        json expected = NormalizeExpected(line.body);
        if (actual.is_discarded() || !Matches(expected, actual)) {
            result_.summary = "frame " + std::to_string(result_.expected) + " mismatch\n  expected " +
                              Brief(expected) + "\n  actual   " + (actual.is_discarded() ? body : Brief(actual));
            failed = true;
            break;
        }
        ++result_.matched;
        Note("matched " + actual.value("type", std::string("?")));
    }

    // Nothing the golden doesn't list may follow: with `expect-silence` (§8) the window is long enough to cover the
    // keys the host types; otherwise it covers the host's teardown. A closed pipe ends the window early (the DLL can't
    // send after that).
    if (!failed) {
        std::string body;
        if (ReadFrame(pipe_, body, transcript_.expectSilence ? kSilenceMs : kStrayMs)) {
            result_.summary = (transcript_.expectSilence ? "expected silence but saw " : "a frame the golden doesn't list: ") + body;
            failed = true;
        } else {
            Note(transcript_.expectSilence ? "silence held" : "no further frames");
        }
    }

    if (!failed) {
        result_.ok = true;
        result_.summary = std::to_string(result_.matched) + "/" + std::to_string(result_.expected) + " frames matched";
    }
}

} // namespace aio::test
