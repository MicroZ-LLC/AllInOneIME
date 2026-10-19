// e2ehook: a tiny WH_GETMESSAGE hook DLL the e2e driver injects into Notepad's GUI thread, so that it can activate the
// AllInOneIME profile *for that thread only*.
//
// A TSF text service has no HKL, so it can't be selected from outside with WM_INPUTLANGCHANGEREQUEST the way a keyboard
// layout can; and ITfInputProcessorProfileMgr::ActivateProfile acts on the calling thread. The only way to put the TIP
// on another app's thread — which is how the language bar switches one window when per-thread input settings are on —
// is to run ActivateProfile inside that app. The driver sets this hook on Notepad's thread and pumps one message; the
// first call activates the profile on Notepad's thread. With per-thread input settings on (the driver sets them), that
// touches only Notepad, never the session.
//
// It writes what it did to the file named by AIO_TIP_LOG (the driver sets it, Notepad inherits it), never any text.

#include <windows.h>
#include <msctf.h>

#include <cstdio>

namespace {

// Must match dllmain.cpp and the driver.
const CLSID kClsidTextService = {0xDBB94280, 0xC4C2, 0x4C91, {0x81, 0x6F, 0x79, 0xBB, 0x47, 0x1A, 0xFE, 0x56}};
const GUID kGuidProfile = {0x5BD6752B, 0x379B, 0x4ECD, {0x9B, 0x1B, 0x08, 0x19, 0xCB, 0xE5, 0x51, 0x71}};

HMODULE g_self = nullptr;
bool g_done = false;

void Log(const char* format, ...) {
    char path[MAX_PATH] = {};
    if (!GetEnvironmentVariableA("AIO_TIP_LOG", path, MAX_PATH)) return;
    HANDLE file = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
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

LANGID Langid() {
    char buf[16] = {};
    if (GetEnvironmentVariableA("AIO_E2E_LANGID", buf, sizeof buf)) {
        return (LANGID)strtoul(buf, nullptr, 0);
    }
    return 0x0409;
}

// Activate AllInOneIME for this (Notepad's) thread, once.
void ActivateOnce() {
    if (g_done) return;
    g_done = true;
    // Thread-local input settings must hold in *this* process (Notepad), so that activating the profile switches only
    // this thread, not the session. The driver sets this in its own process; each process keeps its own view, so we
    // set it here too (in memory). It dies with Notepad.
    BOOL threadLocal = FALSE;
    SystemParametersInfoW(SPI_GETTHREADLOCALINPUTSETTINGS, 0, &threadLocal, 0);
    if (!threadLocal) SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)TRUE, 0);
    Log("thread-local input settings in Notepad: %s", threadLocal ? "already on" : "turned on");
    const HRESULT coInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); // the GUI thread is already STA

    // Enable the profile for this thread's input language, so TSF (ctfmon) treats it as a selectable input method and
    // loads the TIP, then make it the thread's active profile.
    ITfInputProcessorProfiles* profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfiles, (void**)&profiles)) && profiles) {
        HRESULT en = profiles->EnableLanguageProfile(kClsidTextService, Langid(), kGuidProfile, TRUE);
        HRESULT by = profiles->EnableLanguageProfileByDefault(kClsidTextService, Langid(), kGuidProfile, TRUE);
        Log("EnableLanguageProfile=0x%08lx byDefault=0x%08lx", en, by);
        HRESULT act = profiles->ActivateLanguageProfile(kClsidTextService, Langid(), kGuidProfile);
        Log("ActivateLanguageProfile(this thread) = 0x%08lx", act);
        profiles->Release();
    }

    ITfInputProcessorProfileMgr* mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_ITfInputProcessorProfileMgr, (void**)&mgr);
    if (SUCCEEDED(hr) && mgr) {
        hr = mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, Langid(), kClsidTextService, kGuidProfile, nullptr,
                                  TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
        Log("ActivateProfile(this thread, lang 0x%04x) = 0x%08lx", Langid(), hr);
        mgr->Release();
    } else {
        Log("no ITfInputProcessorProfileMgr: 0x%08lx", hr);
    }
    if (SUCCEEDED(coInit)) CoUninitialize();
}

} // namespace

extern "C" __declspec(dllexport) LRESULT CALLBACK GetMsgProc(int code, WPARAM wParam, LPARAM lParam) {
    if (code == HC_ACTION) ActivateOnce();
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}
