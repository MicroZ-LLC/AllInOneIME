// e2edriver: the end-to-end driver (M3, M5-M7). It runs in the logged-on user's session (a scheduled task from SSH;
// TSF and SendInput need an interactive desktop, see README), starts the real engine and real, registered DLL, and
// types into real Notepad through AllInOneIME, reading the result back through UI Automation.
//
//   e2edriver --engine <AllInOneIMEEngine.exe> [--scenario improve|plain|pinyin|ai] [--fixture <provider.json>]
//             [--plain <text>] [--engine-arg <arg>]... [--shots <dir>] [--engine-log <file>] [--langid 0x0409]
//             [--timeout-ms 60000] [--expect-tip <dll>] [--probe] [--host]
//
// The scenarios (what is typed, and what the document must then hold):
//   improve  "hi @improve helo", Return, "1" with the engine in test mode and the scripted provider (--fixture):
//            "hi Hello." (the default);
//   plain    the --plain text, as typed;
//   pinyin   a tap of Shift (typing starts in English, as for a new user), "nihao", Space, "nihao", "1": "你好你好";
//   ai       "@improve hello", Return, the versions streamed from the provider the engine's settings name (the run's
//            stub on localhost), "1": "Hello there.".
// For all but plain it checks the engine's candidate window: up while the candidates or the results are, a no-activate
// topmost tool window that never took the foreground from the target, and captured as a PNG into --shots.
//
// What it does:
//   1. starts the engine in this session (so it and the DLL pass §2.1's same-session client check): for improve in test
//      mode with the scripted provider on the system clock, so the @improve stream plays out in real time; otherwise as
//      it runs for a user (no test mode), with the --engine-arg arguments (the run's settings file, librime's user
//      folder, keys from the environment);
//   2. enables per-thread input settings for the session (in memory), so switching an input method changes only the
//      window it is done on, never every app (see the README's warning about the session-wide input method);
//   3. starts Notepad and finds its editable document through UIA;
//   4. activates the AllInOneIME profile for Notepad's process only, from inside it (the e2ehook), never for the
//      session; --expect-tip names the DLL that must then be loaded there (an installed copy);
//   5. types "hi @improve helo", Return, "1" (or the --plain text) with SendInput — each key only while Notepad has the
//      foreground, and stopping at once if it ever doesn't, so no key reaches another window;
//   6. reads Notepad's text with UIA TextPattern and checks it is "hi Hello." (or the --plain text, passed through).
//
// At the end it puts Notepad back on the session's input method, closes its own tab, stops the engine, and restores
// the per-thread input setting. --probe stops after step 4 and reports what it found (used to settle how the switch
// works on this machine); it changes nothing lasting either. --host types into an EDIT control of its own instead.

#include <windows.h>
#include <msctf.h>
#include <tlhelp32.h>
#include <uiautomation.h>

#include <wincodec.h>

#include <cstdio>
#include <cstdarg>
#include <string>
#include <vector>

// The DLL's CLSID and profile GUID (must match dllmain.cpp). Duplicated so the driver needn't link the DLL.
static const CLSID kClsidTextService = {0xDBB94280, 0xC4C2, 0x4C91, {0x81, 0x6F, 0x79, 0xBB, 0x47, 0x1A, 0xFE, 0x56}};
static const GUID kGuidProfile = {0x5BD6752B, 0x379B, 0x4ECD, {0x9B, 0x1B, 0x08, 0x19, 0xCB, 0xE5, 0x51, 0x71}};

namespace {

int g_failures = 0;
FILE* g_out = stdout;

void Log(const char* format, ...) {
    char line[1024];
    SYSTEMTIME st;
    GetLocalTime(&st);
    int n = _snprintf_s(line, sizeof line, _TRUNCATE, "%02u:%02u:%02u.%03u ", st.wHour, st.wMinute, st.wSecond,
                        st.wMilliseconds);
    va_list args;
    va_start(args, format);
    _vsnprintf_s(line + n, sizeof line - n, _TRUNCATE, format, args);
    va_end(args);
    printf("%s\n", line);

    // Also into the DLL's diagnostic log (AIO_TIP_LOG), so the two read as one timeline.
    char path[MAX_PATH] = {};
    if (GetEnvironmentVariableA("AIO_TIP_LOG", path, MAX_PATH)) {
        HANDLE file = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                  nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file != INVALID_HANDLE_VALUE) {
            std::string s = std::string(line) + "\r\n";
            DWORD w = 0;
            WriteFile(file, s.data(), (DWORD)s.size(), &w, nullptr);
            CloseHandle(file);
        }
    }
}

void Check(bool ok, const char* what) {
    Log("  [%s] %s", ok ? "ok" : "FAIL", what);
    if (!ok) ++g_failures;
}

template <class T>
void Release(T*& p) {
    if (p) { p->Release(); p = nullptr; }
}

std::string Narrow(const std::wstring& s) {
    if (s.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0, nullptr, nullptr);
    std::string o(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), o.data(), n, nullptr, nullptr);
    return o;
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

std::wstring ImageName(DWORD pid) {
    HANDLE p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return {};
    wchar_t buf[MAX_PATH];
    DWORD n = MAX_PATH;
    std::wstring name;
    if (QueryFullProcessImageNameW(p, 0, buf, &n)) {
        name = buf;
        size_t slash = name.find_last_of(L"\\/");
        if (slash != std::wstring::npos) name = name.substr(slash + 1);
    }
    CloseHandle(p);
    return name;
}

// ---- Notepad through UIA --------------------------------------------------------------------------------------

struct Found {
    HWND window = nullptr;
    DWORD pid = 0;
    IUIAutomationElement* edit = nullptr; // the editable document (TextPattern)
};

bool IEquals(const std::wstring& a, const wchar_t* b) { return _wcsicmp(a.c_str(), b) == 0; }

// Visible top-level windows owned by a Notepad.exe process (the one we launched, or the one its stub spawned). Store
// Notepad shows more than one window of class "Notepad"; the caller tries each for an editable document.
struct Hunt {
    std::vector<HWND> windows;
    DWORD pid = 0;
};

BOOL CALLBACK FindNotepadWindow(HWND hwnd, LPARAM lp) {
    if (!IsWindowVisible(hwnd)) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (!IEquals(ImageName(pid), L"notepad.exe")) return TRUE;  // Windows filenames aren't case-sensitive
    if (GetWindow(hwnd, GW_OWNER)) return TRUE;                 // a top-level editor window, not an owned popup
    auto* hunt = reinterpret_cast<Hunt*>(lp);
    hunt->windows.push_back(hwnd);
    hunt->pid = pid;
    return TRUE;
}

std::wstring ReadDocument(IUIAutomationElement* edit);

// The editable document inside `window` whose text equals `want` (a control with the Text pattern). We only ever type
// into the document we seeded with a unique marker, never the user's: if no document matches, we do not type at all.
// Classic Notepad is an Edit/Document; the Store app is a RichEdit; UIA finds either.
IUIAutomationElement* FindSeededEdit(IUIAutomation* uia, HWND window, const std::wstring& want) {
    IUIAutomationElement* root = nullptr;
    if (FAILED(uia->ElementFromHandle(window, &root)) || !root) return nullptr;
    IUIAutomationCondition* hasText = nullptr;
    VARIANT vTrue;
    vTrue.vt = VT_BOOL;
    vTrue.boolVal = VARIANT_TRUE;
    uia->CreatePropertyCondition(UIA_IsTextPatternAvailablePropertyId, vTrue, &hasText);
    IUIAutomationElement* found = nullptr;
    if (hasText) {
        IUIAutomationElementArray* all = nullptr;
        if (SUCCEEDED(root->FindAll(TreeScope_Subtree, hasText, &all)) && all) {
            int count = 0;
            all->get_Length(&count);
            for (int i = 0; i < count && !found; ++i) {
                IUIAutomationElement* e = nullptr;
                if (SUCCEEDED(all->GetElement(i, &e)) && e) {
                    if (ReadDocument(e) == want) found = e;  // our seeded document
                    else e->Release();
                }
            }
            all->Release();
        }
        hasText->Release();
    }
    Release(root);
    return found;
}

std::wstring ReadDocument(IUIAutomationElement* edit) {
    if (!edit) return {};
    IUnknown* unk = nullptr;
    if (FAILED(edit->GetCurrentPattern(UIA_TextPatternId, &unk)) || !unk) return {};
    IUIAutomationTextPattern* text = nullptr;
    unk->QueryInterface(__uuidof(IUIAutomationTextPattern), (void**)&text);
    unk->Release();
    if (!text) return {};
    std::wstring result;
    IUIAutomationTextRange* range = nullptr;
    if (SUCCEEDED(text->get_DocumentRange(&range)) && range) {
        BSTR s = nullptr;
        if (SUCCEEDED(range->GetText(-1, &s)) && s) {
            result.assign(s, SysStringLen(s));
            SysFreeString(s);
        }
        range->Release();
    }
    text->Release();
    // Notepad's document ends with the line the caret is on; trim a trailing CR/LF the control may add.
    while (!result.empty() && (result.back() == L'\r' || result.back() == L'\n')) result.pop_back();
    return result;
}

bool SetUiaFocus(IUIAutomationElement* edit) {
    return edit && SUCCEEDED(edit->SetFocus());
}

// ---- the foreground ------------------------------------------------------------------------------------------

// Make `window` the foreground window (a scheduled task's process may need to attach to the current foreground
// thread's input to be allowed to).
void TakeForeground(HWND window) {
    ShowWindow(window, SW_SHOW);
    SetForegroundWindow(window);
    if (GetForegroundWindow() != window) {
        HWND fg = GetForegroundWindow();
        DWORD fgThread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
        DWORD me = GetCurrentThreadId();
        if (fgThread && fgThread != me) AttachThreadInput(me, fgThread, TRUE);
        SetForegroundWindow(window);
        BringWindowToTop(window);
        if (fgThread && fgThread != me) AttachThreadInput(me, fgThread, FALSE);
    }
}

// The foreground window belongs to `pid` (our Notepad): the guard before every SendInput, so a key can only ever go
// to the Notepad this driver started.
bool ForegroundIsNotepad(DWORD pid) {
    HWND fg = GetForegroundWindow();
    if (!fg) return false;
    DWORD fgPid = 0;
    GetWindowThreadProcessId(fg, &fgPid);
    return fgPid == pid;
}

// ---- keys (SendInput) ----------------------------------------------------------------------------------------

void SendKey(WORD vk, bool down) {
    INPUT in = {};
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = vk;
    in.ki.wScan = (WORD)MapVirtualKeyW(vk, MAPVK_VK_TO_VSC);
    in.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
    SendInput(1, &in, sizeof in);
}

struct UsKey {
    WORD vk;
    bool shift;
};

// A character on the US physical layout (both 0x0409 and 0x0804 use it).
bool KeyForChar(wchar_t c, UsKey& out) {
    if (c >= L'a' && c <= L'z') { out = {(WORD)(L'A' + (c - L'a')), false}; return true; }
    if (c >= L'A' && c <= L'Z') { out = {(WORD)c, true}; return true; }
    if (c >= L'0' && c <= L'9') { out = {(WORD)c, false}; return true; }
    switch (c) {
    case L' ': out = {VK_SPACE, false}; return true;
    case L'@': out = {'2', true}; return true;
    case L'.': out = {VK_OEM_PERIOD, false}; return true;
    default: return false;
    }
}

// Types `text` into the foreground, a key at a time, checking the foreground is our Notepad before each. False (and it
// stops) if the foreground is ever not Notepad: no key goes anywhere else.
bool TypeText(const std::wstring& text, DWORD pid) {
    for (wchar_t c : text) {
        UsKey k;
        if (!KeyForChar(c, k)) { Log("  no key for U+%04X", (unsigned)c); return false; }
        if (!ForegroundIsNotepad(pid)) {
            Check(false, "Notepad has the foreground before the key");
            return false;
        }
        if (k.shift) SendKey(VK_SHIFT, true);
        SendKey(k.vk, true);
        SendKey(k.vk, false);
        if (k.shift) SendKey(VK_SHIFT, false);
        Pump(90);
    }
    return true;
}

bool TapKey(WORD vk, DWORD pid) {
    if (!ForegroundIsNotepad(pid)) {
        Check(false, "Notepad has the foreground before the key");
        return false;
    }
    SendKey(vk, true);
    SendKey(vk, false);
    Pump(90);
    return true;
}

// A tap of the left Shift key on its own (down, up, nothing between): AllInOneIME's switch between English and 中文.
bool TapShift(DWORD pid) {
    if (!ForegroundIsNotepad(pid)) {
        Check(false, "Notepad has the foreground before the key");
        return false;
    }
    SendKey(VK_LSHIFT, true);
    Pump(60);
    SendKey(VK_LSHIFT, false);
    Pump(250);
    return true;
}

// Ctrl+`vk` (a shortcut the app, not the IME, handles: select-all, save, close-tab).
bool Chord(WORD mod, WORD vk, DWORD pid) {
    if (!ForegroundIsNotepad(pid)) {
        Check(false, "Notepad has the foreground before the chord");
        return false;
    }
    SendKey(mod, true);
    SendKey(vk, true);
    SendKey(vk, false);
    SendKey(mod, false);
    Pump(120);
    return true;
}

// The TIP DLLs loaded in process `pid`, by path (it loads when AllInOneIME engages; an installed copy and a build's
// can both be there, in a Notepad that outlived an earlier run).
std::vector<std::wstring> TipModules(DWORD pid) {
    std::vector<std::wstring> paths;
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pid);
    if (snap == INVALID_HANDLE_VALUE) return paths;
    MODULEENTRY32W me = {sizeof me};
    if (Module32FirstW(snap, &me)) {
        do {
            if (_wcsicmp(me.szModule, L"AllInOneTIP.dll") == 0) paths.push_back(me.szExePath);
        } while (Module32NextW(snap, &me));
    }
    CloseHandle(snap);
    return paths;
}

bool TipLoaded(DWORD pid) { return !TipModules(pid).empty(); }

std::string TipModulesText(DWORD pid) {
    std::string text;
    for (const auto& path : TipModules(pid)) text += (text.empty() ? "" : ", ") + Narrow(path);
    return text.empty() ? "none" : text;
}

// ---- the engine's candidate window ---------------------------------------------------------------------------

struct PanelHunt {
    DWORD pid = 0;
    HWND found = nullptr;
};

BOOL CALLBACK FindPanelWindow(HWND hwnd, LPARAM lp) {
    auto* hunt = reinterpret_cast<PanelHunt*>(lp);
    wchar_t name[64] = {};
    GetClassNameW(hwnd, name, 64);
    if (wcscmp(name, L"AllInOneIME.CandidateWindow") != 0) return TRUE;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != hunt->pid) return TRUE;
    hunt->found = hwnd;
    return FALSE;
}

// The engine's candidate window (its class, in the engine's process).
HWND FindPanel(DWORD enginePid) {
    PanelHunt hunt;
    hunt.pid = enginePid;
    EnumWindows(FindPanelWindow, reinterpret_cast<LPARAM>(&hunt));
    return hunt.found;
}

// What the screen shows where `window` is, as a PNG (WIC): the layered window over what is behind its corners.
bool CaptureWindowPng(HWND window, const std::wstring& path) {
    RECT r;
    if (!GetWindowRect(window, &r)) return false;
    int w = r.right - r.left, h = r.bottom - r.top;
    if (w <= 0 || h <= 0) return false;
    HDC screen = GetDC(nullptr);
    HDC memory = CreateCompatibleDC(screen);
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof info.bmiHeader;
    info.bmiHeader.biWidth = w;
    info.bmiHeader.biHeight = -h;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    bool ok = false;
    if (bitmap) {
        HGDIOBJ old = SelectObject(memory, bitmap);
        ok = BitBlt(memory, 0, 0, w, h, screen, r.left, r.top, SRCCOPY | CAPTUREBLT) != 0;
        SelectObject(memory, old);
        // Opaque: the screen's pixels have no alpha of their own.
        for (int i = 0; ok && i < w * h; ++i) static_cast<BYTE*>(bits)[i * 4 + 3] = 255;
    }
    if (ok) {
        ok = false;
        IWICImagingFactory* wic = nullptr;
        IWICBitmap* source = nullptr;
        IWICStream* stream = nullptr;
        IWICBitmapEncoder* encoder = nullptr;
        IWICBitmapFrameEncode* frame = nullptr;
        if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic))) &&
            SUCCEEDED(wic->CreateBitmapFromMemory(w, h, GUID_WICPixelFormat32bppBGRA, w * 4, w * h * 4,
                                                  static_cast<BYTE*>(bits), &source)) &&
            SUCCEEDED(wic->CreateStream(&stream)) && SUCCEEDED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE)) &&
            SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) &&
            SUCCEEDED(encoder->Initialize(stream, WICBitmapEncoderNoCache)) &&
            SUCCEEDED(encoder->CreateNewFrame(&frame, nullptr)) && SUCCEEDED(frame->Initialize(nullptr)) &&
            SUCCEEDED(frame->SetSize(w, h))) {
            WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
            ok = SUCCEEDED(frame->SetPixelFormat(&format)) && SUCCEEDED(frame->WriteSource(source, nullptr)) &&
                 SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
        }
        Release(frame);
        Release(encoder);
        Release(stream);
        Release(source);
        Release(wic);
    }
    if (bitmap) DeleteObject(bitmap);
    DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    return ok;
}

// The engine's candidate window must be up: a no-activate, topmost tool window that left the foreground to the target
// (`targetPid`'s window), captured into `shot`.
bool CheckPanel(DWORD enginePid, DWORD targetPid, const std::wstring& shot, const char* what) {
    HWND panel = nullptr;
    for (int i = 0; i < 60 && !(panel && IsWindowVisible(panel)); ++i) {
        panel = FindPanel(enginePid);
        if (!(panel && IsWindowVisible(panel))) Pump(50);
    }
    bool up = panel && IsWindowVisible(panel);
    Log("  candidate window (%s): %s", what, up ? "up" : "not up");
    Check(up, "the engine's candidate window is up");
    if (!up) return false;
    RECT r;
    GetWindowRect(panel, &r);
    Log("  candidate window %p at (%ld, %ld), %ld x %ld", (void*)panel, r.left, r.top, r.right - r.left, r.bottom - r.top);
    LONG_PTR ex = GetWindowLongPtrW(panel, GWL_EXSTYLE);
    Check((ex & WS_EX_NOACTIVATE) && (ex & WS_EX_TOPMOST) && (ex & WS_EX_TOOLWINDOW) && (ex & WS_EX_LAYERED),
          "it is a layered, no-activate, topmost tool window");
    HWND fg = GetForegroundWindow();
    DWORD fgPid = 0;
    if (fg) GetWindowThreadProcessId(fg, &fgPid);
    Check(fg != panel && fgPid == targetPid, "it never took the foreground from the window typed in");
    if (!shot.empty()) {
        bool saved = CaptureWindowPng(panel, shot);
        Check(saved, "captured it as a PNG");
        if (saved) Log("  captured: %s", Narrow(shot).c_str());
    }
    return true;
}

// ---- the scenarios ---------------------------------------------------------------------------------------------

bool EngineLogHas(const std::wstring& engineLog, const char* text);

struct Scenario {
    std::string name = "improve";
    std::wstring plain;
    std::wstring shots;  // where the candidate window's PNGs go (empty: none)
    std::wstring engineLog;
    DWORD enginePid = 0;

    std::wstring Expected() const {
        if (name == "plain") return plain;
        if (name == "pinyin") return L"你好你好";  // 你好你好
        if (name == "ai") return L"Hello there.";
        return L"hi Hello.";
    }

    std::wstring Shot(const wchar_t* file) const { return shots.empty() ? std::wstring() : shots + L"\\" + file; }
};

bool TapShift(DWORD pid);

// Types the scenario's keys into the foreground (`pid`'s window), checking the candidate window on the way.
bool TypeScenario(const Scenario& s, DWORD pid) {
    if (s.name == "plain") return TypeText(s.plain, pid);
    if (s.name == "pinyin") {
        // librime deploys as the engine starts (a second or so, longer in a new user folder): until then the field types
        // Latin letters only.
        bool ready = false;
        for (int i = 0; i < 600 && !(ready = EngineLogHas(s.engineLog, "rime: ready")); ++i) Pump(100);
        Check(ready, "librime is ready in the engine");
        // A new user's typing starts in English; a tap of Shift switches to 中文 (the run's settings: English, Chinese).
        if (!TapShift(pid)) return false;
        if (!TypeText(L"nihao", pid)) return false;
        Pump(300);
        CheckPanel(s.enginePid, pid, s.Shot(L"pinyin-candidates.png"), "nihao");
        if (!TapKey(VK_SPACE, pid)) return false;
        Pump(400);
        HWND panel = FindPanel(s.enginePid);
        Check(!panel || !IsWindowVisible(panel), "the candidate window went with the commit");
        if (!TypeText(L"nihao", pid)) return false;
        Pump(300);
        return TapKey('1', pid);
    }
    if (s.name == "ai") {
        if (!TypeText(L"@improve hello", pid) || !TapKey(VK_RETURN, pid)) return false;
        Log("  Return: waiting for the provider's stream (the stub on localhost)");
        Pump(2500);
        CheckPanel(s.enginePid, pid, s.Shot(L"ai-results.png"), "@improve's versions");
        return TapKey('1', pid);
    }
    bool typed = TypeText(L"hi ", pid) && TypeText(L"@improve helo", pid) && TapKey(VK_RETURN, pid);
    if (typed) {
        Log("  Return: waiting for the scripted stream");
        Pump(1500);  // the provider streams the versions in real time (the system clock)
        CheckPanel(s.enginePid, pid, s.Shot(L"improve-results.png"), "@improve's versions");
        typed = TapKey('1', pid);
    }
    return typed;
}

// Write a one-line marker file (UTF-8, no BOM, no newline), so we can tell our own document from the user's.
bool WriteSeed(const std::wstring& path, const std::string& marker) {
    HANDLE f = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    DWORD w = 0;
    bool ok = WriteFile(f, marker.data(), (DWORD)marker.size(), &w, nullptr) != 0;
    CloseHandle(f);
    return ok;
}

// ---- TSF profile: activating the TIP on Notepad's thread via an injected hook --------------------------------

// A TSF text service has no HKL (checked: activating it leaves the thread's layout at the base US one, and it never
// appears in GetKeyboardLayoutList), so it can't be put on another process's thread from outside the way a keyboard
// layout can (WM_INPUTLANGCHANGEREQUEST). ActivateProfile acts on the *calling* thread. So, as the shell does for a
// single window, we run ActivateProfile inside Notepad: a WH_GETMESSAGE hook DLL (e2ehook) injected into Notepad's GUI
// thread activates the profile there once. With per-thread input settings on, that touches only Notepad.
struct Injection {
    HMODULE lib = nullptr;
    HHOOK hook = nullptr;
    HANDLE config = nullptr;  // the hand-over the hook reads in Notepad
};

// The hook's hand-over (must match e2ehook.cpp): the Notepad it lands in is usually the user's, already running, so it
// hasn't our environment (AIO_E2E_LANGID, AIO_TIP_LOG).
struct HookConfig {
    DWORD langid;
    wchar_t log[MAX_PATH];
    BOOL haveRestore;                  // the session's input method now: what Notepad goes back to
    TF_INPUTPROCESSORPROFILE restore;
};

bool Inject(Injection& in, HWND window, DWORD threadId, const std::wstring& dllPath, LANGID lang,
            const TF_INPUTPROCESSORPROFILE* restore) {
    in.config = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(HookConfig),
                                   L"Local\\AllInOneIME-e2e-hook");
    if (in.config) {
        if (auto* config = static_cast<HookConfig*>(MapViewOfFile(in.config, FILE_MAP_WRITE, 0, 0, sizeof(HookConfig)))) {
            config->langid = lang;
            GetEnvironmentVariableW(L"AIO_TIP_LOG", config->log, MAX_PATH);
            config->haveRestore = restore != nullptr;
            if (restore) config->restore = *restore;
            UnmapViewOfFile(config);
        }
    }
    in.lib = LoadLibraryW(dllPath.c_str());
    if (!in.lib) { Log("  LoadLibrary %ls failed: %lu", dllPath.c_str(), GetLastError()); return false; }
    auto proc = reinterpret_cast<HOOKPROC>(GetProcAddress(in.lib, "GetMsgProc"));
    if (!proc) { Log("  GetProcAddress(GetMsgProc) failed"); return false; }
    in.hook = SetWindowsHookExW(WH_GETMESSAGE, proc, in.lib, threadId);
    if (!in.hook) { Log("  SetWindowsHookEx on thread %lu failed: %lu", threadId, GetLastError()); return false; }
    // Pump the hooked thread so GetMsgProc runs and activates the profile there.
    for (int i = 0; i < 20; ++i) {
        PostMessageW(window, WM_NULL, 0, 0);
        Pump(50);
    }
    return true;
}

bool LogContains(const char* text);

// Before unhooking: the hook puts Notepad back on the session's input method (and the rest it changed there). The TIP
// stays loaded in Notepad (TSF keeps objects of it, so COM never unloads it) until Notepad exits: an uninstall meanwhile
// moves the file aside and deletes it at the next restart.
void Uninject(Injection& in, HWND window, DWORD pid) {
    if (in.hook && window) {
        const UINT restore = RegisterWindowMessageW(L"AllInOneIME-e2e-restore");
        for (int i = 0; i < 40 && !LogContains("hook: restore: done"); ++i) {
            PostMessageW(window, restore, 0, 0);
            Pump(50);
        }
        Check(LogContains("hook: restore: done"), "Notepad is back on the session's input method");
        if (pid) Log("  AllInOneTIP.dll in Notepad: %s", TipModulesText(pid).c_str());
    }
    if (in.hook) { UnhookWindowsHookEx(in.hook); in.hook = nullptr; }
    if (in.lib) { FreeLibrary(in.lib); in.lib = nullptr; }
    if (in.config) { CloseHandle(in.config); in.config = nullptr; }
}

// Wait up to `ms` for the DLL to log that it reached the engine. The DLL writes "engine connected" to its diagnostic
// log (AIO_TIP_LOG) only after the handshake, in whatever process TSF loaded it into (Notepad, or ours in host mode),
// so this is the reliable signal that AllInOneIME engaged. We read the same file the driver logs to.
// The diagnostic log (AIO_TIP_LOG: ours, the DLL's and the hook's) holds `text`.
bool LogContains(const char* text) {
    char path[MAX_PATH] = {};
    if (!GetEnvironmentVariableA("AIO_TIP_LOG", path, MAX_PATH)) return false;
    HANDLE f = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    std::string data;
    char buf[4096];
    DWORD n = 0;
    while (ReadFile(f, buf, sizeof buf, &n, nullptr) && n) data.append(buf, n);
    CloseHandle(f);
    return data.find(text) != std::string::npos;
}

// The engine logs each connection with its client's pid ("connection N: pid P, ..."). That is the signal to trust: a
// DLL that an earlier run left loaded in the user's Notepad keeps writing to that run's (deleted) diagnostic log.
bool EngineSawPid(const std::wstring& engineLog, DWORD pid) {
    if (engineLog.empty()) return false;
    HANDLE f = CreateFileW(engineLog.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    std::string data;
    char buf[4096];
    DWORD n = 0;
    while (ReadFile(f, buf, sizeof buf, &n, nullptr) && n) data.append(buf, n);
    CloseHandle(f);
    return data.find(": pid " + std::to_string(pid) + ",") != std::string::npos;
}

// The engine's log holds `text`.
bool EngineLogHas(const std::wstring& engineLog, const char* text) {
    if (engineLog.empty()) return false;
    HANDLE f = CreateFileW(engineLog.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE) return false;
    std::string data;
    char buf[4096];
    DWORD n = 0;
    while (ReadFile(f, buf, sizeof buf, &n, nullptr) && n) data.append(buf, n);
    CloseHandle(f);
    return data.find(text) != std::string::npos;
}

// Wait up to `ms` for AllInOneIME in process `pid` to reach the engine.
bool WaitForEngineConnection(const std::wstring& engineLog, DWORD pid, DWORD ms) {
    ULONGLONG end = GetTickCount64() + ms;
    do {
        if (EngineSawPid(engineLog, pid)) return true;
        Pump(100);
    } while (GetTickCount64() < end);
    return false;
}

// The global state we touch and put back.
struct SessionState {
    bool setThreadLocal = false;  // we turned SPI_SETTHREADLOCALINPUTSETTINGS on
    TF_INPUTPROCESSORPROFILE previous = {};
    bool havePrevious = false;
};

void RestoreSession(SessionState& s, ITfInputProcessorProfileMgr* mgr) {
    if (s.havePrevious && mgr) {
        const auto& p = s.previous;
        mgr->ActivateProfile(p.dwProfileType, p.langid, p.clsid, p.guidProfile, p.hkl,
                             TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
    }
    if (s.setThreadLocal) {
        SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)FALSE, 0);
        s.setThreadLocal = false;
    }
}

// ---- the hosted-edit end-to-end -----------------------------------------------------------------------------
//
// Modern (packaged, WinUI) Notepad does not host a classic in-process TSF text service: ActivateProfile and the hook
// succeed, but TSF never loads the DLL into Notepad, so it can't compose there. A classic Win32 EDIT control does host
// the TIP in-process (as tiptest's own text store does). This mode drives the whole real stack — the real DLL loaded
// by TSF, the real engine over the pipe, keys from SendInput, the text read back through UIA TextPattern — through an
// EDIT control in the driver's own window. It is the end-to-end the DLL supports on this machine; the Notepad path
// above is kept for a host that can load the TIP (classic Notepad, or once AllInOneIME ships as an installed IM).
int HostEditRun(IUIAutomation* uia, ITfInputProcessorProfileMgr* profileMgr, const std::wstring& engineLog,
                LANGID lang, const std::wstring& expectTip, const Scenario& scenario) {
    Log("host-edit: a classic EDIT control in our own window");
    WNDCLASSEXW wc = {sizeof wc};
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"AioE2EHost";
    RegisterClassExW(&wc);
    HWND top = CreateWindowExW(0, L"AioE2EHost", L"AllInOneIME e2e", WS_OVERLAPPEDWINDOW, 40, 40, 520, 240, nullptr,
                               nullptr, wc.hInstance, nullptr);
    HWND edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
                                WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_AUTOVSCROLL | ES_WANTRETURN,
                                0, 0, 500, 200, top, nullptr, wc.hInstance, nullptr);
    Check(top && edit, "created the EDIT control");
    if (!top || !edit) return 1;
    ShowWindow(top, SW_SHOW);
    TakeForeground(top);
    SetFocus(edit);
    Pump(200);
    DWORD mine = GetCurrentProcessId();
    Check(ForegroundIsNotepad(mine), "our window has the foreground");

    // Activate the profile on this thread (per-thread input settings are on): TSF loads the TIP in-process here.
    HRESULT hr = profileMgr ? profileMgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, lang, kClsidTextService,
                                                          kGuidProfile, nullptr, TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE)
                            : E_FAIL;
    Log("  ActivateProfile(this thread) = 0x%08lx", hr);
    Pump(300);
    bool switched = WaitForEngineConnection(engineLog, mine, 6000);
    Log("  TIP loaded here: %s; engine saw us connect: %s", TipModulesText(mine).c_str(), switched ? "yes" : "no");
    Check(switched, "AllInOneIME engaged (the DLL reached the engine)");
    if (!expectTip.empty()) {
        bool found = false;
        for (const auto& path : TipModules(mine)) found = found || _wcsicmp(path.c_str(), expectTip.c_str()) == 0;
        Check(found, "the DLL loaded here is the expected copy");
    }

    IUIAutomationElement* el = nullptr;
    if (uia) uia->ElementFromHandle(edit, &el);
    Check(el != nullptr, "UIA sees the EDIT control");

    if (switched) {
        SetFocus(edit);
        Pump(150);
        Log("typing (%s)", scenario.name.c_str());
        bool typed = TypeScenario(scenario, mine);
        Check(typed, "typed the keys");
        Pump(400);
        std::wstring doc = el ? ReadDocument(el) : L"";
        if (doc.empty()) {  // some EDIT providers expose only the Value pattern
            wchar_t buf[256] = {};
            GetWindowTextW(edit, buf, 256);
            doc = buf;
            while (!doc.empty() && (doc.back() == L'\r' || doc.back() == L'\n')) doc.pop_back();
        }
        Log("  document: \"%s\"", Narrow(doc).c_str());
        Check(doc == scenario.Expected(), ("the control shows \"" + Narrow(scenario.Expected()) + "\"").c_str());
    }

    // Restore this thread's input method (TSF deactivates the TIP), then tear the window down.
    if (profileMgr) {
        TF_INPUTPROCESSORPROFILE prev = {};
        // Back to the base keyboard layout for this thread; the session default is untouched.
        profileMgr->ActivateProfile(TF_PROFILETYPE_KEYBOARDLAYOUT, lang, GUID_NULL, GUID_NULL,
                                    GetKeyboardLayout(0), TF_IPPMF_DONTCARECURRENTINPUTLANGUAGE);
        (void)prev;
    }
    Release(el);
    if (edit) DestroyWindow(edit);
    if (top) DestroyWindow(top);
    Pump(100);
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);

    std::wstring enginePath, fixturePath, engineLog;
    LANGID lang = 0x0409;
    DWORD timeoutMs = 60000;
    std::wstring plain, expectTip;
    std::vector<std::wstring> engineArgs;
    Scenario scenario;
    bool scenarioGiven = false;
    bool probe = false;
    bool host = false;
    for (int i = 1; i < argc; ++i) {
        auto wide = [](const char* s) {
            int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
            std::wstring w(n ? n - 1 : 0, L'\0');
            MultiByteToWideChar(CP_UTF8, 0, s, -1, w.data(), n);
            return w;
        };
        std::string a = argv[i];
        if (a == "--engine" && i + 1 < argc) enginePath = wide(argv[++i]);
        else if (a == "--fixture" && i + 1 < argc) fixturePath = wide(argv[++i]);
        else if (a == "--engine-log" && i + 1 < argc) engineLog = wide(argv[++i]);
        else if (a == "--langid" && i + 1 < argc) lang = (LANGID)strtoul(argv[++i], nullptr, 0);
        else if (a == "--timeout-ms" && i + 1 < argc) timeoutMs = strtoul(argv[++i], nullptr, 10);
        else if (a == "--plain" && i + 1 < argc) plain = wide(argv[++i]);
        else if (a == "--expect-tip" && i + 1 < argc) expectTip = wide(argv[++i]);
        else if (a == "--engine-arg" && i + 1 < argc) engineArgs.push_back(wide(argv[++i]));
        else if (a == "--shots" && i + 1 < argc) scenario.shots = wide(argv[++i]);
        else if (a == "--scenario" && i + 1 < argc) { scenario.name = argv[++i]; scenarioGiven = true; }
        else if (a == "--probe") probe = true;
        else if (a == "--host") host = true;
    }
    if (!scenarioGiven && !plain.empty()) scenario.name = "plain";
    scenario.plain = plain;
    scenario.engineLog = engineLog;
    const bool known = scenario.name == "improve" || scenario.name == "plain" || scenario.name == "pinyin" ||
                       scenario.name == "ai";
    if (enginePath.empty() || !known || (scenario.name == "improve" && fixturePath.empty()) ||
        (scenario.name == "plain" && plain.empty())) {
        printf("usage: e2edriver --engine <exe> [--scenario improve|plain|pinyin|ai] [--fixture <json>] [--plain <text>]\n"
               "       [--engine-arg <arg>]... [--shots <dir>] [--engine-log <file>] [--langid 0xNNNN] [--timeout-ms N]\n"
               "       [--expect-tip <dll>] [--probe] [--host]\n");
        return 2;
    }

    DWORD session = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &session);
    Log("e2edriver: session %lu, langid 0x%04x, scenario %s%s", session, lang, scenario.name.c_str(), probe ? ", probe" : "");

    // A hard watchdog, so the driver can never hang its scheduled task. It can't tidy up the session from here (no
    // handles), but main's own teardown runs on every path that isn't a true hang.
    DWORD watchdogMs = timeoutMs + 15000;
    HANDLE wd = CreateThread(nullptr, 0, [](void* p) -> DWORD {
        Sleep((DWORD)(uintptr_t)p);
        fprintf(stderr, "watchdog: timed out\n");
        ExitProcess(3);
    }, (void*)(uintptr_t)watchdogMs, 0, nullptr);
    if (wd) CloseHandle(wd);

    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HRESULT hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    // The hook DLL reads the langid from the environment; set it before Notepad launches, so Notepad inherits it (and
    // AIO_TIP_LOG, which run-in-session.sh set).
    {
        char buf[16];
        _snprintf_s(buf, sizeof buf, _TRUNCATE, "0x%04x", lang);
        SetEnvironmentVariableA("AIO_E2E_LANGID", buf);
    }
    wchar_t selfPath[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, selfPath, MAX_PATH);
    std::wstring hookDll = selfPath;
    hookDll = hookDll.substr(0, hookDll.find_last_of(L"\\/") + 1) + L"e2ehook.dll";

    // 1. The engine, in this session: for improve test mode, the scripted provider, the system clock (the stream plays
    // in real time); else as a user's runs, with the run's own arguments.
    const bool testMode = scenario.name == "improve";
    Log("starting the engine: %ls%s", enginePath.c_str(), testMode ? " (test mode)" : "");
    std::wstring cmd = L"\"" + enginePath + L"\"";
    if (testMode) cmd += L" --test --provider \"" + fixturePath + L"\" --clock system";
    for (const auto& arg : engineArgs) {
        cmd += arg.find_first_of(L" \t") == std::wstring::npos ? L" " + arg : L" \"" + arg + L"\"";
        Log("  engine argument: %ls", arg.c_str());
    }
    STARTUPINFOW si = {sizeof si};
    HANDLE engineErr = INVALID_HANDLE_VALUE;
    if (!engineLog.empty()) {
        SECURITY_ATTRIBUTES sa = {sizeof sa, nullptr, TRUE};
        engineErr = CreateFileW(engineLog.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                                CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (engineErr != INVALID_HANDLE_VALUE) {
            si.dwFlags |= STARTF_USESTDHANDLES;
            si.hStdError = engineErr;
            si.hStdOutput = engineErr;
        }
    }
    PROCESS_INFORMATION engine = {};
    std::vector<wchar_t> cmdBuf(cmd.begin(), cmd.end());
    cmdBuf.push_back(0);
    bool engineStarted = CreateProcessW(nullptr, cmdBuf.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr,
                                        nullptr, &si, &engine) != 0;
    Check(engineStarted, "the engine started");
    if (!engineStarted) { Log("  CreateProcess failed: %lu", GetLastError()); return 1; }
    scenario.enginePid = engine.dwProcessId;
    // Let the pipe come up (and, as a user's engine, librime deploy: a second or so in a new user folder).
    Pump(testMode ? 600 : 2500);

    ITfInputProcessorProfileMgr* profileMgr = nullptr;
    CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                     IID_ITfInputProcessorProfileMgr, (void**)&profileMgr);
    ITfThreadMgr* threadMgr = nullptr;
    TfClientId tid = 0;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr,
                                   (void**)&threadMgr)) && threadMgr) {
        threadMgr->Activate(&tid);
    }
    Check(profileMgr && threadMgr, "TSF is available (an interactive session)");

    SessionState state;

    // 2. Per-thread input settings, so switching one window never switches every app (README's warning).
    BOOL threadLocal = FALSE;
    SystemParametersInfoW(SPI_GETTHREADLOCALINPUTSETTINGS, 0, &threadLocal, 0);
    Log("input settings were %s", threadLocal ? "per thread" : "session-wide");
    if (profileMgr && SUCCEEDED(profileMgr->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &state.previous))) {
        state.havePrevious = true;
    }
    if (!threadLocal) {
        state.setThreadLocal = SystemParametersInfoW(SPI_SETTHREADLOCALINPUTSETTINGS, 0, (PVOID)TRUE, 0) != 0;
        Check(state.setThreadLocal, "input settings made per thread for the run");
    }

    IUIAutomation* uia = nullptr;
    CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation), (void**)&uia);
    Check(uia != nullptr, "UI Automation is available");

    if (host) {
        // The hosted-edit end-to-end: the full real stack through an EDIT control in our own process.
        HostEditRun(uia, profileMgr, engineLog, lang, expectTip, scenario);
        Release(uia);
        RestoreSession(state, profileMgr);
        if (threadMgr) { threadMgr->Deactivate(); threadMgr->Release(); }
        Release(profileMgr);
        if (engineStarted) {
            TerminateProcess(engine.hProcess, 0);
            WaitForSingleObject(engine.hProcess, 2000);
            CloseHandle(engine.hProcess);
            CloseHandle(engine.hThread);
        }
        if (engineErr != INVALID_HANDLE_VALUE) CloseHandle(engineErr);
        if (SUCCEEDED(hrInit)) CoUninitialize();
        Log("%s (%d failures)", g_failures == 0 ? "PASS" : "FAIL", g_failures);
        return g_failures == 0 ? 0 : 1;
    }

    // 3. Notepad, on a temp file we seed with a unique marker. The Store Notepad is a single, tabbed instance, so our
    // tab lives in the user's own Notepad process: we must never terminate it or close its window, only type into the
    // document we can prove is ours (its text is exactly the marker) and close our own tab. If we can't find our
    // seeded document, we type nothing.
    wchar_t tempDir[MAX_PATH] = {};
    GetTempPathW(MAX_PATH, tempDir);
    std::wstring seedPath = std::wstring(tempDir) + L"aio-e2e-" + std::to_wstring(GetCurrentProcessId()) + L".txt";
    char marker[64];
    _snprintf_s(marker, sizeof marker, _TRUNCATE, "AIO-E2E-%lu", GetCurrentProcessId());
    std::wstring want;
    for (const char* c = marker; *c; ++c) want.push_back((wchar_t)*c);
    Check(WriteSeed(seedPath, marker), "seeded a temp file");

    Found np;
    PROCESS_INFORMATION notepadStub = {};
    STARTUPINFOW nsi = {sizeof nsi};
    std::wstring npCmd = L"notepad.exe \"" + seedPath + L"\"";
    std::vector<wchar_t> npBuf(npCmd.begin(), npCmd.end());
    npBuf.push_back(0);
    CreateProcessW(nullptr, npBuf.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &nsi, &notepadStub);
    Log("launched: %ls", npCmd.c_str());
    // Find the document whose text is our marker (and the window + pid that hold it). Never the user's.
    for (int i = 0; i < 120 && !np.edit; ++i) {
        Pump(100);
        Hunt hunt;
        EnumWindows(FindNotepadWindow, reinterpret_cast<LPARAM>(&hunt));
        for (HWND w : hunt.windows) {
            IUIAutomationElement* edit = uia ? FindSeededEdit(uia, w, want) : nullptr;
            if (edit) { np.window = w; np.pid = hunt.pid; np.edit = edit; break; }
        }
    }
    Check(np.edit != nullptr, "found our seeded document in Notepad (UIA TextPattern)");
    if (np.window) Log("  Notepad window %p, pid %lu, our marker \"%s\"", (void*)np.window, np.pid, marker);

    // 4. Activate AllInOneIME on Notepad's thread, by injecting the hook. Per-thread input settings are on, so this is
    // Notepad's thread only.
    Injection injection;
    bool switched = false, confirmedMine = false;
    if (np.window && np.edit) {
        TakeForeground(np.window);
        Check(ForegroundIsNotepad(np.pid), "Notepad has the foreground");
        SetUiaFocus(np.edit);
        Pump(200);
        // Prove our document is the one that will take the keys: it is focused and still holds exactly the marker.
        confirmedMine = ReadDocument(np.edit) == want;
        Check(confirmedMine, "our seeded document is the active one (safe to type)");

        DWORD npThread = GetWindowThreadProcessId(np.window, nullptr);
        Log("  injecting e2ehook into Notepad thread %lu", npThread);
        if (Inject(injection, np.window, npThread, hookDll, lang, state.havePrevious ? &state.previous : nullptr)) {
            // TSF loads the TIP into a process on a focus transition, not merely when the active profile changes. Move
            // the focus away and back to Notepad (through a tiny scratch window of our own), so TSF re-reads the active
            // profile for Notepad's thread and loads AllInOneIME there.
            WNDCLASSEXW wc = {sizeof wc};
            wc.lpfnWndProc = DefWindowProcW;
            wc.hInstance = GetModuleHandleW(nullptr);
            wc.lpszClassName = L"AioE2EScratch";
            RegisterClassExW(&wc);
            HWND scratch = CreateWindowExW(WS_EX_TOOLWINDOW, L"AioE2EScratch", L"", WS_POPUP, -200, -200, 1, 1, nullptr,
                                           nullptr, wc.hInstance, nullptr);
            for (int i = 0; i < 3 && !switched; ++i) {
                if (scratch) { TakeForeground(scratch); Pump(200); }
                TakeForeground(np.window);
                SetUiaFocus(np.edit);
                Pump(200);
                switched = WaitForEngineConnection(engineLog, np.pid, 2500);
            }
            if (scratch) DestroyWindow(scratch);
            Log("  AllInOneTIP.dll in Notepad: %s; engine saw Notepad connect: %s", TipModulesText(np.pid).c_str(),
                switched ? "yes" : "no");
        }
        Check(switched, "AllInOneIME is active in Notepad (the DLL reached the engine)");
        if (!expectTip.empty()) {
            bool found = false;
            for (const auto& path : TipModules(np.pid)) found = found || _wcsicmp(path.c_str(), expectTip.c_str()) == 0;
            Check(found, "the DLL in Notepad is the expected copy");
        }
    }

    bool mayType = np.window && np.edit && switched && confirmedMine;
    if (!probe && mayType) {
        // 5. Clear the marker (plain shortcut) and type. Each key only while Notepad has the foreground and only ever
        // into the document we proved is ours.
        TakeForeground(np.window);
        SetUiaFocus(np.edit);
        Pump(150);
        Chord(VK_CONTROL, 'A', np.pid);
        TapKey(VK_DELETE, np.pid);
        Pump(150);
        bool empty = ReadDocument(np.edit).empty();
        Check(empty, "cleared our document before typing");
        if (empty) {
            Log("typing (%s)", scenario.name.c_str());
            bool typed = TypeScenario(scenario, np.pid);
            Check(typed, "typed the keys into Notepad");
            Pump(500);

            // 6. The result.
            const std::wstring expected = scenario.Expected();
            std::wstring doc = ReadDocument(np.edit);
            Log("  document: \"%s\"", Narrow(doc).c_str());
            Check(doc == expected, ("Notepad shows \"" + Narrow(expected) + "\"").c_str());
        }
    } else if (probe) {
        Log("probe: engine=%d notepad=%p edit=%p mine=%d tipLoaded=%d switched=%d", engineStarted, (void*)np.window,
            (void*)np.edit, confirmedMine, np.pid ? TipLoaded(np.pid) : 0, switched);
    }

    // Teardown. Unhook. Then, only if our document is still the active one, save it (no prompt, it is a file) and
    // close our tab (Ctrl+W). We never close the user's window or terminate the shared Notepad process.
    Log("teardown");
    Uninject(injection, np.window, np.pid);
    if (np.window && np.edit) {
        std::wstring now = ReadDocument(np.edit);
        bool oursActive = ForegroundIsNotepad(np.pid) && (now == want || now == scenario.Expected() || now.empty() ||
                                                          (!plain.empty() && now.find(plain) == 0) ||
                                                          now.find(L"improve") != std::wstring::npos ||
                                                          now.find(L"nihao") != std::wstring::npos ||
                                                          now.find(L"你好") == 0);
        if (oursActive) {
            Chord(VK_CONTROL, 'S', np.pid);
            Pump(300);
            Chord(VK_CONTROL, 'W', np.pid); // close our tab
            Pump(300);
            Log("  saved and closed our tab");
        } else {
            Log("  our document is not the active one: leaving Notepad untouched");
        }
    }
    Release(np.edit);
    Release(uia);
    RestoreSession(state, profileMgr);
    if (threadMgr) { threadMgr->Deactivate(); threadMgr->Release(); }
    Release(profileMgr);

    // Stop the engine (it holds nothing to flush).
    if (engineStarted) {
        TerminateProcess(engine.hProcess, 0);
        WaitForSingleObject(engine.hProcess, 2000);
        CloseHandle(engine.hProcess);
        CloseHandle(engine.hThread);
    }
    if (engineErr != INVALID_HANDLE_VALUE) CloseHandle(engineErr);
    if (notepadStub.hProcess) { CloseHandle(notepadStub.hProcess); CloseHandle(notepadStub.hThread); }
    DeleteFileW(seedPath.c_str());

    if (SUCCEEDED(hrInit)) CoUninitialize();
    Log("%s (%d failures)", g_failures == 0 ? "PASS" : "FAIL", g_failures);
    return g_failures == 0 ? 0 : 1;
}
