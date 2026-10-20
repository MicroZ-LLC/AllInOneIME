// AllInOneIMESetup: the installer's helper, for what an MSI can't author itself. It is installed next to the DLL and
// the engine, and the MSI runs it (WixQuietExec, so its output goes to the MSI log). A user can run it too.
//
//   AllInOneIMESetup add-keyboard [0x0804|0x0409]   add AllInOneIME to this user's language list (InstallLayoutOrTip)
//   AllInOneIMESetup remove-keyboard                take it out of this user's list, and drop this user's TSF state
//                                                   for it
//   AllInOneIMESetup start-engine                   start this user's engine in this session, never elevated
//   AllInOneIMESetup stop-engines [--dry-run]       end every engine and Settings app run from where AllInOneIME is
//                                                   installed (any user), but the consoles' processes; --dry-run: say
//                                                   which, end none
//   AllInOneIMESetup status                         what is registered, in this user's list, and running
//
// add-keyboard picks the language: Chinese (Simplified) when it is in the user's list, else English (US). It never
// makes AllInOneIME the default input method nor switches to it: the user picks it with Win+Space, as any keyboard.
// The registration itself (the COM server, the profiles, the categories) is the DLL's DllRegisterServer, which the MSI
// runs as SelfReg.

#include <windows.h>
#include <ole2.h> // before the shell's headers: WIN32_LEAN_AND_MEAN leaves OLE out of windows.h
#include <shlobj.h>
#include <exdisp.h>
#include <msctf.h>
#include <sddl.h>
#include <shldisp.h>
#include <shlwapi.h>
#include <tlhelp32.h>
#include <winternl.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>

namespace {

// The DLL's CLSID and profile (Windows/tip/dllmain.cpp).
const CLSID kClsidTextService = {0xDBB94280, 0xC4C2, 0x4C91, {0x81, 0x6F, 0x79, 0xBB, 0x47, 0x1A, 0xFE, 0x56}};
const GUID kGuidProfile = {0x5BD6752B, 0x379B, 0x4ECD, {0x9B, 0x1B, 0x08, 0x19, 0xCB, 0xE5, 0x51, 0x71}};
constexpr LANGID kLangEnglish = 0x0409;
constexpr LANGID kLangChinese = 0x0804;
constexpr LANGID kLanguages[] = {kLangEnglish, kLangChinese};

constexpr wchar_t kEngineExe[] = L"AllInOneIMEEngine.exe";
// The Settings app, in Settings\ beside the engine: its files are replaced or removed with the engine's.
constexpr wchar_t kSettingsExe[] = L"AllInOneIMESettings.exe";

// input.dll's export (no header, no import library): see "InstallLayoutOrTip".
constexpr DWORD ILOT_UNINSTALL = 0x00000001;
using InstallLayoutOrTipFn = BOOL(WINAPI*)(LPCWSTR, DWORD);

// The user's language list, as Settings and Get-WinUserLanguageList show it: a key per language under here, holding
// a value per input method ("0804:{CLSID}{profile}"; TSF's own "enabled" flags, which EnumEnabledLayoutOrTip reports,
// also count a text service that is only enabled by default and in nobody's list).
constexpr wchar_t kUserProfile[] = L"Control Panel\\International\\User Profile";

void Say(const char* format, ...) {
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    printf("\n");
}

std::wstring GuidString(const GUID& guid) {
    wchar_t text[64] = {};
    StringFromGUID2(guid, text, static_cast<int>(std::size(text)));
    return text;
}

// "0804:{CLSID}{profile}", the form InstallLayoutOrTip and the language list (InputMethodTips) use.
std::wstring TipId(LANGID lang) {
    wchar_t prefix[8] = {};
    swprintf_s(prefix, L"%04X:", lang);
    return prefix + GuidString(kClsidTextService) + GuidString(kGuidProfile);
}

std::vector<std::wstring> Subkeys(HKEY root, const std::wstring& path) {
    std::vector<std::wstring> names;
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, path.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS) return names;
    wchar_t name[256];
    for (DWORD i = 0;; ++i) {
        DWORD length = static_cast<DWORD>(std::size(name));
        if (RegEnumKeyExW(key, i, name, &length, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
        names.push_back(name);
    }
    RegCloseKey(key);
    return names;
}

struct Listed {
    LANGID lang;
    std::wstring tag; // the language's key, "zh-Hans-CN"
};

// Where AllInOneIME is in this user's language list.
std::vector<Listed> ListedLanguages() {
    std::vector<Listed> found;
    for (const auto& tag : Subkeys(HKEY_CURRENT_USER, kUserProfile)) {
        for (LANGID lang : kLanguages) {
            if (RegGetValueW(HKEY_CURRENT_USER, (std::wstring(kUserProfile) + L"\\" + tag).c_str(), TipId(lang).c_str(),
                             RRF_RT_ANY, nullptr, nullptr, nullptr) == ERROR_SUCCESS) {
                found.push_back({lang, tag});
            }
        }
    }
    return found;
}

// InstallLayoutOrTip also rewrites the legacy list of the keyboard layouts to load (HKCU\Keyboard Layout\Preload) from
// the language list: a language in the list without a keyboard of its own gets its default layout added there. A text
// service is never in that list, so what changes there is a side effect: this puts it back as it was.
class PreloadKept {
public:
    PreloadKept() : values_(Read()) {}
    ~PreloadKept() {
        if (!existed_ || Read() == values_) return;
        HKEY key = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, kPreload, 0, KEY_READ | KEY_SET_VALUE, &key) != ERROR_SUCCESS) return;
        for (const auto& [name, data] : Read()) RegDeleteValueW(key, name.c_str());
        for (const auto& [name, data] : values_) {
            RegSetValueExW(key, name.c_str(), 0, REG_SZ, reinterpret_cast<const BYTE*>(data.c_str()),
                           static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
        }
        RegCloseKey(key);
        Say("kept HKCU\\Keyboard Layout\\Preload as it was (InstallLayoutOrTip had rewritten it)");
    }

private:
    static constexpr wchar_t kPreload[] = L"Keyboard Layout\\Preload";
    using Values = std::vector<std::pair<std::wstring, std::wstring>>;

    Values Read() {
        Values values;
        HKEY key = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, kPreload, 0, KEY_READ, &key) != ERROR_SUCCESS) return values;
        existed_ = true;
        for (DWORD i = 0;; ++i) {
            wchar_t name[64], data[64] = {};
            DWORD nameLength = static_cast<DWORD>(std::size(name)), dataSize = sizeof data - sizeof(wchar_t), type = 0;
            if (RegEnumValueW(key, i, name, &nameLength, nullptr, &type, reinterpret_cast<BYTE*>(data), &dataSize) !=
                ERROR_SUCCESS) {
                break;
            }
            if (type == REG_SZ) values.emplace_back(name, data);
        }
        RegCloseKey(key);
        std::sort(values.begin(), values.end());
        return values;
    }

    bool existed_ = false;
    Values values_;
};

class InputDll {
public:
    InputDll() {
        module_ = LoadLibraryExW(L"input.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (module_) install_ = reinterpret_cast<InstallLayoutOrTipFn>(GetProcAddress(module_, "InstallLayoutOrTip"));
    }
    ~InputDll() {
        if (module_) FreeLibrary(module_);
    }
    bool ok() const { return install_ != nullptr; }
    bool Install(const std::wstring& id, DWORD flags) const {
        PreloadKept preload;
        return install_(id.c_str(), flags) != FALSE;
    }

private:
    HMODULE module_ = nullptr;
    InstallLayoutOrTipFn install_ = nullptr;
};

// ---- this process: its user, session and elevation ----

std::wstring CurrentUserSid() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
    std::vector<BYTE> buffer(256);
    DWORD size = 0;
    std::wstring result;
    if (GetTokenInformation(token, TokenUser, buffer.data(), static_cast<DWORD>(buffer.size()), &size)) {
        wchar_t* text = nullptr;
        if (ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &text)) {
            result = text;
            LocalFree(text);
        }
    }
    CloseHandle(token);
    return result;
}

bool IsElevated() {
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
    TOKEN_ELEVATION elevation = {};
    DWORD size = 0;
    const bool elevated = GetTokenInformation(token, TokenElevation, &elevation, sizeof elevation, &size) &&
                          elevation.TokenIsElevated;
    CloseHandle(token);
    return elevated;
}

DWORD CurrentSession() {
    DWORD session = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &session);
    return session;
}

// ---- where things are ----

std::wstring ReadMachineString(const wchar_t* subkey, const wchar_t* name) {
    wchar_t value[MAX_PATH * 2] = {};
    DWORD size = sizeof value;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, subkey, name, RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_SUBKEY_WOW6464KEY,
                     nullptr, value, &size) != ERROR_SUCCESS) {
        return {};
    }
    return value;
}

// The engine the DLL starts (HKLM\Software\AllInOneIME, Engine), else the one next to this program.
std::wstring EnginePath() {
    std::wstring path = ReadMachineString(L"Software\\AllInOneIME", L"Engine");
    if (!path.empty()) return path;
    wchar_t self[MAX_PATH * 2] = {};
    GetModuleFileNameW(nullptr, self, static_cast<DWORD>(std::size(self)));
    std::wstring dir = self;
    return dir.substr(0, dir.find_last_of(L'\\') + 1) + kEngineExe;
}

std::wstring WithBackslash(std::wstring folder) {
    if (!folder.empty() && folder.back() != L'\\') folder += L'\\';
    return folder;
}

// The folders the only engines stop-engines ends are in, each with its trailing backslash: this helper's own (the
// installed copy's folder, wherever msiexec INSTALLFOLDER= put it: the MSI runs the helper from there, also while it
// removes that copy, when HKLM's InstallDir is already gone), the installed copy's (InstallDir, run by hand), and
// Program Files\AllInOneIME\ (every version's folder in the default place).
std::vector<std::wstring> InstallRoots() {
    std::vector<std::wstring> roots;
    wchar_t self[MAX_PATH * 2] = {};
    const DWORD length = GetModuleFileNameW(nullptr, self, static_cast<DWORD>(std::size(self)));
    std::wstring own(self, length);
    if (!own.empty()) roots.push_back(own.substr(0, own.find_last_of(L'\\') + 1));
    const std::wstring installed = ReadMachineString(L"Software\\AllInOneIME", L"InstallDir");
    if (!installed.empty()) roots.push_back(WithBackslash(installed));
    PWSTR folder = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_ProgramFilesX64, 0, nullptr, &folder)) && folder) {
        roots.push_back(WithBackslash(folder) + L"AllInOneIME\\");
    }
    CoTaskMemFree(folder);
    return roots;
}

bool StartsWithNoCase(const std::wstring& text, const std::wstring& prefix) {
    return !prefix.empty() && text.size() >= prefix.size() &&
           _wcsnicmp(text.c_str(), prefix.c_str(), prefix.size()) == 0;
}

struct Engine {
    DWORD pid = 0;
    DWORD session = 0;
    std::wstring path;
    std::wstring commandLine;
};

// A process's command line (NtQueryInformationProcess, ProcessCommandLineInformation: Windows 8.1 and later); empty
// when it can't be read.
std::wstring CommandLineOf(HANDLE process) {
    using Query = NTSTATUS(NTAPI*)(HANDLE, PROCESSINFOCLASS, PVOID, ULONG, PULONG);
    static const auto query = reinterpret_cast<Query>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "NtQueryInformationProcess"));
    if (!query) return {};
    constexpr auto kProcessCommandLineInformation = static_cast<PROCESSINFOCLASS>(60);
    ULONG size = 0;
    query(process, kProcessCommandLineInformation, nullptr, 0, &size);
    if (size < sizeof(UNICODE_STRING)) return {};
    std::vector<unsigned char> buffer(size);
    if (query(process, kProcessCommandLineInformation, buffer.data(), size, &size) < 0) return {};
    const auto* line = reinterpret_cast<const UNICODE_STRING*>(buffer.data());
    return std::wstring(line->Buffer, line->Length / sizeof(wchar_t));
}

// The engine's own process for a console window it opened (`AllInOneIMEEngine --run-in-console`): its program (an
// agent, a terminal command) still runs there, and it holds that program's prompt file until the program ends.
bool IsConsoleProcess(const Engine& engine) {
    return engine.commandLine.find(L" --run-in-console") != std::wstring::npos;
}

std::vector<Engine> RunningEngines(const wchar_t* exe = kEngineExe) {
    std::vector<Engine> engines;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return engines;
    PROCESSENTRY32W entry = {sizeof entry};
    for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
        if (_wcsicmp(entry.szExeFile, exe) != 0) continue;
        Engine engine;
        engine.pid = entry.th32ProcessID;
        ProcessIdToSessionId(engine.pid, &engine.session);
        if (HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, engine.pid)) {
            wchar_t path[MAX_PATH * 2] = {};
            DWORD size = static_cast<DWORD>(std::size(path));
            if (QueryFullProcessImageNameW(process, 0, path, &size)) engine.path = path;
            engine.commandLine = CommandLineOf(process);
            CloseHandle(process);
        }
        engines.push_back(engine);
    }
    CloseHandle(snapshot);
    return engines;
}

// ---- add-keyboard / remove-keyboard ----

// The user's language list has Chinese (Simplified): a language key, or a tag of the list's order (Languages).
bool UserHasSimplifiedChinese() {
    std::vector<std::wstring> tags = Subkeys(HKEY_CURRENT_USER, kUserProfile);
    std::vector<wchar_t> languages(4096);
    DWORD size = static_cast<DWORD>(languages.size() * sizeof(wchar_t));
    if (RegGetValueW(HKEY_CURRENT_USER, kUserProfile, L"Languages", RRF_RT_REG_MULTI_SZ, nullptr, languages.data(),
                     &size) == ERROR_SUCCESS) {
        for (const wchar_t* tag = languages.data(); *tag; tag += wcslen(tag) + 1) tags.push_back(tag);
    }
    for (const auto& tag : tags) {
        if (_wcsicmp(tag.c_str(), L"zh-CN") == 0 || _wcsicmp(tag.c_str(), L"zh-Hans-CN") == 0 ||
            _wcsicmp(tag.c_str(), L"zh-Hans") == 0) {
            return true;
        }
    }
    return false;
}

bool IsListed(LANGID lang) {
    for (const auto& listed : ListedLanguages()) {
        if (listed.lang == lang) return true;
    }
    return false;
}

int AddKeyboard(LANGID requested) {
    InputDll input;
    if (!input.ok()) {
        Say("add-keyboard: input.dll has no InstallLayoutOrTip");
        return 1;
    }
    const auto present = ListedLanguages();
    if (!present.empty()) {
        Say("add-keyboard: already in this user's language list (%ls)", TipId(present.front().lang).c_str());
        return 0;
    }
    const LANGID lang = requested ? requested : (UserHasSimplifiedChinese() ? kLangChinese : kLangEnglish);
    const std::wstring id = TipId(lang);
    // No ILOT_DEFPROFILE: added at the end of the language's input methods, never made the default nor switched to.
    if (!input.Install(id, 0)) {
        Say("add-keyboard: InstallLayoutOrTip(%ls) failed", id.c_str());
        return 1;
    }
    const bool listed = IsListed(lang);
    Say("add-keyboard: %ls %s", id.c_str(), listed ? "added to this user's language list" : "NOT in the list after");
    return listed ? 0 : 1;
}

// Deletes `subkey` of `root` and everything under it.
void DeleteTree(HKEY root, const std::wstring& subkey) {
    if (RegDeleteTreeW(root, subkey.c_str()) == ERROR_SUCCESS) RegDeleteKeyW(root, subkey.c_str());
}

// What TSF keeps for this user under keys named by our CLSID: ours alone. (The machine's part is DllUnregisterServer's.)
void DropUserTsfState() {
    const std::wstring clsid = GuidString(kClsidTextService);
    DeleteTree(HKEY_CURRENT_USER, L"Software\\Microsoft\\CTF\\TIP\\" + clsid);
    // InputSession\<KLID>\{CLSID}: TSF's usage counters for a text service, per language.
    const std::wstring sessions = L"Software\\Microsoft\\CTF\\InputSession";
    for (const auto& klid : Subkeys(HKEY_CURRENT_USER, sessions)) {
        DeleteTree(HKEY_CURRENT_USER, sessions + L"\\" + klid + L"\\" + clsid);
    }
}

int RemoveKeyboard() {
    InputDll input;
    if (!input.ok()) {
        Say("remove-keyboard: input.dll has no InstallLayoutOrTip");
        return 1;
    }
    int failures = 0;
    for (const auto& listed : ListedLanguages()) {
        const std::wstring id = TipId(listed.lang);
        const bool ok = input.Install(id, ILOT_UNINSTALL);
        Say("remove-keyboard: %ls %s", id.c_str(), ok ? "removed from this user's language list" : "FAILED");
        if (!ok) ++failures;
    }
    const auto left = ListedLanguages();
    if (!left.empty()) {
        Say("remove-keyboard: still in the list (%ls)", TipId(left.front().lang).c_str());
        ++failures;
    }
    DropUserTsfState();
    if (!failures) Say("remove-keyboard: AllInOneIME is not in this user's language list");
    return failures ? 1 : 0;
}

// ---- start-engine / stop-engines ----

// Starts `path` through the desktop's shell (Explorer), so it runs as the logged-on user would start it: unelevated,
// a child of Explorer, as a Run entry is at logon ("How can I launch an unelevated process from my elevated process").
HRESULT ShellExecuteFromDesktop(const std::wstring& path) {
    IShellWindows* windows = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_ShellWindows, nullptr, CLSCTX_LOCAL_SERVER, IID_PPV_ARGS(&windows));
    if (FAILED(hr)) return hr;
    VARIANT empty = {};
    long hwnd = 0;
    IDispatch* desktop = nullptr;
    hr = windows->FindWindowSW(&empty, &empty, SWC_DESKTOP, &hwnd, SWFO_NEEDDISPATCH, &desktop);
    windows->Release();
    if (hr != S_OK || !desktop) return FAILED(hr) ? hr : E_FAIL;
    IShellBrowser* browser = nullptr;
    hr = IUnknown_QueryService(desktop, SID_STopLevelBrowser, IID_PPV_ARGS(&browser));
    desktop->Release();
    if (FAILED(hr)) return hr;
    IShellView* view = nullptr;
    hr = browser->QueryActiveShellView(&view);
    browser->Release();
    if (FAILED(hr)) return hr;
    IDispatch* background = nullptr;
    hr = view->GetItemObject(SVGIO_BACKGROUND, IID_PPV_ARGS(&background));
    view->Release();
    if (FAILED(hr)) return hr;
    IShellFolderViewDual* folderView = nullptr;
    hr = background->QueryInterface(IID_PPV_ARGS(&folderView));
    background->Release();
    if (FAILED(hr)) return hr;
    IDispatch* application = nullptr;
    hr = folderView->get_Application(&application);
    folderView->Release();
    if (FAILED(hr)) return hr;
    IShellDispatch2* shell = nullptr;
    hr = application->QueryInterface(IID_PPV_ARGS(&shell));
    application->Release();
    if (FAILED(hr)) return hr;
    BSTR file = SysAllocString(path.c_str());
    VARIANT args = {}, dir = {}, operation = {}, show = {};
    show.vt = VT_I4;
    show.lVal = SW_HIDE;
    hr = shell->ShellExecute(file, args, dir, operation, show);
    SysFreeString(file);
    shell->Release();
    return hr;
}

bool EngineRunningForMe(const std::wstring& sid) {
    const std::wstring name = L"Local\\AllInOneIME-Engine-" + sid;
    if (HANDLE mutex = OpenMutexW(SYNCHRONIZE, FALSE, name.c_str())) {
        CloseHandle(mutex);
        return true;
    }
    return false;
}

int StartEngine() {
    const DWORD session = CurrentSession();
    if (session == 0) {
        // Session 0 has no desktop and no apps: an engine there would only hold the pipe's name.
        Say("start-engine: session 0 (a service or SSH): not started; it starts at logon, or when an app needs it");
        return 0;
    }
    const std::wstring sid = CurrentUserSid();
    if (!sid.empty() && EngineRunningForMe(sid)) {
        Say("start-engine: already running for this user in this session");
        return 0;
    }
    const std::wstring path = EnginePath();
    if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
        Say("start-engine: no engine at %ls", path.c_str());
        return 1;
    }
    if (IsElevated()) {
        // An elevated engine would serve every app with an administrator's rights: start it through the shell.
        const HRESULT hr = ShellExecuteFromDesktop(path);
        Say("start-engine: through the desktop shell (this process is elevated): 0x%08lx", hr);
        return SUCCEEDED(hr) ? 0 : 1;
    }
    std::wstring command = L"\"" + path + L"\"";
    STARTUPINFOW si = {sizeof si};
    PROCESS_INFORMATION pi = {};
    const DWORD flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT;
    BOOL started = CreateProcessW(path.c_str(), command.data(), nullptr, nullptr, FALSE,
                                  flags | CREATE_BREAKAWAY_FROM_JOB, nullptr, nullptr, &si, &pi);
    if (!started) {
        started = CreateProcessW(path.c_str(), command.data(), nullptr, nullptr, FALSE, flags, nullptr, nullptr, &si,
                                 &pi);
    }
    if (!started) {
        Say("start-engine: CreateProcess failed: %lu", GetLastError());
        return 1;
    }
    Say("start-engine: started, pid %lu", pi.dwProcessId);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}

// Ends the engines and Settings windows run from the installed copy's folders (InstallRoots), for an uninstall or an
// upgrade: their files go. A console's process is left to its program (an upgrade or uninstall doesn't close the
// user's agent or terminal mid-work; it deletes the prompt's file once the program ends, and its files go at the next
// restart, as a DLL in use does). `dryRun`: says which it would end.
int StopEngines(bool dryRun) {
    const std::vector<std::wstring> roots = InstallRoots();
    int failures = 0, stopped = 0;
    std::vector<Engine> running = RunningEngines(kEngineExe);
    for (const auto& window : RunningEngines(kSettingsExe)) running.push_back(window);
    for (const auto& engine : running) {
        const bool installed = std::any_of(roots.begin(), roots.end(),
                                           [&](const std::wstring& root) { return StartsWithNoCase(engine.path, root); });
        if (!installed) {
            Say("stop-engines: left pid %lu alone (%ls)", engine.pid,
                engine.path.empty() ? L"path unknown" : engine.path.c_str());
            continue;
        }
        if (IsConsoleProcess(engine)) {
            Say("stop-engines: left pid %lu alone (a console's, its program still running: %ls)", engine.pid,
                engine.path.c_str());
            continue;
        }
        if (dryRun) {
            Say("stop-engines: would stop pid %lu (session %lu, %ls)", engine.pid, engine.session, engine.path.c_str());
            ++stopped;
            continue;
        }
        HANDLE process = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, engine.pid);
        if (!process) {
            Say("stop-engines: can't open pid %lu: %lu", engine.pid, GetLastError());
            ++failures;
            continue;
        }
        // The engine keeps nothing that needs flushing; the DLLs see the pipe close and go passive.
        if (TerminateProcess(process, 0) && WaitForSingleObject(process, 5000) == WAIT_OBJECT_0) {
            Say("stop-engines: stopped pid %lu (session %lu)", engine.pid, engine.session);
            ++stopped;
        } else {
            Say("stop-engines: pid %lu didn't stop: %lu", engine.pid, GetLastError());
            ++failures;
        }
        CloseHandle(process);
    }
    if (!stopped && !failures) Say("stop-engines: none running");
    return failures ? 1 : 0;
}

// ---- status ----

int Status() {
    printf("com-server: %ls\n",
           ReadMachineString((L"Software\\Classes\\CLSID\\" + GuidString(kClsidTextService) + L"\\InprocServer32").c_str(),
                             nullptr)
               .c_str());
    printf("engine-path: %ls\n", ReadMachineString(L"Software\\AllInOneIME", L"Engine").c_str());
    printf("run-at-logon: %ls\n",
           ReadMachineString(L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", L"AllInOneIME").c_str());

    // The profiles as RegisterProfile wrote them, and as TSF enumerates them (only where TSF runs: not in session 0).
    ITfInputProcessorProfileMgr* mgr = nullptr;
    if (CurrentSession() != 0) {
        CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                         IID_ITfInputProcessorProfileMgr, reinterpret_cast<void**>(&mgr));
    } else {
        printf("tsf: not in session 0 (a service's or SSH's): run status in a desktop session to see TSF's view\n");
    }
    for (LANGID lang : kLanguages) {
        wchar_t key[160] = {};
        swprintf_s(key, L"Software\\Microsoft\\CTF\\TIP\\%ls\\LanguageProfile\\0x%08X\\%ls",
                   GuidString(kClsidTextService).c_str(), lang, GuidString(kGuidProfile).c_str());
        const std::wstring description = ReadMachineString(key, L"Description");
        printf("profile %04X: %s\n", lang, description.empty() ? "not registered" : "registered");
        if (mgr) {
            TF_INPUTPROCESSORPROFILE profile = {};
            const HRESULT hr = mgr->GetProfile(TF_PROFILETYPE_INPUTPROCESSOR, lang, kClsidTextService, kGuidProfile,
                                               nullptr, &profile);
            if (hr == S_OK) {
                printf("tsf %04X: enumerated, %s\n", lang,
                       (profile.dwFlags & TF_IPP_FLAG_ENABLED) ? "enabled" : "not enabled");
            } else {
                printf("tsf %04X: not enumerated (0x%08lx)\n", lang, hr);
            }
        }
    }
    if (mgr) mgr->Release();

    const auto listed = ListedLanguages();
    if (listed.empty()) printf("language-list: not in this user's list\n");
    for (const auto& item : listed) printf("language-list: %ls (%ls)\n", TipId(item.lang).c_str(), item.tag.c_str());

    const auto engines = RunningEngines();
    if (engines.empty()) printf("engine: not running\n");
    for (const auto& engine : engines) {
        printf("engine: pid %lu, session %lu, %ls\n", engine.pid, engine.session, engine.path.c_str());
    }
    return 0;
}

int Usage() {
    printf("usage: AllInOneIMESetup add-keyboard [0x0804|0x0409] | remove-keyboard | start-engine | "
           "stop-engines [--dry-run] | status\n");
    return 2;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 2) return Usage();
    const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const std::wstring command = argv[1];
    int rc = 2;
    if (command == L"add-keyboard") {
        const LANGID lang = argc > 2 ? static_cast<LANGID>(wcstoul(argv[2], nullptr, 0)) : 0;
        if (lang && lang != kLangEnglish && lang != kLangChinese) {
            rc = Usage();
        } else {
            rc = AddKeyboard(lang);
        }
    } else if (command == L"remove-keyboard") {
        rc = RemoveKeyboard();
    } else if (command == L"start-engine") {
        rc = StartEngine();
    } else if (command == L"stop-engines") {
        rc = StopEngines(argc > 2 && std::wstring(argv[2]) == L"--dry-run");
    } else if (command == L"status") {
        rc = Status();
    } else {
        rc = Usage();
    }
    if (SUCCEEDED(init)) CoUninitialize();
    return rc;
}
