// tiptest: drives the real, registered DLL through real TSF against a golden transcript.
//
// It creates its own ITfThreadMgr and an in-memory ITextStoreACP (TextStore), activates the AllInOneIME profile on its
// own thread (ITfInputProcessorProfileMgr::ActivateProfile, so TSF itself loads the DLL and calls ActivateEx), starts
// the FakeEngine on a background thread, sets the focus, and types the transcript's keys through ITfKeystrokeMgr
// (TestKeyDown, then KeyDown if the TIP eats it, as an app's message loop does). Where the TIP lets a key through, it
// plays the app and inserts the key's character. At the end it checks the document text and the frames the FakeEngine
// saw.
//
//   tiptest <golden.jsonl> [--direct] [--focus=foreground|associate|tsf]
//
// TSF routes keys only to the thread that owns the foreground window, so tiptest makes its (10x10) window the
// foreground one, with the input settings per thread for the run so the user's other apps keep their input method.
// --focus=associate (no foreground) and --focus=tsf (no window focus either) show what TSF then doesn't do. --direct
// skips TSF's dispatch altogether: it CoCreates the TIP itself and calls its sinks the way TSF would; it is only a
// fallback for a host where no window can take the foreground (see README).
//
// It must run in an interactive session (TSF and the DLL's §2.1 guard need a desktop); see README.

#include <windows.h>
#include <msctf.h>

#include <cstdarg>
#include <cstdio>
#include <string>

#include "TextStore.h"
#include "test/common/FakeEngine.h"
#include "test/common/Transcript.h"

using namespace aio::test;

// The DLL's CLSID and profile GUID (must match dllmain.cpp). Duplicated here so the test needn't link the DLL.
static const CLSID kClsidTextService = {0xDBB94280, 0xC4C2, 0x4C91, {0x81, 0x6F, 0x79, 0xBB, 0x47, 0x1A, 0xFE, 0x56}};
static const GUID kGuidProfile = {0x5BD6752B, 0x379B, 0x4ECD, {0x9B, 0x1B, 0x08, 0x19, 0xCB, 0xE5, 0x51, 0x71}};

namespace {

int g_failures = 0;
void Check(bool ok, const char* what) {
    printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
    if (!ok) ++g_failures;
}

void Pump(DWORD ms) {
    ULONGLONG end = GetTickCount64() + ms;
    for (;;) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        LONGLONG left = (LONGLONG)end - (LONGLONG)GetTickCount64();
        if (left <= 0) break;
        MsgWaitForMultipleObjects(0, nullptr, FALSE, (DWORD)left, QS_ALLINPUT);
    }
}

// A step marker in the DLL's diagnostic log (AIO_TIP_LOG), so the two read as one timeline.
void Mark(const char* format, ...) {
    char path[MAX_PATH] = {};
    if (!GetEnvironmentVariableA("AIO_TIP_LOG", path, MAX_PATH)) return;
    HANDLE file = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    char line[512];
    SYSTEMTIME st;
    GetLocalTime(&st);
    int n = _snprintf_s(line, sizeof line, _TRUNCATE, "%02u:%02u:%02u.%03u %5lu %5lu test: ", st.wHour, st.wMinute,
                        st.wSecond, st.wMilliseconds, GetCurrentProcessId(), GetCurrentThreadId());
    va_list args;
    va_start(args, format);
    n += _vsnprintf_s(line + n, sizeof line - n - 2, _TRUNCATE, format, args);
    va_end(args);
    line[n++] = '\r';
    line[n++] = '\n';
    DWORD written = 0;
    WriteFile(file, line, (DWORD)n, &written, nullptr);
    CloseHandle(file);
}

std::string Narrow(const std::wstring& s) {
    if (s.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0, nullptr, nullptr);
    std::string o(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), o.data(), n, nullptr, nullptr);
    return o;
}

// Sets the thread keyboard state so the DLL's GetKeyState/ToUnicodeEx see the key's modifiers.
void ApplyModifierState(const TypeKey& k) {
    BYTE state[256] = {};
    GetKeyboardState(state);
    const BYTE down = 0x80;
    auto set = [&](int vk, bool on) { state[vk] = on ? down : 0; };
    set(VK_SHIFT, k.shift);
    set(VK_LSHIFT, k.lshift || (k.shift && !k.rshift));
    set(VK_RSHIFT, k.rshift);
    set(VK_CONTROL, k.ctrl);
    set(VK_LCONTROL, k.lctrl || (k.ctrl && !k.rctrl));
    set(VK_RCONTROL, k.rctrl);
    set(VK_MENU, k.alt);
    set(VK_LMENU, k.lalt || (k.alt && !k.ralt));
    set(VK_RMENU, k.ralt);
    state[VK_CAPITAL] = 0;
    SetKeyboardState(state);
}

// The character a key would type now (so the test can play the app inserting a passed-through key).
std::wstring CharOf(WORD vk, WORD scan) {
    BYTE state[256] = {};
    GetKeyboardState(state);
    wchar_t buf[8] = {};
    int n = ToUnicodeEx(vk, scan, state, buf, 8, 0x4, GetKeyboardLayout(0));
    if (n == 1 && buf[0] >= 0x20 && buf[0] != 0x7F) return std::wstring(1, buf[0]);
    return {};
}

LPARAM MakeLParam(const TypeKey& k) {
    LPARAM l = 1;                       // repeat count
    l |= (LPARAM)(k.scan & 0xFF) << 16; // scan code
    if (k.extended) l |= (LPARAM)1 << 24;
    if (!k.down) l |= ((LPARAM)1 << 30) | ((LPARAM)1 << 31); // previous-down + transition
    return l;
}

template <class T>
void Release(T*& p) {
    if (p) { p->Release(); p = nullptr; }
}

// The language to activate the profile for: the thread's input language if the profile has it (so TSF needn't switch
// the thread's keyboard layout, and nothing new is loaded into the session), else en-US.
LANGID ProfileLanguage() {
    const LANGID current = LOWORD(reinterpret_cast<uintptr_t>(GetKeyboardLayout(0)));
    if (current == 0x0409 || current == 0x0804) return current;
    return 0x0409;
}

// The session's input state, put back as it was found (see main).
TF_INPUTPROCESSORPROFILE g_previousProfile = {};
bool g_havePreviousProfile = false;
bool g_restoreGlobalInput = false;

void RestoreGlobalInput() {
    if (g_restoreGlobalInput) {
        g_restoreGlobalInput = false;
        SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)FALSE, 0);
    }
}

// Makes the window the foreground one. A scheduled task's process may not take the foreground by itself; attached to
// the foreground thread's input for the call, it may.
void TakeForeground(HWND wnd) {
    ShowWindow(wnd, SW_SHOWNOACTIVATE);
    BOOL ok = SetForegroundWindow(wnd);
    if (!ok || GetForegroundWindow() != wnd) {
        const HWND fg = GetForegroundWindow();
        const DWORD fgThread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
        const DWORD me = GetCurrentThreadId();
        if (fgThread && fgThread != me) AttachThreadInput(me, fgThread, TRUE);
        ok = SetForegroundWindow(wnd);
        BringWindowToTop(wnd);
        if (fgThread && fgThread != me) AttachThreadInput(me, fgThread, FALSE);
    }
    Check(GetForegroundWindow() == wnd, "the test window has the foreground");
}

// Ends our composition the way an app does (§5.5 `terminated`).
void TerminateComposition(ITfContext* context) {
    ITfContextOwnerCompositionServices* services = nullptr;
    if (SUCCEEDED(context->QueryInterface(IID_ITfContextOwnerCompositionServices, (void**)&services)) && services) {
        HRESULT hr = services->TerminateComposition(nullptr);
        printf("    terminate composition: hr=0x%08lx\n", hr);
        services->Release();
    }
}

} // namespace

int main(int argc, char** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    // A hard watchdog, so the test can never hang a scheduled task.
    HANDLE wd = CreateThread(nullptr, 0, [](void*) -> DWORD {
        Sleep(100000);
        fprintf(stderr, "watchdog: timed out\n");
        RestoreGlobalInput();
        ExitProcess(2);
    }, nullptr, 0, nullptr);
    if (wd) CloseHandle(wd);

    std::string goldenPath;
    bool direct = false;
    std::string focusMode = "foreground";
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--direct") == 0) direct = true;
        else if (strncmp(argv[i], "--focus=", 8) == 0) focusMode = argv[i] + 8;
        else goldenPath = argv[i];
    }
    if (goldenPath.empty()) {
        printf("usage: tiptest <golden.jsonl> [--direct] [--focus=foreground|associate|tsf]\n");
        return 2;
    }
    printf("tiptest: %s (%s)\n", goldenPath.c_str(), direct ? "direct sink calls" : "real TSF dispatch");

    DWORD session = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &session);
    printf("session %lu\n", session);

    Transcript t;
    std::string err;
    if (!Transcript::Load(goldenPath, t, err)) {
        printf("  [FAIL] load transcript: %s\n", err.c_str());
        printf("\nFAIL (1 failures)\n");
        return 1;
    }

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    WNDCLASSEXW wc = {sizeof wc};
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"TipTestWnd";
    RegisterClassExW(&wc);
    HWND wnd = CreateWindowExW(0, L"TipTestWnd", L"tiptest", WS_OVERLAPPED, 0, 0, 10, 10, nullptr, nullptr,
                               wc.hInstance, nullptr);

    // The field's input scope: IS_PASSWORD for a secure golden (so the DLL detects §8 secure), else IS_DEFAULT (a plain
    // text field, reported as scopes:[0]). The store reports it through GUID_PROP_INPUTSCOPE.
    const InputScope kScope = t.secure ? IS_PASSWORD : IS_DEFAULT;

    // The DLL in this process talks to this test's own pipe (AIO_TIP_PIPE), never to the DLLs in the user's apps.
    const std::wstring testPipe = FakeEngine::RealPipeName(FakeEngine::CurrentUserSid()) + L"-tiptest-" +
                                  std::to_wstring(GetCurrentProcessId());
    SetEnvironmentVariableW(L"AIO_TIP_PIPE", testPipe.c_str());
    FakeEngine engine(t, testPipe);
    engine.Start();
    while (!engine.PipeReady()) Sleep(5);

    ITfThreadMgr* threadMgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr,
                                  (void**)&threadMgr);
    Check(SUCCEEDED(hr) && threadMgr, "create ITfThreadMgr");
    if (!threadMgr) {
        // Session 0 (an OpenSSH session, a service) has no TSF at all: run tiptest in the user's session (README).
        printf("    CoCreateInstance(CLSID_TF_ThreadMgr) hr=0x%08lx, session %lu\n\nFAIL (%d failures)\n", hr, session,
               g_failures);
        RestoreGlobalInput();
        return 1;
    }

    TfClientId appClientId = TF_CLIENTID_NULL;
    Check(SUCCEEDED(threadMgr->Activate(&appClientId)), "activate the thread manager (app)");

    // The registered profile, as TSF lists it (proves DllRegisterServer).
    const LANGID lang = ProfileLanguage();
    ITfInputProcessorProfileMgr* profileMgr = nullptr;
    CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr,
                     (void**)&profileMgr);
    if (profileMgr) {
        TF_INPUTPROCESSORPROFILE profile = {};
        hr = profileMgr->GetProfile(TF_PROFILETYPE_INPUTPROCESSOR, lang, kClsidTextService, kGuidProfile, nullptr,
                                    &profile);
        Check(SUCCEEDED(hr), "the AllInOneIME profile is registered");
        printf("    language 0x%04x, flags 0x%lx (%s)\n", lang, profile.dwFlags,
               (profile.dwFlags & TF_IPP_FLAG_ENABLED) ? "enabled" : "not enabled");
        ITfInputProcessorProfiles* profiles = nullptr;
        if (SUCCEEDED(profileMgr->QueryInterface(IID_ITfInputProcessorProfiles, (void**)&profiles)) && profiles) {
            BSTR desc = nullptr;
            const bool ok = SUCCEEDED(profiles->GetLanguageProfileDescription(kClsidTextService, lang, kGuidProfile,
                                                                              &desc)) &&
                            desc && wcscmp(desc, L"AllInOneIME") == 0;
            Check(ok, "its name reads back as AllInOneIME");
            if (desc) SysFreeString(desc);
            profiles->Release();
        }
    } else {
        Check(false, "ITfInputProcessorProfileMgr");
    }

    ITfDocumentMgr* docMgr = nullptr;
    ITfDocumentMgr* otherDocMgr = nullptr; // an empty document to move the focus to (the blur)
    Check(SUCCEEDED(threadMgr->CreateDocumentMgr(&docMgr)) && docMgr, "create a document manager");
    threadMgr->CreateDocumentMgr(&otherDocMgr);

    TextStore* store = new TextStore(wnd, kScope);
    ITfContext* context = nullptr;
    TfEditCookie ecStore = 0;
    hr = docMgr->CreateContext(appClientId, 0, static_cast<ITextStoreACP*>(store), &context, &ecStore);
    Check(SUCCEEDED(hr) && context, "create a context on the in-memory store");
    if (context) docMgr->Push(context);

    ITfTextInputProcessorEx* tip = nullptr; // --direct only
    ITfThreadMgrEventSink* tmSink = nullptr;
    ITfKeyEventSink* keySink = nullptr;
    ITfKeystrokeMgr* keystrokes = nullptr;
    bool activated = false;

    if (!direct) {
        // TSF routes keystrokes only to the thread that owns the foreground window, and with Windows' default input
        // settings ("the same input method for every app", SPI_GETTHREADLOCALINPUTSETTINGS false) the foreground
        // thread's input method becomes the whole session's: the user's other apps would switch to AllInOneIME too.
        // So for the run the settings are made per-thread (in memory only, never saved), and put back at the end.
        BOOL threadLocal = FALSE;
        SystemParametersInfoW(SPI_GETTHREADLOCALINPUTSETTINGS, 0, &threadLocal, 0);
        if (profileMgr && SUCCEEDED(profileMgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &g_previousProfile))) {
            g_havePreviousProfile = true;
        }
        if (!threadLocal) {
            g_restoreGlobalInput = SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)TRUE, 0) != 0;
            Check(g_restoreGlobalInput, "input settings per thread for the run (SPI_SETTHREADLOCALINPUTSETTINGS)");
        }

        // The app's focus, before the TIP comes: the window has the Win32 focus and TSF's follows it to the document
        // (AssociateFocus). The foreground is taken before the profile changes, so nothing it attaches to sees the
        // change. --focus=associate leaves out the foreground, --focus=tsf the window too (ITfThreadMgr::SetFocus
        // only), to show what TSF then doesn't do.
        Mark("focus (%s)", focusMode.c_str());
        if (wnd && focusMode != "tsf") {
            ShowWindow(wnd, SW_SHOWNOACTIVATE);
            ITfDocumentMgr* prev = nullptr;
            threadMgr->AssociateFocus(wnd, docMgr, &prev);
            Release(prev);
            if (focusMode == "foreground") TakeForeground(wnd);
            SetFocus(wnd);
            printf("    the window has the focus: %s; the foreground: %s\n", GetFocus() == wnd ? "yes" : "no",
                   GetForegroundWindow() == wnd ? "yes" : "no");
        } else {
            threadMgr->SetFocus(docMgr);
        }
        Pump(100);

        // TSF loads the DLL and activates it for this thread only (no FORPROCESS/FORSESSION).
        Mark("activate the profile");
        hr = profileMgr ? profileMgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, lang, kClsidTextService,
                                                      kGuidProfile, nullptr, TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE)
                        : E_FAIL;
        Check(SUCCEEDED(hr), "activate the AllInOneIME profile on this thread (ActivateProfile)");
        if (FAILED(hr)) printf("    ActivateProfile hr=0x%08lx\n", hr);
        TF_INPUTPROCESSORPROFILE active = {};
        const bool ours = profileMgr && SUCCEEDED(profileMgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &active)) &&
                          IsEqualCLSID(active.clsid, kClsidTextService);
        Check(ours, "TSF reports AllInOneIME as the thread's active keyboard TIP");
        activated = ours;
        threadMgr->QueryInterface(IID_ITfKeystrokeMgr, (void**)&keystrokes);
        Check(keystrokes != nullptr, "ITfKeystrokeMgr");
    } else {
        // Play TSF: CoCreate the registered DLL, activate it, and call its sinks below.
        hr = CoCreateInstance(kClsidTextService, nullptr, CLSCTX_INPROC_SERVER, IID_ITfTextInputProcessorEx,
                              (void**)&tip);
        Check(SUCCEEDED(hr) && tip, "CoCreate the registered AllInOneIME TIP");
        if (tip) {
            hr = tip->ActivateEx(threadMgr, appClientId, 0);
            activated = SUCCEEDED(hr);
            Check(activated, "activate the TIP (ActivateEx)");
            tip->QueryInterface(IID_ITfThreadMgrEventSink, (void**)&tmSink);
            tip->QueryInterface(IID_ITfKeyEventSink, (void**)&keySink);
        }
        Check(tmSink && keySink, "the TIP exposes the thread-manager and key-event sinks");
    }
    printf("    AIO_TIP_LOG=%s\n", getenv("AIO_TIP_LOG") ? getenv("AIO_TIP_LOG") : "(unset)");

    // Let the handshake finish, so `open`/`focus` go out on the live connection (the DLL sends them on `welcome` for a
    // context focused before it). --direct: the handshake first, then the focus.
    Pump(800);
    if (direct) {
        threadMgr->SetFocus(docMgr);
        if (tmSink) tmSink->OnSetFocus(docMgr, nullptr);
        Pump(300);
    }
    Mark("keys");

    int typed = 0, eatenCount = 0;
    if (activated && context && (keystrokes || keySink)) {
        for (const auto& step : t.steps) {
            if (step.kind == Step::Kind::terminate) {
                TerminateComposition(context);
                Pump(200);
                continue;
            }
            if (step.kind == Step::Kind::wait) {
                Pump(step.waitMs);
                continue;
            }
            const TypeKey& k = step.key;
            ApplyModifierState(k);
            const LPARAM lp = MakeLParam(k);
            BOOL eaten = FALSE;
            if (k.down) {
                BOOL tested = FALSE;
                for (int test = 0; test < (t.doubleTest ? 2 : 1); ++test) {
                    if (keystrokes) keystrokes->TestKeyDown(k.vk, lp, &tested);
                    else keySink->OnTestKeyDown(context, k.vk, lp, &tested);
                }
                if (tested) {
                    if (keystrokes) keystrokes->KeyDown(k.vk, lp, &eaten);
                    else keySink->OnKeyDown(context, k.vk, lp, &eaten);
                }
                if (!eaten) {
                    std::wstring ch = CharOf(k.vk, k.scan);
                    if (!ch.empty()) store->ExternalReplace(store->SelStart(), store->SelEnd(), ch);
                }
            } else {
                BOOL tested = FALSE;
                for (int test = 0; test < (t.doubleTest ? 2 : 1); ++test) {
                    if (keystrokes) keystrokes->TestKeyUp(k.vk, lp, &tested);
                    else keySink->OnTestKeyUp(context, k.vk, lp, &tested);
                }
                if (tested) {
                    if (keystrokes) keystrokes->KeyUp(k.vk, lp, &eaten);
                    else keySink->OnKeyUp(context, k.vk, lp, &eaten);
                }
            }
            ++typed;
            if (eaten) ++eatenCount;
            Pump(40);
        }
    }
    printf("    typed %d keys, %d eaten by the TIP\n", typed, eatenCount);
    ApplyModifierState(TypeKey{});
    Pump(300);

    // Blur (the focus moves to another document), then close (the context is popped).
    Mark("blur");
    if (otherDocMgr) threadMgr->SetFocus(otherDocMgr);
    if (direct && tmSink) tmSink->OnSetFocus(otherDocMgr, docMgr);
    Pump(200);
    if (direct && tmSink && context) tmSink->OnPopContext(context);
    Mark("pop");
    if (docMgr) docMgr->Pop(TF_POPF_ALL);
    Pump(200);

    if (t.hasExpectDocument) {
        const bool match = store->Text() == t.expectDocument;
        Check(match, "the document matches expect-document");
        printf("    expected \"%s\"  actual \"%s\"\n", Narrow(t.expectDocument).c_str(), Narrow(store->Text()).c_str());
    } else {
        printf("  document: \"%s\"\n", Narrow(store->Text()).c_str());
    }

    // Teardown. The thread's input method goes back to what it was (TSF deactivates the TIP), the window goes (and
    // with it the foreground), and only then do the input settings go back to the session's.
    Mark("deactivate");
    if (tip && activated) tip->Deactivate();
    if (!direct && profileMgr && g_havePreviousProfile) {
        const auto& p = g_previousProfile;
        profileMgr->ActivateProfile(p.dwProfileType, p.langid, p.clsid, p.guidProfile, p.hkl,
                                    TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
    }
    Release(tmSink);
    Release(keySink);
    Release(tip);
    Release(keystrokes);
    Release(context);
    Release(docMgr);
    Release(otherDocMgr);
    if (threadMgr) threadMgr->Deactivate();
    Release(profileMgr);
    Release(threadMgr);
    store->Release();
    if (wnd) DestroyWindow(wnd);
    Pump(100);
    RestoreGlobalInput();

    engine.Join();
    const auto& r = engine.Result();
    printf("engine: %s\n", r.summary.c_str());
    for (const auto& n : r.notes) printf("    . %s\n", n.c_str());
    Check(r.ok, "the fake engine saw exactly the golden's frames");

    if (SUCCEEDED(hrInit)) CoUninitialize();

    printf("\n%s (%d failures)\n", g_failures == 0 ? "PASS" : "FAIL", g_failures);
    return g_failures == 0 ? 0 : 1;
}
