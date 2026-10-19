// tsfstate: shows, and restores, the session's active keyboard input method. A test helper (run it in the user's
// session, like tiptest).
//
//   tsfstate                                   print the active keyboard profile and the input-settings scope
//   tsfstate --restore <langid> <clsid> <profile>
//                                              make that profile the session's active one again (TF_IPPMF_FORSESSION),
//                                              as the user switching back to it would
//
// With Windows' default "same input method for every app" (SPI_GETTHREADLOCALINPUTSETTINGS false), a profile activated
// on the foreground thread becomes the whole session's; tiptest restores the previous one itself, and this is the
// manual way back.

#include <windows.h>
#include <msctf.h>

#include <cstdio>
#include <cwchar>

namespace {

void PrintProfile(const char* what, const TF_INPUTPROCESSORPROFILE& p) {
    wchar_t clsid[64] = {}, profile[64] = {};
    StringFromGUID2(p.clsid, clsid, 64);
    StringFromGUID2(p.guidProfile, profile, 64);
    printf("%s: type %lu, lang 0x%04x, clsid %ls, profile %ls, hkl %p\n", what, p.dwProfileType, p.langid, clsid,
           profile, (void*)p.hkl);
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return 1;
    BOOL threadLocal = FALSE;
    SystemParametersInfoW(SPI_GETTHREADLOCALINPUTSETTINGS, 0, &threadLocal, 0);
    printf("input settings scope: %s\n", threadLocal ? "per app window (thread-local)" : "session (global)");

    ITfInputProcessorProfileMgr* mgr = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                IID_ITfInputProcessorProfileMgr, (void**)&mgr)) || !mgr) {
        printf("no ITfInputProcessorProfileMgr\n");
        return 1;
    }
    // A thread manager, so the profile manager answers for an active TSF thread.
    ITfThreadMgr* threadMgr = nullptr;
    TfClientId tid = 0;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr,
                                   (void**)&threadMgr)) && threadMgr) {
        threadMgr->Activate(&tid);
    }

    TF_INPUTPROCESSORPROFILE active = {};
    if (SUCCEEDED(mgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &active))) PrintProfile("active", active);

    int rc = 0;
    if (argc == 5 && wcscmp(argv[1], L"--restore") == 0) {
        const LANGID lang = static_cast<LANGID>(wcstoul(argv[2], nullptr, 0));
        CLSID clsid = {};
        GUID profile = {};
        if (FAILED(CLSIDFromString(argv[3], &clsid)) || FAILED(CLSIDFromString(argv[4], &profile))) {
            printf("bad clsid or profile\n");
            rc = 2;
        } else {
            const HRESULT hr = mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, lang, clsid, profile, nullptr,
                                                    TF_IPPMF_FORSESSION | TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
            printf("ActivateProfile(for the session): 0x%08lx\n", hr);
            if (SUCCEEDED(mgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &active))) PrintProfile("active now", active);
            rc = SUCCEEDED(hr) ? 0 : 1;
        }
    }
    if (threadMgr) {
        threadMgr->Deactivate();
        threadMgr->Release();
    }
    mgr->Release();
    CoUninitialize();
    return rc;
}
