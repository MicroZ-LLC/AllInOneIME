// e2ehook: a tiny WH_GETMESSAGE hook DLL the e2e driver injects into Notepad's GUI thread, so that it can activate the
// AllInOneIME profile *for that thread only*, and put the thread back as it was afterwards.
//
// A TSF text service has no HKL, so it can't be selected from outside with WM_INPUTLANGCHANGEREQUEST the way a keyboard
// layout can; and ITfInputProcessorProfileMgr::ActivateProfile acts on the calling thread. The only way to put the TIP
// on another app's thread — which is how the language bar switches one window when per-thread input settings are on —
// is to run ActivateProfile inside that app. The driver sets this hook on Notepad's thread and pumps one message; the
// first call activates the profile on Notepad's thread. With per-thread input settings on (the driver sets them), that
// touches only Notepad, never the session.
//
// The Notepad it lands in is usually the user's own, already running (the Store Notepad is one process for every
// window), so it hasn't the driver's environment: the driver hands the language and its log file over in a named
// mapping (`Local\AllInOneIME-e2e-hook`). The hook points the DLL's diagnostic log (AIO_TIP_LOG) in Notepad at the
// driver's for the run, so the driver sees the DLL load and connect there.
//
// The profile is activated for Notepad's process (TF_IPPMF_FORPROCESS), not only the window's thread: the Store Notepad
// is a WinUI 3 app, whose text input (TextInputFramework) doesn't run its TSF on the window's thread, so activating the
// window's thread alone never loads the TIP (M3 found exactly that). It is still one process, never the session.
//
// When the driver posts the registered message `AllInOneIME-e2e-restore`, the hook puts back what it changed in
// Notepad: the session's input method (as the driver found it) for the process, the per-thread input setting,
// AIO_TIP_LOG; then it asks COM to unload the DLLs no longer in use (TSF keeps objects of the TIP, so it stays loaded
// until Notepad exits).
//
// It writes what it did to the driver's log, never any text.

#include <windows.h>
#include <msctf.h>

#include <cstdio>

namespace {

// Must match dllmain.cpp and the driver.
const CLSID kClsidTextService = {0xDBB94280, 0xC4C2, 0x4C91, {0x81, 0x6F, 0x79, 0xBB, 0x47, 0x1A, 0xFE, 0x56}};
const GUID kGuidProfile = {0x5BD6752B, 0x379B, 0x4ECD, {0x9B, 0x1B, 0x08, 0x19, 0xCB, 0xE5, 0x51, 0x71}};

// The driver's hand-over (must match the driver).
struct HookConfig {
    DWORD langid;
    wchar_t log[MAX_PATH];
    BOOL haveRestore;                  // the session's input method when the driver started: what Notepad goes back to
    TF_INPUTPROCESSORPROFILE restore;
};
constexpr wchar_t kConfigName[] = L"Local\\AllInOneIME-e2e-hook";
constexpr wchar_t kRestoreMessage[] = L"AllInOneIME-e2e-restore";

HMODULE g_self = nullptr;
bool g_done = false;
bool g_restored = false;
UINT g_restoreMessage = 0;
HookConfig g_config = {};

// What the hook changed, to put back.
bool g_setThreadLocal = false;
bool g_havePrevious = false;
TF_INPUTPROCESSORPROFILE g_previous = {};
bool g_setLog = false;
bool g_hadLog = false;
wchar_t g_previousLog[MAX_PATH] = {};

void Log(const char* format, ...) {
    const wchar_t* path = g_config.log[0] ? g_config.log : nullptr;
    wchar_t env[MAX_PATH] = {};
    if (!path && GetEnvironmentVariableW(L"AIO_TIP_LOG", env, MAX_PATH)) path = env;
    if (!path) return;
    HANDLE file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    char line[512];
    SYSTEMTIME st;
    GetLocalTime(&st);
    int n = _snprintf_s(line, sizeof line, _TRUNCATE, "%02u:%02u:%02u.%03u %5lu %5lu hook: ", st.wHour, st.wMinute,
                        st.wSecond, st.wMilliseconds, GetCurrentProcessId(), GetCurrentThreadId());
    va_list args;
    va_start(args, format);
    n += _vsnprintf_s(line + n, sizeof line - n - 2, _TRUNCATE, format, args);
    va_end(args);
    line[n++] = '\r';
    line[n++] = '\n';
    DWORD w = 0;
    WriteFile(file, line, (DWORD)n, &w, nullptr);
    CloseHandle(file);
}

// The driver's hand-over, else (the driver started this Notepad) the environment.
void ReadConfig() {
    if (HANDLE mapping = OpenFileMappingW(FILE_MAP_READ, FALSE, kConfigName)) {
        if (const void* view = MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, sizeof(HookConfig))) {
            g_config = *static_cast<const HookConfig*>(view);
            g_config.log[MAX_PATH - 1] = 0;
            UnmapViewOfFile(view);
        }
        CloseHandle(mapping);
    }
    if (!g_config.langid) {
        char buf[16] = {};
        g_config.langid = GetEnvironmentVariableA("AIO_E2E_LANGID", buf, sizeof buf)
                              ? (DWORD)strtoul(buf, nullptr, 0)
                              : 0x0409;
    }
}

void LogActive(ITfInputProcessorProfileMgr* mgr, const char* when) {
    TF_INPUTPROCESSORPROFILE p = {};
    if (FAILED(mgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &p))) {
        Log("%s: no active profile", when);
        return;
    }
    const bool ours = IsEqualCLSID(p.clsid, kClsidTextService) && IsEqualGUID(p.guidProfile, kGuidProfile);
    Log("%s: type %lu, lang 0x%04x%s", when, p.dwProfileType, p.langid, ours ? ", AllInOneIME" : "");
}

// Activate AllInOneIME for this (Notepad's) thread, once.
void ActivateOnce() {
    if (g_done) return;
    g_done = true;
    ReadConfig();
    const LANGID lang = (LANGID)g_config.langid;
    Log("in Notepad: lang 0x%04x", lang);

    // The DLL's diagnostic log, in this process, for the run: the driver's file.
    if (g_config.log[0]) {
        g_hadLog = GetEnvironmentVariableW(L"AIO_TIP_LOG", g_previousLog, MAX_PATH) != 0;
        g_setLog = SetEnvironmentVariableW(L"AIO_TIP_LOG", g_config.log) != FALSE;
    }

    // Thread-local input settings must hold in *this* process (Notepad), so that activating the profile switches only
    // this thread, not the session. The driver sets this in its own process; each process keeps its own view, so we
    // set it here too (in memory), and put it back at the restore.
    BOOL threadLocal = FALSE;
    SystemParametersInfoW(SPI_GETTHREADLOCALINPUTSETTINGS, 0, &threadLocal, 0);
    if (!threadLocal) g_setThreadLocal = SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)TRUE, 0) != 0;
    Log("thread-local input settings in Notepad: %s", threadLocal ? "already on" : "turned on");
    const HRESULT coInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); // the GUI thread is already STA

    ITfInputProcessorProfileMgr* mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfileMgr, (void**)&mgr);
    if (SUCCEEDED(hr) && mgr) {
        g_havePrevious = SUCCEEDED(mgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &g_previous));
        LogActive(mgr, "before");
    }

    // Enable the profile for this thread's input language, so TSF (ctfmon) treats it as a selectable input method and
    // loads the TIP, then make it the thread's active profile.
    ITfInputProcessorProfiles* profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfiles, (void**)&profiles)) && profiles) {
        BOOL enabled = FALSE;
        profiles->IsEnabledLanguageProfile(kClsidTextService, lang, kGuidProfile, &enabled);
        HRESULT en = enabled ? S_OK : profiles->EnableLanguageProfile(kClsidTextService, lang, kGuidProfile, TRUE);
        Log("enabled for the user: %s (EnableLanguageProfile=0x%08lx)", enabled ? "already" : "now", en);
        HRESULT act = profiles->ActivateLanguageProfile(kClsidTextService, lang, kGuidProfile);
        Log("ActivateLanguageProfile(this thread) = 0x%08lx", act);
        profiles->Release();
    }

    if (mgr) {
        hr = mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, lang, kClsidTextService, kGuidProfile, nullptr,
                                  TF_IPPMF_FORPROCESS | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
        Log("ActivateProfile(Notepad's process, lang 0x%04x) = 0x%08lx", lang, hr);
        LogActive(mgr, "after");
        Log("AllInOneTIP.dll in Notepad: %s", GetModuleHandleW(L"AllInOneTIP.dll") ? "loaded" : "not loaded");
        mgr->Release();
    } else {
        Log("no ITfInputProcessorProfileMgr: 0x%08lx", hr);
    }
    if (SUCCEEDED(coInit)) CoUninitialize();
}

// Put back what ActivateOnce changed in Notepad, once.
void RestoreOnce() {
    if (!g_done || g_restored) return;
    g_restored = true;
    const HRESULT coInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ITfInputProcessorProfileMgr* mgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr, (void**)&mgr)) && mgr) {
        // The session's input method as the driver found it (with the default "same input method for every app"
        // Notepad follows it anyway), else this thread's from before.
        if (g_config.haveRestore || g_havePrevious) {
            const auto& p = g_config.haveRestore ? g_config.restore : g_previous;
            const HRESULT hr = mgr->ActivateProfile(p.dwProfileType, p.langid, p.clsid, p.guidProfile, p.hkl,
                                                    TF_IPPMF_FORPROCESS | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
            Log("restore: Notepad's process back on the session's input method (lang 0x%04x) = 0x%08lx", p.langid, hr);
        }
        LogActive(mgr, "restored");
        mgr->Release();
    }
    if (g_setThreadLocal) {
        SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)FALSE, 0);
        g_setThreadLocal = false;
        Log("restore: thread-local input settings off again in Notepad");
    }
    if (g_setLog) SetEnvironmentVariableW(L"AIO_TIP_LOG", g_hadLog ? g_previousLog : nullptr);
    // TSF released the TIP when the thread switched back: let COM unload it if nothing holds it any more.
    CoFreeUnusedLibrariesEx(0, 0);
    Log("restore: done; AllInOneTIP.dll in Notepad: %s", GetModuleHandleW(L"AllInOneTIP.dll") ? "still loaded"
                                                                                                 : "not loaded");
    if (SUCCEEDED(coInit)) CoUninitialize();
}

} // namespace

extern "C" __declspec(dllexport) LRESULT CALLBACK GetMsgProc(int code, WPARAM wParam, LPARAM lParam) {
    if (code == HC_ACTION) {
        if (!g_restoreMessage) g_restoreMessage = RegisterWindowMessageW(kRestoreMessage);
        const MSG* msg = reinterpret_cast<const MSG*>(lParam);
        if (msg && msg->message == g_restoreMessage) {
            RestoreOnce();
        } else {
            ActivateOnce();
        }
    }
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
