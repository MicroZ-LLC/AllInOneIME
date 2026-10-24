// The engine's candidate window: see AllInOneIMEPanel.h.
//
// - A WS_POPUP window with WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST: never activated (a
//   click answers WM_MOUSEACTIVATE with MA_NOACTIVATE, it is shown with SW_SHOWNOACTIVATE), never in the taskbar or
//   Alt+Tab, above the app being typed in.
// - Drawn with Direct2D into a premultiplied 32-bit DIB (a DC render target) and handed to UpdateLayeredWindow with
//   per-pixel alpha, so its corners are round; text with DirectWrite (Segoe UI, Han through the system's fallback,
//   Simplified Chinese glyphs).
// - Per monitor DPI: the process is per-monitor aware (the engine sets it), the caret comes in physical pixels, and the
//   panel is laid out at the DPI of the monitor the caret is on, inside that monitor's work area: below the caret, or
//   above it when there is no room.
// - It is drawn only while its owner's process is the app in front (its window, a classic console's window for its
//   conhost, the focus or a window inside the foreground window: InFront), and hides when another app takes the
//   foreground (EVENT_SYSTEM_FOREGROUND): a background or sandboxed client can't put it, with its text, over another app.
// - Everything happens on the window's own thread: the API posts it messages with a copy of what to show.
#ifdef _WIN32

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <shellscalingapi.h>
#include <tlhelp32.h>
#include <wincodec.h>

#include <algorithm>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "AllInOneIMEPanel.h"

namespace {

template <class T>
void SafeRelease(T *&p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

std::wstring Copy(const uint16_t *s) { return s ? std::wstring(reinterpret_cast<const wchar_t *>(s)) : std::wstring(); }

std::vector<std::wstring> CopyAll(const uint16_t *const *strings, int32_t count) {
    std::vector<std::wstring> all;
    for (int32_t i = 0; strings && i < count; ++i) all.push_back(Copy(strings[i]));
    return all;
}

struct Icon {
    int kind = AIO_ICON_NONE;
    std::wstring text, fallback;
    uint32_t color = 0;
};

struct Row {
    std::wstring label, text, comment;
    int style = 0;
    bool pickable = true;
    bool complete = true;
    Icon icon;
};

struct Chip {
    std::wstring shortcut, name;
};

struct Model {
    std::vector<Row> rows;
    int highlighted = -1;
    bool horizontal = false;
    bool transcript = false;
    int statusKind = AIO_STATUS_NONE;
    std::wstring status;
    std::vector<std::wstring> statusItems;
    bool hasInput = false;
    std::wstring inputPrompt, inputText;
    int inputCaret = -1;  // in inputText, UTF-16
    std::vector<std::wstring> header;
    std::wstring handoffTitle;
    std::vector<Chip> handoff;
    std::wstring footer, detail;
    bool empty() const {
        return rows.empty() && statusKind == AIO_STATUS_NONE && !hasInput && header.empty() && handoffTitle.empty() &&
               handoff.empty() && footer.empty() && detail.empty();
    }
};

Model CopyModel(const AioPanelModel *m) {
    Model model;
    if (!m) return model;
    for (int32_t i = 0; i < m->rowCount; ++i) {
        const AioPanelRow &r = m->rows[i];
        Row row;
        row.label = Copy(r.label);
        row.text = Copy(r.text);
        row.comment = Copy(r.comment);
        row.style = r.style;
        row.pickable = r.pickable != 0;
        row.complete = r.complete != 0;
        row.icon.kind = r.icon.kind;
        row.icon.text = Copy(r.icon.text);
        row.icon.fallback = Copy(r.icon.fallback);
        row.icon.color = r.icon.color;
        model.rows.push_back(std::move(row));
    }
    model.highlighted = m->highlighted;
    model.horizontal = m->horizontal != 0;
    model.transcript = m->transcript != 0;
    model.statusKind = m->statusKind;
    model.status = Copy(m->status);
    model.statusItems = CopyAll(m->statusItems, m->statusItemCount);
    model.hasInput = m->inputText != nullptr;
    model.inputPrompt = Copy(m->inputPrompt);
    model.inputText = Copy(m->inputText);
    model.inputCaret = m->inputCaret >= 0 ? std::min<int>(m->inputCaret, (int)model.inputText.size()) : -1;
    model.header = CopyAll(m->headerLines, m->headerCount);
    model.handoffTitle = Copy(m->handoffTitle);
    std::vector<std::wstring> shortcuts = CopyAll(m->handoffShortcuts, m->handoffCount);
    std::vector<std::wstring> names = CopyAll(m->handoffNames, m->handoffCount);
    for (size_t i = 0; i < shortcuts.size() && i < names.size(); ++i) model.handoff.push_back({shortcuts[i], names[i]});
    model.footer = Copy(m->footer);
    model.detail = Copy(m->detail);
    return model;
}

// What the API posts to the window's thread.
enum Op { OpShow, OpHide, OpMove, OpNotice };
struct Command {
    Op op;
    Model model;
    bool hasCaret = false;
    AioCaret caret = {};
    uint64_t owner = 0;
    uint32_t ownerPid = 0;
    bool ownerTrusted = false;
    std::wstring text;
    int durationMs = 0;
};

const UINT kCommand = WM_APP + 1;
const UINT kSync = WM_APP + 2;
const UINT kSavePng = WM_APP + 3;
const UINT kImagesRead = WM_APP + 4;  // the image loader read something: draw again
// An image is looked at again (in the background) when a draw wants it this long after it last was: changed, or
// readable now. At most kMaxImages are kept, those being read too, the least recently drawn going first.
const ULONGLONG kImageRecheckMs = 2000;
const size_t kMaxImages = 64;
// The images are read by kImageReaders threads at once at most, started as reads wait for one; a read under way this
// long (a share that doesn't answer) holds up no other: another thread is started for them, kMaxImageThreads in all.
const size_t kImageReaders = 2;
const ULONGLONG kImageStuckMs = 1000;
const size_t kMaxImageThreads = 8;
const UINT_PTR kNoticeTimer = 1;
const UINT_PTR kCaretTimer = 2;
const UINT_PTR kImageTimer = 3;  // an image waits for a read to end or to be stuck: look again
const wchar_t kClassName[] = L"AllInOneIME.CandidateWindow";

struct Colors {
    D2D1_COLOR_F background, border, text, secondary, highlight, highlightText, error, chip;
};

D2D1_COLOR_F Rgb(uint32_t rgb, float alpha = 1.0f) {
    return D2D1::ColorF(((rgb >> 16) & 0xFF) / 255.0f, ((rgb >> 8) & 0xFF) / 255.0f, (rgb & 0xFF) / 255.0f, alpha);
}

// The apps' theme: HKCU\...\Themes\Personalize, AppsUseLightTheme (missing: light).
bool DarkTheme() {
    DWORD value = 1, size = sizeof value;
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                     L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value, &size) != ERROR_SUCCESS) {
        return false;
    }
    return value == 0;
}

Colors ThemeColors(bool dark) {
    if (dark) {
        return {Rgb(0x2B2B2B, 0.98f), Rgb(0x454545), Rgb(0xFFFFFF), Rgb(0xA6A6A6), Rgb(0x4CC2FF), Rgb(0x000000),
                Rgb(0xFF99A4), Rgb(0x3C3C3C)};
    }
    return {Rgb(0xF9F9F9, 0.98f), Rgb(0xD5D5D5), Rgb(0x1A1A1A), Rgb(0x6B6B6B), Rgb(0x0067C0), Rgb(0xFFFFFF),
            Rgb(0xC42B1C), Rgb(0xEAEAEA)};
}

// An image a row shows (a script extension's), as it was last read: premultiplied BGRA pixels, at most 128 a side (none:
// unreadable), and what the file was then.
struct ImageEntry {
    std::wstring path;
    std::vector<BYTE> pixels;
    UINT width = 0, height = 0;
    bool tried = false, exists = false;
    FILETIME written = {};
    ULONGLONG size = 0;
    ULONGLONG checkedAt = 0, usedAt = 0;
    bool loading = false;
};

// Reads the rows' images on threads of their own, never the window's: a file on a share that is slow or offline holds
// nothing up, the panel drawing the fallback meanwhile, nor the other images (`kImageStuckMs`). What they read goes into
// `entries` and the window is told to draw again (kImagesRead). Shared with those threads, which may outlive the panel
// (a read that never ends) and then end.
struct ImageLoader {
    std::mutex lock;
    std::condition_variable wake;
    std::deque<std::wstring> pending;
    std::vector<ImageEntry> entries;
    HWND notify = nullptr;
    bool stopping = false;
    // The threads, those waiting for a path, and when each read under way started.
    size_t threads = 0, idle = 0;
    std::vector<ULONGLONG> reading;
};

}  // namespace

struct AioPanel {
    AioPanelCallbacks callbacks = {};
    HANDLE thread = nullptr;
    DWORD threadId = 0;
    HANDLE ready = nullptr;
    HWND hwnd = nullptr;
    HWINEVENTHOOK foregroundHook = nullptr;

    ID2D1Factory *d2d = nullptr;
    IDWriteFactory *dwrite = nullptr;
    ID2D1DCRenderTarget *target = nullptr;
    IDWriteTextFormat *textFormat = nullptr, *labelFormat = nullptr, *commentFormat = nullptr, *footerFormat = nullptr,
                      *statusFormat = nullptr, *iconFormat = nullptr, *emojiFormat = nullptr;
    UINT formatsDpi = 0;
    // The rows' images (a script extension's): read off the window's thread (`ImageLoader`, made with the first one);
    // where there is no window (render_png, `readImagesNow`) read as they are drawn, with `wic`.
    std::shared_ptr<ImageLoader> images;
    bool readImagesNow = false;
    IWICImagingFactory *wic = nullptr;

    HDC memoryDC = nullptr;
    HBITMAP bitmap = nullptr;
    HGDIOBJ oldBitmap = nullptr;
    void *bits = nullptr;
    int bitmapWidth = 0, bitmapHeight = 0;

    // What is shown, and for whom.
    Model model;
    bool modelShown = false;
    uint64_t owner = 0;
    uint32_t ownerPid = 0;
    bool ownerTrusted = false;
    bool hasCaret = false;
    AioCaret caret = {};
    bool waitingForCaret = false;
    std::wstring notice;
    bool noticeAlone = false;  // the notice is all there is
    std::vector<RECT> rowRects;
    std::vector<bool> rowPickable;
    // Where the first row's text starts (placed under the caret), the input's caret was drawn, the rows are scrolled.
    float textInset = 0;
    POINT caretDrawn = {-1, -1};
    int scrolled = 0;
    POINT position = {};
    SIZE size = {};
    bool visible = false;
    UINT dpi = 96;

    std::mutex stateLock;
    AioPanelState state = {};
};

namespace {

thread_local AioPanel *g_panel = nullptr;  // the window thread's own (the WinEvent hook has no context)

float Scale(AioPanel *p) { return p->dpi / 96.0f; }

IDWriteTextFormat *MakeFormat(AioPanel *p, float size, DWRITE_FONT_WEIGHT weight = DWRITE_FONT_WEIGHT_NORMAL) {
    IDWriteTextFormat *format = nullptr;
    p->dwrite->CreateTextFormat(L"Segoe UI", nullptr, weight, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
                                size * Scale(p), L"zh-cn", &format);
    if (format) {
        format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
        format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
        // Long rows end in an ellipsis.
        DWRITE_TRIMMING trimming = {DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
        IDWriteInlineObject *ellipsis = nullptr;
        p->dwrite->CreateEllipsisTrimmingSign(format, &ellipsis);
        format->SetTrimming(&trimming, ellipsis);
        SafeRelease(ellipsis);
    }
    return format;
}

// The icons' font: Segoe Fluent Icons (Windows 11), else Segoe MDL2 Assets (Windows 10), whose code points it keeps.
// Found once, by the first caller, whatever thread it is on (render_png may be called from any).
const wchar_t *IconFont(AioPanel *p) {
    static const wchar_t *const font = [p]() -> const wchar_t * {
        const wchar_t *found = L"Segoe MDL2 Assets";
        IDWriteFontCollection *fonts = nullptr;
        if (SUCCEEDED(p->dwrite->GetSystemFontCollection(&fonts, FALSE)) && fonts) {
            UINT32 index = 0;
            BOOL exists = FALSE;
            if (SUCCEEDED(fonts->FindFamilyName(L"Segoe Fluent Icons", &index, &exists)) && exists) found = L"Segoe Fluent Icons";
            fonts->Release();
        }
        return found;
    }();
    return font;
}

IDWriteTextFormat *MakeCentered(AioPanel *p, const wchar_t *family, float size) {
    IDWriteTextFormat *format = nullptr;
    p->dwrite->CreateTextFormat(family, nullptr, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
                                size * Scale(p), L"en-us", &format);
    if (format) {
        format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
        format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
        format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    }
    return format;
}

void MakeFormats(AioPanel *p) {
    if (p->formatsDpi == p->dpi && p->textFormat) return;
    SafeRelease(p->textFormat);
    SafeRelease(p->labelFormat);
    SafeRelease(p->commentFormat);
    SafeRelease(p->footerFormat);
    SafeRelease(p->statusFormat);
    SafeRelease(p->iconFormat);
    SafeRelease(p->emojiFormat);
    p->textFormat = MakeFormat(p, 16.0f);
    p->labelFormat = MakeFormat(p, 12.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD);
    p->commentFormat = MakeFormat(p, 12.0f);
    p->footerFormat = MakeFormat(p, 11.5f);
    p->statusFormat = MakeFormat(p, 13.5f);
    p->iconFormat = MakeCentered(p, IconFont(p), 12.0f);
    p->emojiFormat = MakeCentered(p, L"Segoe UI Emoji", 15.0f);
    p->formatsDpi = p->dpi;
}

// A text's size in pixels, at most `maxWidth` wide.
D2D1_SIZE_F Measure(AioPanel *p, const std::wstring &text, IDWriteTextFormat *format, float maxWidth) {
    if (text.empty() || !format) return D2D1::SizeF(0, 0);
    IDWriteTextLayout *layout = nullptr;
    p->dwrite->CreateTextLayout(text.c_str(), (UINT32)text.size(), format, maxWidth, 10000.0f, &layout);
    if (!layout) return D2D1::SizeF(0, 0);
    DWRITE_TEXT_METRICS metrics = {};
    layout->GetMetrics(&metrics);
    layout->Release();
    return D2D1::SizeF(std::min(std::ceil(metrics.widthIncludingTrailingWhitespace), maxWidth), std::ceil(metrics.height));
}

void DrawText(AioPanel *p, const std::wstring &text, IDWriteTextFormat *format, float x, float y, float width, float height,
              const D2D1_COLOR_F &color, DWRITE_TEXT_ALIGNMENT alignment = DWRITE_TEXT_ALIGNMENT_LEADING) {
    if (text.empty() || !format || width <= 0) return;
    ID2D1SolidColorBrush *brush = nullptr;
    p->target->CreateSolidColorBrush(color, &brush);
    if (!brush) return;
    IDWriteTextLayout *layout = nullptr;
    p->dwrite->CreateTextLayout(text.c_str(), (UINT32)text.size(), format, width, height, &layout);
    if (layout) {
        layout->SetTextAlignment(alignment);
        // Emoji in color (rime-ice offers them among the candidates: nihao gives 👋).
        p->target->DrawTextLayout(D2D1::Point2F(x, y), layout, brush,
                                  D2D1_DRAW_TEXT_OPTIONS_CLIP | D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
        layout->Release();
    }
    brush->Release();
}

void FillRounded(AioPanel *p, D2D1_RECT_F rect, float radius, const D2D1_COLOR_F &color) {
    ID2D1SolidColorBrush *brush = nullptr;
    p->target->CreateSolidColorBrush(color, &brush);
    if (!brush) return;
    p->target->FillRoundedRectangle(D2D1::RoundedRect(rect, radius, radius), brush);
    brush->Release();
}

// The DPI of the monitor `point` is on (its effective DPI, as Settings' scale gives it).
UINT DpiAt(POINT point, RECT *work) {
    HMONITOR monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
    UINT x = 96, y = 96;
    if (FAILED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &x, &y))) x = 96;
    MONITORINFO info = {sizeof info};
    if (work && GetMonitorInfoW(monitor, &info)) *work = info.rcWork;
    return x ? x : 96;
}

// The full path of process `pid`'s executable ("" if it can't be read).
std::wstring ProcessImage(DWORD pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return std::wstring();
    wchar_t path[MAX_PATH * 2];
    DWORD size = (DWORD)(sizeof path / sizeof path[0]);
    std::wstring image = QueryFullProcessImageNameW(process, 0, path, &size) ? std::wstring(path, size) : std::wstring();
    CloseHandle(process);
    return image;
}

// Whether process `pid` is System32's `name` (conhost.exe).
bool IsSystemProgram(DWORD pid, const wchar_t *name) {
    wchar_t system[MAX_PATH];
    UINT count = GetSystemDirectoryW(system, MAX_PATH);
    if (!count || count >= MAX_PATH) return false;
    std::wstring expected = std::wstring(system, count) + L"\\" + name;
    return CompareStringOrdinal(ProcessImage(pid).c_str(), -1, expected.c_str(), -1, TRUE) == CSTR_EQUAL;
}

// Whether a thread of process `pid` made the top-level `window` (EnumThreadWindows over its threads, from a Toolhelp
// snapshot: a few ms). The last answer is kept for a second: the panel asks again at every key.
bool MadeBy(HWND window, DWORD pid) {
    static std::mutex lock;
    static HWND lastWindow = nullptr;
    static DWORD lastPid = 0;
    static bool lastAnswer = false;
    static ULONGLONG lastAt = 0;
    {
        std::lock_guard<std::mutex> guard(lock);
        if (window == lastWindow && pid == lastPid && GetTickCount64() - lastAt < 1000) return lastAnswer;
    }
    bool found = false;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot != INVALID_HANDLE_VALUE) {
        THREADENTRY32 entry = {sizeof entry};
        for (BOOL more = Thread32First(snapshot, &entry); more && !found; more = Thread32Next(snapshot, &entry)) {
            if (entry.th32OwnerProcessID != pid) continue;
            struct Search {
                HWND window;
                bool found;
            } search = {window, false};
            EnumThreadWindows(
                entry.th32ThreadID,
                [](HWND made, LPARAM lParam) -> BOOL {
                    Search *s = reinterpret_cast<Search *>(lParam);
                    s->found = made == s->window;
                    return !s->found;
                },
                reinterpret_cast<LPARAM>(&search));
            found = search.found;
        }
        CloseHandle(snapshot);
    }
    std::lock_guard<std::mutex> guard(lock);
    lastWindow = window;
    lastPid = pid;
    lastAnswer = found;
    lastAt = GetTickCount64();
    return found;
}

// Whether `window` is process `pid`'s. GetWindowThreadProcessId says so, except for a classic console's window
// (ConsoleWindowClass): the conhost.exe that draws it, where TSF and so the DLL run, has it report the console's client
// (cmd.exe, powershell.exe: ConsoleSetWindowOwner) instead, so for System32's conhost the window's real thread decides.
bool IsProcessWindow(HWND window, DWORD pid) {
    if (!window || !pid) return false;
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner == pid) return true;
    wchar_t name[32] = {};
    if (!GetClassNameW(window, name, 32) || wcscmp(name, L"ConsoleWindowClass") != 0) return false;
    return IsSystemProgram(pid, L"conhost.exe") && MadeBy(window, pid);
}

// Whether `window` is System32's ApplicationFrameHost.exe's: the frame a UWP app's CoreWindow is put in.
bool IsFrameHostWindow(HWND window) {
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    return pid && IsSystemProgram(pid, L"ApplicationFrameHost.exe");
}

// Whether process `pid` is the app in front, `foreground` the foreground window and `focus` its thread's focus window:
// - the foreground window is its own (IsProcessWindow: a classic console's, for its conhost);
// - the focus is in a window of its own: a window of another process inside the app's (a WebView2 in the new Outlook
//   or Teams, whose input method client is msedgewebview2.exe), whose thread's input is the app's;
// - or a window inside the foreground window is its own: a UWP app's CoreWindow in ApplicationFrameHost's frame (the
//   app is in an AppContainer: an untrusted client, §8), or, for a trusted client (`trusted`: medium integrity or
//   higher, no AppContainer), anywhere inside it (a browser's, a plugin's). Another process's window in the app's, for an
//   untrusted client, would be one it put there itself to show its panel over that app (UIPI keeps a low-integrity or
//   AppContainer process from creating a child of, or SetParent-ing into, a medium one's window: tried, error 5).
bool InFront(HWND foreground, HWND focus, DWORD pid, bool trusted) {
    if (!foreground || !pid) return false;
    if (IsProcessWindow(foreground, pid) || (focus && IsProcessWindow(focus, pid))) return true;
    if (!trusted && !IsFrameHostWindow(foreground)) return false;
    struct Search {
        DWORD pid;
        bool found;
    } search = {pid, false};
    EnumChildWindows(
        foreground,
        [](HWND child, LPARAM lParam) -> BOOL {
            Search *s = reinterpret_cast<Search *>(lParam);
            DWORD childPid = 0;
            GetWindowThreadProcessId(child, &childPid);
            s->found = childPid == s->pid;
            return !s->found;
        },
        reinterpret_cast<LPARAM>(&search));
    return search.found;
}

// The focus window of `foreground`'s thread (GetGUIThreadInfo), nil if none.
HWND FocusOf(HWND foreground) {
    GUITHREADINFO info = {sizeof info};
    if (!foreground || !GetGUIThreadInfo(GetWindowThreadProcessId(foreground, nullptr), &info)) return nullptr;
    return info.hwndFocus;
}

bool InFront(HWND foreground, DWORD pid, bool trusted) { return InFront(foreground, FocusOf(foreground), pid, trusted); }

bool OwnsForeground(DWORD pid, bool trusted) { return InFront(GetForegroundWindow(), pid, trusted); }

// `rect`, in the client coordinates of `window` (a system caret, as GetGUIThreadInfo gives it), in physical screen
// pixels. Those coordinates are the window's own: for an app that isn't per-monitor aware they are its logical pixels,
// scaled on a monitor at another DPI. So they are mapped to the screen as the window sees it (this thread in the
// window's DPI awareness for ClientToScreen), then to physical pixels (LogicalToPhysicalPointForPerMonitorDPI); this
// per-monitor aware thread's own ClientToScreen would take them for physical ones.
bool ClientRectOnScreen(HWND window, RECT rect, AioCaret *out) {
    POINT a = {rect.left, rect.top}, b = {rect.right, rect.bottom};
    DPI_AWARENESS_CONTEXT previous = SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(window));
    BOOL mapped = ClientToScreen(window, &a) && ClientToScreen(window, &b);
    if (previous) SetThreadDpiAwarenessContext(previous);
    if (!mapped) return false;
    LogicalToPhysicalPointForPerMonitorDPI(window, &a);
    LogicalToPhysicalPointForPerMonitorDPI(window, &b);
    *out = {a.x, a.y, std::max<LONG>(b.x - a.x, 1), std::max<LONG>(b.y - a.y, 1), 0};
    return true;
}

// Where the caret is when the DLL hasn't said: the foreground thread's system caret (classic Win32 controls have one),
// else the bottom left of the foreground window, else the pointer. In physical pixels.
AioCaret FallbackCaret() {
    AioCaret c = {};
    HWND fg = GetForegroundWindow();
    GUITHREADINFO info = {sizeof info};
    if (fg && GetGUIThreadInfo(GetWindowThreadProcessId(fg, nullptr), &info) && info.hwndCaret &&
        (info.rcCaret.right > info.rcCaret.left || info.rcCaret.bottom > info.rcCaret.top) &&
        ClientRectOnScreen(info.hwndCaret, info.rcCaret, &c)) {
        return c;
    }
    RECT r;
    if (fg && GetWindowRect(fg, &r)) {
        UINT dpi = DpiAt(POINT{r.left, r.top}, nullptr);
        c = {r.left + MulDiv(40, (int)dpi, 96), r.top + MulDiv(80, (int)dpi, 96), 1, MulDiv(20, (int)dpi, 96), 0};
        return c;
    }
    POINT pt;
    GetCursorPos(&pt);
    c = {pt.x, pt.y, 1, MulDiv(20, (int)DpiAt(pt, nullptr), 96), 0};
    return c;
}

void PublishState(AioPanel *p) {
    std::lock_guard<std::mutex> lock(p->stateLock);
    p->state.visible = p->visible ? 1 : 0;
    p->state.x = p->position.x;
    p->state.y = p->position.y;
    p->state.width = p->size.cx;
    p->state.height = p->size.cy;
    p->state.owner = p->owner;
    p->state.rows = (int32_t)p->model.rows.size();
    p->state.highlighted = p->model.highlighted;
    p->state.dpi = (int32_t)p->dpi;
    p->state.notice = p->notice.empty() ? 0 : 1;
    p->state.caretX = p->caretDrawn.x;
    p->state.caretY = p->caretDrawn.y;
    p->state.scrolled = p->scrolled;
    if (p->images) {
        std::lock_guard<std::mutex> images(p->images->lock);
        p->state.images = (int32_t)p->images->entries.size();
    }
}

bool EnsureBitmap(AioPanel *p, int width, int height) {
    if (p->bitmap && width <= p->bitmapWidth && height <= p->bitmapHeight) return true;
    if (p->bitmap) {
        SelectObject(p->memoryDC, p->oldBitmap);
        DeleteObject(p->bitmap);
        p->bitmap = nullptr;
    }
    if (!p->memoryDC) p->memoryDC = CreateCompatibleDC(nullptr);
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof info.bmiHeader;
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;  // top-down
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    p->bitmap = CreateDIBSection(p->memoryDC, &info, DIB_RGB_COLORS, &p->bits, nullptr, 0);
    if (!p->bitmap) return false;
    p->oldBitmap = SelectObject(p->memoryDC, p->bitmap);
    p->bitmapWidth = width;
    p->bitmapHeight = height;
    return true;
}

void HideWindow(AioPanel *p) {
    if (p->visible) ShowWindow(p->hwnd, SW_HIDE);
    p->visible = false;
    p->modelShown = false;
    p->noticeAlone = false;
    KillTimer(p->hwnd, kCaretTimer);
    p->waitingForCaret = false;
    PublishState(p);
}

// A text layout of `text` in `format`, `width` wide: on one line ending in an ellipsis, or wrapped (`wrap`).
IDWriteTextLayout *MakeLayout(AioPanel *p, const std::wstring &text, IDWriteTextFormat *format, float width, bool wrap) {
    if (!format) return nullptr;
    IDWriteTextLayout *layout = nullptr;
    p->dwrite->CreateTextLayout(text.c_str(), (UINT32)text.size(), format, std::max(width, 1.0f), 100000.0f, &layout);
    if (layout && wrap) {
        layout->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP);
        DWRITE_TRIMMING none = {DWRITE_TRIMMING_GRANULARITY_NONE, 0, 0};
        layout->SetTrimming(&none, nullptr);
    }
    return layout;
}

// A layout's size in pixels, at most `maxWidth` wide.
D2D1_SIZE_F LayoutSize(IDWriteTextLayout *layout, float maxWidth) {
    if (!layout) return D2D1::SizeF(0, 0);
    DWRITE_TEXT_METRICS metrics = {};
    layout->GetMetrics(&metrics);
    return D2D1::SizeF(std::min(std::ceil(metrics.widthIncludingTrailingWhitespace), maxWidth), std::ceil(metrics.height));
}

// `colorFonts`: emoji in color (rime-ice's candidates, a row's); off, all of it in `color` (the status's ⚠).
void DrawLayout(AioPanel *p, IDWriteTextLayout *layout, float x, float y, const D2D1_COLOR_F &color, bool colorFonts = true) {
    if (!layout) return;
    ID2D1SolidColorBrush *brush = nullptr;
    p->target->CreateSolidColorBrush(color, &brush);
    if (!brush) return;
    p->target->DrawTextLayout(D2D1::Point2F(x, y), layout, brush,
                              colorFonts ? D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT : D2D1_DRAW_TEXT_OPTIONS_NONE);
    brush->Release();
}

void Fill(AioPanel *p, D2D1_RECT_F rect, const D2D1_COLOR_F &color) {
    ID2D1SolidColorBrush *brush = nullptr;
    p->target->CreateSolidColorBrush(color, &brush);
    if (!brush) return;
    p->target->FillRectangle(rect, brush);
    brush->Release();
}

// `path` read with `wic` into `entry`'s pixels (premultiplied BGRA, at most 128 pixels a side; none when it can't be).
void ReadImage(IWICImagingFactory *wic, const std::wstring &path, ImageEntry &entry) {
    entry.pixels.clear();
    entry.width = entry.height = 0;
    IWICBitmapDecoder *decoder = nullptr;
    IWICBitmapFrameDecode *frame = nullptr;
    IWICBitmapScaler *scaler = nullptr;
    IWICFormatConverter *converter = nullptr;
    UINT width = 0, height = 0;
    if (wic && SUCCEEDED(wic->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
                                                        &decoder)) &&
        SUCCEEDED(decoder->GetFrame(0, &frame)) && SUCCEEDED(frame->GetSize(&width, &height)) && width && height) {
        IWICBitmapSource *frameSource = frame;
        const UINT most = 128;
        if ((width > most || height > most) && SUCCEEDED(wic->CreateBitmapScaler(&scaler))) {
            float ratio = std::min(most / (float)width, most / (float)height);
            if (SUCCEEDED(scaler->Initialize(frame, std::max(1u, (UINT)(width * ratio)), std::max(1u, (UINT)(height * ratio)),
                                             WICBitmapInterpolationModeFant))) {
                frameSource = scaler;
            }
        }
        UINT w = 0, h = 0;
        if (SUCCEEDED(wic->CreateFormatConverter(&converter)) &&
            SUCCEEDED(converter->Initialize(frameSource, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nullptr, 0,
                                            WICBitmapPaletteTypeMedianCut)) &&
            SUCCEEDED(converter->GetSize(&w, &h)) && w && h) {
            std::vector<BYTE> pixels((size_t)w * h * 4);
            if (SUCCEEDED(converter->CopyPixels(nullptr, w * 4, (UINT)pixels.size(), pixels.data()))) {
                entry.pixels = std::move(pixels);
                entry.width = w;
                entry.height = h;
            }
        }
    }
    SafeRelease(converter);
    SafeRelease(scaler);
    SafeRelease(frame);
    SafeRelease(decoder);
}

// The file's time and size now; false when it isn't there or can't be asked.
bool FileStamp(const std::wstring &path, FILETIME &written, ULONGLONG &size) {
    WIN32_FILE_ATTRIBUTE_DATA data = {};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return false;
    written = data.ftLastWriteTime;
    size = ((ULONGLONG)data.nFileSizeHigh << 32) | data.nFileSizeLow;
    return true;
}

// The image loader's thread: each path asked for is looked at (its time and size) and read again unless it is as it
// was (read once at least), then the window is told when what it draws changed.
void LoadImages(std::shared_ptr<ImageLoader> loader) {
    const HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    IWICImagingFactory *wic = nullptr;
    CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory),
                     reinterpret_cast<void **>(&wic));
    std::unique_lock<std::mutex> lock(loader->lock);
    auto entry = [&](const std::wstring &path) -> ImageEntry * {
        for (ImageEntry &e : loader->entries) {
            if (e.path == path) return &e;
        }
        return nullptr;
    };
    while (true) {
        loader->idle += 1;
        loader->wake.wait(lock, [&] { return loader->stopping || !loader->pending.empty(); });
        loader->idle -= 1;
        if (loader->stopping) break;
        const std::wstring path = std::move(loader->pending.front());
        loader->pending.pop_front();
        ImageEntry *before = entry(path);
        if (!before) continue;  // no longer kept
        const ImageEntry was = *before;
        const ULONGLONG started = GetTickCount64();
        loader->reading.push_back(started);
        lock.unlock();
        ImageEntry read;
        FILETIME written = {};
        ULONGLONG size = 0;
        const bool exists = FileStamp(path, written, size);
        const bool same = was.tried && exists == was.exists &&
                          (!exists || (CompareFileTime(&written, &was.written) == 0 && size == was.size));
        if (!same && exists) ReadImage(wic, path, read);
        lock.lock();
        loader->reading.erase(std::find(loader->reading.begin(), loader->reading.end(), started));
        ImageEntry *now = entry(path);
        if (!now) continue;
        now->loading = false;
        now->checkedAt = GetTickCount64();
        if (same) continue;
        const bool changed = !was.pixels.empty() || !read.pixels.empty();
        now->tried = true;
        now->exists = exists;
        now->written = written;
        now->size = size;
        now->pixels = std::move(read.pixels);
        now->width = read.width;
        now->height = read.height;
        if (changed && loader->notify) PostMessageW(loader->notify, kImagesRead, 0, 0);
    }
    loader->threads -= 1;
    lock.unlock();
    SafeRelease(wic);
    if (SUCCEEDED(init)) CoUninitialize();
}

// A thread for each image waiting to be read (the loader's lock held): one waiting for a path, else a new one while
// fewer than kImageReaders read without being stuck (kImageStuckMs), kMaxImageThreads in all. False when one waits for
// a read to end or to be stuck: the window looks again (kImageTimer).
bool ReadPending(const std::shared_ptr<ImageLoader> &loader) {
    for (size_t asked = 0; asked < loader->pending.size(); asked++) {
        if (asked < loader->idle) {
            loader->wake.notify_one();
            continue;
        }
        const ULONGLONG now = GetTickCount64();
        const size_t stuck = (size_t)std::count_if(loader->reading.begin(), loader->reading.end(),
                                                   [&](ULONGLONG started) { return now - started >= kImageStuckMs; });
        if (loader->threads >= kMaxImageThreads) return true;  // till a read ends
        if (loader->threads - std::min(stuck, loader->threads) >= kImageReaders) return false;
        loader->threads += 1;
        std::thread(LoadImages, loader).detach();
    }
    return true;
}

// `path` to be looked at by the loader's threads (its lock held).
void AskForImage(const std::shared_ptr<ImageLoader> &loader, const std::wstring &path) {
    loader->pending.push_back(path);
    if (!ReadPending(loader) && loader->notify) SetTimer(loader->notify, kImageTimer, (UINT)kImageStuckMs, nullptr);
}

// `entry`'s pixels as a bitmap of the render target's; nil without pixels.
ID2D1Bitmap *Bitmap(AioPanel *p, const ImageEntry &entry) {
    if (entry.pixels.empty()) return nullptr;
    ID2D1Bitmap *bitmap = nullptr;
    D2D1_BITMAP_PROPERTIES properties =
        D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    p->target->CreateBitmap(D2D1::SizeU(entry.width, entry.height), entry.pixels.data(), entry.width * 4, properties, &bitmap);
    return bitmap;
}

// The image at `path` for this draw, as last read; nil while it is being read the first time, or when it can't be (the
// fallback is drawn, and the image once it comes: kImagesRead). One last looked at kImageRecheckMs ago or more is looked
// at again in the background, so that a file changed, or one readable now, is drawn as it is. Where there is no window
// (`readImagesNow`), read here.
ID2D1Bitmap *Image(AioPanel *p, const std::wstring &path) {
    if (p->readImagesNow) {
        if (!p->wic) {
            CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory),
                             reinterpret_cast<void **>(&p->wic));
        }
        ImageEntry entry;
        ReadImage(p->wic, path, entry);
        return Bitmap(p, entry);
    }
    if (!p->images) {
        p->images = std::make_shared<ImageLoader>();
        p->images->notify = p->hwnd;
    }
    ImageLoader &loader = *p->images;
    std::lock_guard<std::mutex> lock(loader.lock);
    const ULONGLONG now = GetTickCount64();
    auto found = std::find_if(loader.entries.begin(), loader.entries.end(), [&](const ImageEntry &e) { return e.path == path; });
    if (found == loader.entries.end()) {
        if (loader.entries.size() >= kMaxImages) {
            auto oldest = loader.entries.end();
            for (auto e = loader.entries.begin(); e != loader.entries.end(); ++e) {
                if (!e->loading && (oldest == loader.entries.end() || e->usedAt < oldest->usedAt)) oldest = e;
            }
            // All being read (shares that don't answer): none kept for this one, its fallback drawn until one is done.
            if (oldest == loader.entries.end()) return nullptr;
            loader.entries.erase(oldest);
        }
        ImageEntry entry;
        entry.path = path;
        entry.loading = true;
        entry.checkedAt = entry.usedAt = now;
        loader.entries.push_back(std::move(entry));
        AskForImage(p->images, path);
        return nullptr;
    }
    found->usedAt = now;
    if (!found->loading && now - found->checkedAt >= kImageRecheckMs) {
        found->loading = true;
        found->checkedAt = now;
        AskForImage(p->images, path);
    }
    return Bitmap(p, *found);
}

// A row's icon in `box`: an image or an emoji in the square's place, else the glyph white on its colored rounded square
// (the fallback glyph where the image can't be read, or isn't yet). An emoji a font has no color for is in `color`, the
// row's text's.
void DrawIcon(AioPanel *p, const Icon &icon, D2D1_RECT_F box, const D2D1_COLOR_F &color) {
    const float side = box.right - box.left;
    if (icon.kind == AIO_ICON_IMAGE) {
        if (ID2D1Bitmap *bitmap = Image(p, icon.text)) {
            D2D1_SIZE_F size = bitmap->GetSize();
            float ratio = std::min(side / std::max(size.width, 1.0f), side / std::max(size.height, 1.0f));
            float w = size.width * ratio, h = size.height * ratio;
            float x = box.left + (side - w) / 2, y = box.top + (side - h) / 2;
            p->target->DrawBitmap(bitmap, D2D1::RectF(x, y, x + w, y + h), 1.0f, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
            bitmap->Release();
            return;
        }
    } else if (icon.kind == AIO_ICON_EMOJI && !icon.text.empty()) {
        float grow = std::round(side * 0.2f);
        DrawText(p, icon.text, p->emojiFormat, box.left - grow, box.top - grow, side + 2 * grow, side + 2 * grow, color,
                 DWRITE_TEXT_ALIGNMENT_CENTER);
        return;
    }
    const std::wstring &glyph = icon.kind == AIO_ICON_GLYPH ? icon.text : icon.fallback;
    FillRounded(p, box, std::round(side * 0.24f), Rgb(icon.color));
    DrawText(p, glyph, p->iconFormat, box.left, box.top, side, side, Rgb(0xFFFFFF), DWRITE_TEXT_ALIGNMENT_CENTER);
}

// Lays `model` out at the panel's DPI and draws it into the panel's bitmap, in the dark or the light theme: its size, the
// rows' rectangles (clicks), where the first row's text starts (the caret goes under it), where the input's caret was
// drawn and how far a conversation's rows are scrolled. A conversation (`transcript`) is no taller than `maxHeight`
// pixels (0: no limit). From top to bottom: the hand-off, the input, the header's lines, the rows, the status, the
// footer.
bool Paint(AioPanel *p, const Model &model, bool dark, float maxHeight) {
    MakeFormats(p);
    const float s = Scale(p);
    const Colors colors = ThemeColors(dark);
    const float padding = std::round(6 * s), insetX = std::round(8 * s), insetY = std::round(4 * s);
    const float labelGap = std::round(8 * s), commentGap = std::round(12 * s), lineGap = std::round(4 * s);
    const float maxText = std::round(520 * s), minWidth = std::round(260 * s), maxRow = std::round(600 * s);
    const float radius = std::round(8 * s);
    const float iconSize = std::round(20 * s), iconGap = std::round(8 * s);
    const float chipGap = std::round(6 * s), chipPadX = std::round(9 * s), chipPadY = std::round(3 * s);
    const float shortcutGap = std::round(5 * s), bulletIndent = std::round(8 * s);

    const float textHeight = Measure(p, L"Ag中", p->textFormat, maxText).height;
    const float rowHeight = textHeight + 2 * insetY;
    const float footerHeight = Measure(p, L"Ag中", p->footerFormat, maxText).height;
    const float statusHeight = Measure(p, L"Ag中", p->statusFormat, maxText).height;
    const float digitHeight = Measure(p, L"0", p->labelFormat, maxText).height;
    float labelWidth = 0;
    for (const Row &row : model.rows) labelWidth = std::max(labelWidth, Measure(p, row.label, p->labelFormat, maxText).width);
    const bool icons = !model.horizontal && std::any_of(model.rows.begin(), model.rows.end(),
                                                        [](const Row &row) { return row.icon.kind != AIO_ICON_NONE; });
    const float iconColumn = icons ? iconSize + iconGap : 0;
    const float lead = insetX + labelWidth + labelGap + iconColumn;  // a vertical row's text starts here

    // Laid out in the content's coordinates (x from the panel's padding, y from its top), then drawn.
    float contentWidth = 0, y = padding;
    auto widen = [&](float w) { contentWidth = std::max(contentWidth, w); };

    // Where a conversation can go on: its title, then a chip per destination, wrapping.
    float handoffTitleY = -1;
    struct PlacedChip {
        float x, y, w, h, shortcutW;
    };
    std::vector<PlacedChip> chips;
    if (!model.handoffTitle.empty()) {
        widen(Measure(p, model.handoffTitle, p->statusFormat, maxRow).width + 2 * insetX);
        handoffTitleY = y;
        y += statusHeight + lineGap;
    }
    if (!model.handoff.empty()) {
        const float chipH = statusHeight + 2 * chipPadY;
        float x = insetX, top = y;
        for (const Chip &chip : model.handoff) {
            float sw = Measure(p, chip.shortcut, p->labelFormat, maxRow).width;
            float nw = Measure(p, chip.name, p->statusFormat, maxRow).width;
            float w = chipPadX + sw + (sw > 0 ? shortcutGap : 0) + nw + chipPadX;
            if (x > insetX && x + w > maxRow + insetX) {
                x = insetX;
                top += chipH + chipGap;
            }
            chips.push_back({x, top, w, chipH, sw});
            x += w + chipGap;
            widen(x - chipGap + insetX);
        }
        y = top + chipH + lineGap;
    }

    // The input: its prompt and its text, wrapped.
    IDWriteTextLayout *input = nullptr;
    float inputY = -1;
    if (model.hasInput) {
        input = MakeLayout(p, model.inputPrompt + model.inputText, p->textFormat, maxRow, true);
        if (input) {
            D2D1_SIZE_F size = LayoutSize(input, maxRow);
            widen(size.width + 2 * insetX + std::round(2 * s));  // room for the caret after the last character
            inputY = y;
            y += std::max(size.height, textHeight) + lineGap;
        }
    }
    // The header's lines, each its own.
    std::vector<float> headerY;
    for (const std::wstring &line : model.header) {
        widen(Measure(p, line, p->statusFormat, maxRow).width + 2 * insetX);
        headerY.push_back(y);
        y += statusHeight + lineGap;
    }

    // The rows: side by side, one under the other, or a conversation's, wrapped.
    struct Placed {
        float x, y, w, h, textW, commentW;
        IDWriteTextLayout *wrapped;
    };
    std::vector<Placed> placed;
    const float rowsTop = y;
    float rowsHeight = 0;
    if (model.horizontal) {
        float x = 0, lineY = y;
        for (const Row &row : model.rows) {
            float w = Measure(p, row.text, p->textFormat, std::round(280 * s)).width;
            float lw = Measure(p, row.label, p->labelFormat, maxText).width;
            float cell = insetX + lw + std::round(4 * s) + w + insetX;
            if (x > 0 && x + cell > maxRow) {
                x = 0;
                lineY += rowHeight;
            }
            placed.push_back({x, lineY, cell, rowHeight, w, 0, nullptr});
            x += cell + std::round(2 * s);
            widen(x);
        }
        if (!model.rows.empty()) rowsHeight = lineY + rowHeight - y;
    } else {
        float top = y;
        for (const Row &row : model.rows) {
            float cw = row.comment.empty() ? 0 : Measure(p, row.comment, p->commentFormat, std::round(200 * s)).width;
            if (model.transcript) {
                float room = std::min(maxText, maxRow - lead - insetX - (cw > 0 ? commentGap + cw : 0));
                IDWriteTextLayout *wrapped = MakeLayout(p, row.text, p->textFormat, room, true);
                D2D1_SIZE_F size = LayoutSize(wrapped, room);
                float h = std::max(size.height, textHeight) + 2 * insetY;
                float rowWidth = lead + size.width + (cw > 0 ? commentGap + cw : 0) + insetX;
                placed.push_back({0, top, rowWidth, h, size.width, cw, wrapped});
                widen(rowWidth);
                top += h;
            } else {
                float w = Measure(p, row.text, p->textFormat, maxText).width;
                float rowWidth = lead + w + (cw > 0 ? commentGap + cw : 0) + insetX;
                placed.push_back({0, top, rowWidth, rowHeight, w, cw, nullptr});
                widen(rowWidth);
                top += rowHeight;
            }
        }
        rowsHeight = top - y;
    }
    y += rowsHeight;
    if (!model.rows.empty()) y += lineGap;

    // The status: a hint, a wait, an error (after ⚠), or a hint and its list's items, a line each; wrapped (a message
    // from elsewhere may have several lines).
    IDWriteTextLayout *status = nullptr;
    std::vector<IDWriteTextLayout *> items;
    std::vector<float> itemY;
    float statusY = -1;
    if (model.statusKind != AIO_STATUS_NONE) {
        std::wstring text = model.statusKind == AIO_STATUS_ERROR && !model.status.empty() ? L"⚠︎ " + model.status : model.status;
        if (!text.empty()) {
            status = MakeLayout(p, text, p->statusFormat, maxRow, true);
            D2D1_SIZE_F size = LayoutSize(status, maxRow);
            widen(size.width + 2 * insetX);
            statusY = y;
            y += std::max(size.height, statusHeight) + lineGap;
        }
        if (model.statusKind == AIO_STATUS_LIST) {
            for (const std::wstring &item : model.statusItems) {
                IDWriteTextLayout *layout = MakeLayout(p, L"•  " + item, p->statusFormat, maxRow - bulletIndent, true);
                D2D1_SIZE_F size = LayoutSize(layout, maxRow);
                widen(bulletIndent + size.width + 2 * insetX);
                items.push_back(layout);
                itemY.push_back(y);
                y += std::max(size.height, statusHeight) + std::round(2 * s);
            }
            if (!items.empty()) y += lineGap;
        }
    }
    // The footer, the detail on its right.
    float footerY = -1;
    const bool footerRule = y > padding;
    if (!model.footer.empty() || !model.detail.empty()) {
        float fw = Measure(p, model.footer, p->footerFormat, maxRow).width;
        float dw = Measure(p, model.detail, p->footerFormat, maxText).width;
        widen(insetX + fw + (dw > 0 ? commentGap + dw : 0) + insetX);
        if (footerRule) y += std::round(3 * s);
        footerY = y;
        y += footerHeight + insetY;
    }
    float height = y + padding - (footerY < 0 && statusY < 0 && items.empty() && !model.rows.empty() ? lineGap : 0);

    // A conversation no taller than `maxHeight`: its rows scrolled to show the last one, or the highlighted one when it
    // is above; what comes after the rows moves up.
    float scroll = 0, rowsView = rowsHeight;
    if (model.transcript && maxHeight > 0 && height > maxHeight && rowsHeight > 0) {
        rowsView = std::max(rowHeight, rowsHeight - (height - maxHeight));
        scroll = rowsHeight - rowsView;
        if (model.highlighted >= 0 && model.highlighted < (int)placed.size()) {
            float top = placed[model.highlighted].y - rowsTop;
            if (top < scroll) scroll = top;
        }
        float cut = rowsHeight - rowsView;
        height -= cut;
        if (statusY >= 0) statusY -= cut;
        for (float &v : itemY) v -= cut;
        if (footerY >= 0) footerY -= cut;
    }

    // A notice on its own is only as wide as it needs.
    const float width = std::ceil(std::min(std::max(contentWidth, p->noticeAlone ? 0.0f : minWidth), maxRow + 2 * insetX) +
                                  2 * padding);
    height = std::ceil(height);
    const int w = (int)width, h = (int)height;
    auto release = [&]() {
        SafeRelease(input);
        SafeRelease(status);
        for (auto *layout : items) SafeRelease(layout);
        for (auto &row : placed) SafeRelease(row.wrapped);
    };
    if (!EnsureBitmap(p, w, h)) {
        release();
        return false;
    }

    // Draw.
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
    if (!p->target) p->d2d->CreateDCRenderTarget(&props, &p->target);
    if (!p->target) {
        release();
        return false;
    }
    RECT bind = {0, 0, w, h};
    p->target->BindDC(p->memoryDC, &bind);
    p->target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    p->target->BeginDraw();
    p->target->Clear(D2D1::ColorF(0, 0, 0, 0));
    FillRounded(p, D2D1::RectF(0.5f, 0.5f, width - 0.5f, height - 0.5f), radius, colors.border);
    FillRounded(p, D2D1::RectF(1.5f, 1.5f, width - 1.5f, height - 1.5f), radius - 1, colors.background);
    const float left = padding, inner = width - 2 * padding;

    if (handoffTitleY >= 0) {
        DrawText(p, model.handoffTitle, p->statusFormat, left + insetX, handoffTitleY, inner - 2 * insetX, statusHeight,
                 colors.secondary);
    }
    for (size_t i = 0; i < chips.size(); ++i) {
        const PlacedChip &chip = chips[i];
        FillRounded(p, D2D1::RectF(left + chip.x, chip.y, left + chip.x + chip.w, chip.y + chip.h), chip.h / 2, colors.chip);
        float x = left + chip.x + chipPadX;
        DrawText(p, model.handoff[i].shortcut, p->labelFormat, x, chip.y + chipPadY + (statusHeight - digitHeight) / 2,
                 chip.shortcutW + 1, statusHeight, colors.highlight);
        x += chip.shortcutW + (chip.shortcutW > 0 ? shortcutGap : 0);
        DrawText(p, model.handoff[i].name, p->statusFormat, x, chip.y + chipPadY, left + chip.x + chip.w - chipPadX - x + 1,
                 statusHeight, colors.text);
    }

    // The input, its prompt dimmed; its caret where DirectWrite puts that position.
    p->caretDrawn = {-1, -1};
    if (input) {
        ID2D1SolidColorBrush *dim = nullptr;
        p->target->CreateSolidColorBrush(colors.secondary, &dim);
        if (dim && !model.inputPrompt.empty()) input->SetDrawingEffect(dim, {0, (UINT32)model.inputPrompt.size()});
        DrawLayout(p, input, left + insetX, inputY, colors.text);
        if (model.inputCaret >= 0) {
            FLOAT cx = 0, cy = 0;
            DWRITE_HIT_TEST_METRICS hit = {};
            input->HitTestTextPosition((UINT32)(model.inputPrompt.size() + model.inputCaret), FALSE, &cx, &cy, &hit);
            float x = std::round(left + insetX + cx), top = std::round(inputY + cy);
            float caretHeight = hit.height > 0 ? hit.height : textHeight;
            Fill(p, D2D1::RectF(x, top, x + std::max(1.0f, std::round(1.5f * s)), top + caretHeight), colors.highlight);
            p->caretDrawn = {(LONG)x, (LONG)top};
        }
        SafeRelease(dim);
    }
    for (size_t i = 0; i < model.header.size(); ++i) {
        DrawText(p, model.header[i], p->statusFormat, left + insetX, headerY[i], inner - 2 * insetX, statusHeight, colors.secondary);
    }

    // The rows (a conversation's clipped to what is shown of them).
    const bool clipped = model.transcript && rowsView < rowsHeight;
    if (clipped) p->target->PushAxisAlignedClip(D2D1::RectF(0, rowsTop, width, rowsTop + rowsView), D2D1_ANTIALIAS_MODE_ALIASED);
    p->rowRects.clear();
    p->rowPickable.clear();
    for (size_t i = 0; i < model.rows.size(); ++i) {
        const Row &row = model.rows[i];
        const Placed &pl = placed[i];
        const float x = left + pl.x, top = pl.y - scroll;
        const float rowW = model.horizontal ? pl.w : inner;
        const bool lit = (int)i == model.highlighted;
        if (lit) FillRounded(p, D2D1::RectF(x, top, x + rowW, top + pl.h), std::round(5 * s), colors.highlight);
        D2D1_COLOR_F textColor = lit ? colors.highlightText : (row.style == 1 || !row.complete) ? colors.secondary : colors.text;
        D2D1_COLOR_F dim = lit ? colors.highlightText : colors.secondary;
        float lw = model.horizontal ? Measure(p, row.label, p->labelFormat, maxText).width : labelWidth;
        DrawText(p, row.label, p->labelFormat, x + insetX, top + insetY + (textHeight - digitHeight) / 2, lw + 1, textHeight, dim);
        float tx = x + insetX + lw + (model.horizontal ? std::round(4 * s) : labelGap);
        if (icons) {
            if (row.icon.kind != AIO_ICON_NONE) {
                float iy = top + insetY + (textHeight - iconSize) / 2;
                DrawIcon(p, row.icon, D2D1::RectF(tx, iy, tx + iconSize, iy + iconSize), textColor);
            }
            tx += iconColumn;
        }
        if (pl.wrapped) {
            DrawLayout(p, pl.wrapped, tx, top + insetY, textColor);
        } else {
            float textRoom = model.horizontal ? pl.textW + 1 : std::min(pl.textW + 1, x + rowW - insetX - tx);
            DrawText(p, row.text, p->textFormat, tx, top + insetY, textRoom, textHeight, textColor);
        }
        if (!model.horizontal && pl.commentW > 0) {
            float cx = std::max(x + rowW - insetX - pl.commentW, tx + pl.textW + commentGap);
            float cy = top + insetY + (textHeight - Measure(p, L"Ag", p->commentFormat, maxText).height) / 2;
            DrawText(p, row.comment, p->commentFormat, cx, cy, x + rowW - insetX - cx + 1, textHeight, dim);
        }
        // Where a click picks it: what is shown of it.
        float visibleTop = clipped ? std::max(top, rowsTop) : top;
        float visibleBottom = clipped ? std::min(top + pl.h, rowsTop + rowsView) : top + pl.h;
        RECT r = visibleBottom > visibleTop ? RECT{(LONG)x, (LONG)visibleTop, (LONG)(x + rowW), (LONG)visibleBottom} : RECT{0, 0, 0, 0};
        p->rowRects.push_back(r);
        p->rowPickable.push_back(row.pickable && visibleBottom > visibleTop);
    }
    if (clipped) {
        p->target->PopAxisAlignedClip();
        if (scroll > 0.5f) Fill(p, D2D1::RectF(left + insetX, rowsTop, width - padding - insetX, rowsTop + 1), colors.border);
        if (scroll < rowsHeight - rowsView - 0.5f) {
            Fill(p, D2D1::RectF(left + insetX, rowsTop + rowsView - 1, width - padding - insetX, rowsTop + rowsView), colors.border);
        }
    }

    if (status) {
        D2D1_COLOR_F color = model.statusKind == AIO_STATUS_ERROR     ? colors.error
                             : model.statusKind == AIO_STATUS_LOADING ? colors.secondary
                                                                      : colors.text;
        DrawLayout(p, status, left + insetX, statusY, color, model.statusKind != AIO_STATUS_ERROR);
    }
    for (size_t i = 0; i < items.size(); ++i) DrawLayout(p, items[i], left + insetX + bulletIndent, itemY[i], colors.secondary);
    if (footerY >= 0) {
        if (footerRule) {
            float ruleY = std::round(footerY - std::round(3 * s)) + 0.5f;
            Fill(p, D2D1::RectF(left + insetX, ruleY - 0.5f, width - padding - insetX, ruleY + 0.5f), colors.border);
        }
        float dw = Measure(p, model.detail, p->footerFormat, maxText).width;
        DrawText(p, model.footer, p->footerFormat, left + insetX, footerY, inner - 2 * insetX - (dw > 0 ? dw + commentGap : 0),
                 footerHeight, colors.secondary);
        if (dw > 0) {
            DrawText(p, model.detail, p->footerFormat, width - padding - insetX - dw - 1, footerY, dw + 1, footerHeight,
                     p->notice.empty() ? colors.secondary : colors.text);
        }
    }
    HRESULT hr = p->target->EndDraw();
    if (hr == D2DERR_RECREATE_TARGET) SafeRelease(p->target);
    release();

    p->textInset = padding + insetX + (model.horizontal ? 0 : labelWidth + labelGap + iconColumn);
    p->scrolled = (int)std::round(scroll);
    p->size = {w, h};
    return true;
}

// Lays the panel out at the caret's monitor's DPI, draws it and puts it on screen: only while its owner owns the
// foreground (which may have changed since it was asked, while the panel waited for the caret). A conversation is no
// taller than half that monitor's work area.
void Render(AioPanel *p) {
    if (p->ownerPid && !OwnsForeground(p->ownerPid, p->ownerTrusted)) {
        p->model = Model();
        p->notice.clear();
        HideWindow(p);
        return;
    }
    Model model = p->noticeAlone ? Model() : p->model;
    if (p->noticeAlone) {
        model.statusKind = AIO_STATUS_HINT;
        model.status = p->notice;
    } else if (!p->notice.empty()) {
        model.detail = p->notice;
    }
    if (model.empty() || !p->hasCaret) {
        HideWindow(p);
        return;
    }
    RECT work = {};
    POINT anchor = {p->caret.x, p->caret.y + p->caret.height};
    p->dpi = DpiAt(anchor, &work);
    if (!Paint(p, model, DarkTheme(), (work.bottom - work.top) / 2.0f)) return;
    const float s = Scale(p);
    const int w = p->size.cx, h = p->size.cy;

    // Place it: the first row's text under the caret, below the caret line, or above it when there is no room; inside
    // the monitor's work area.
    int x = p->caret.x - (int)p->textInset;
    int top = p->caret.y + p->caret.height + (int)std::round(4 * s);
    if (top + h > work.bottom) top = p->caret.y - h - (int)std::round(4 * s);
    x = std::max<int>(work.left, std::min<int>(x, work.right - w));
    top = std::max<int>(work.top, std::min<int>(top, work.bottom - h));
    p->position = {x, top};

    POINT source = {0, 0};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    HDC screen = GetDC(nullptr);
    UpdateLayeredWindow(p->hwnd, screen, &p->position, &p->size, p->memoryDC, &source, 0, &blend, ULW_ALPHA);
    ReleaseDC(nullptr, screen);
    if (!IsWindowVisible(p->hwnd)) ShowWindow(p->hwnd, SW_SHOWNOACTIVATE);
    SetWindowPos(p->hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    p->visible = true;
    {
        std::lock_guard<std::mutex> lock(p->stateLock);
        p->state.draws += 1;
    }
    PublishState(p);
}

void Handle(AioPanel *p, Command *c) {
    switch (c->op) {
    case OpShow: {
        // A session in a process without the foreground draws nothing (and takes nothing down but its own).
        if (c->ownerPid && !OwnsForeground(c->ownerPid, c->ownerTrusted)) {
            if (c->owner == p->owner) {
                p->model = Model();
                HideWindow(p);
            }
            break;
        }
        bool newOwner = c->owner != p->owner;
        p->owner = c->owner;
        p->ownerPid = c->ownerPid;
        p->ownerTrusted = c->ownerTrusted;
        p->model = std::move(c->model);
        p->modelShown = true;
        p->noticeAlone = false;
        if (c->hasCaret) {
            p->caret = c->caret;
            p->hasCaret = true;
            p->waitingForCaret = false;
            KillTimer(p->hwnd, kCaretTimer);
        } else if (newOwner || !p->hasCaret) {
            // §6: wait up to 50 ms for the DLL's caret report before the first draw, then go by the system's caret.
            p->hasCaret = false;
            if (!p->waitingForCaret) {
                p->waitingForCaret = true;
                SetTimer(p->hwnd, kCaretTimer, 50, nullptr);
            }
            PublishState(p);
            return;
        }
        Render(p);
        break;
    }
    case OpHide:
        if (c->owner == 0 || c->owner == p->owner) {
            p->model = Model();
            if (p->noticeAlone || !p->notice.empty()) {
                // A notice outlives the panel it was beside, on its own, until it expires.
                if (!p->notice.empty() && p->hasCaret) {
                    p->noticeAlone = true;
                    p->modelShown = false;
                    Render(p);
                    break;
                }
            }
            HideWindow(p);
        }
        break;
    case OpMove:
        if (c->owner == p->owner) {
            p->caret = c->caret;
            p->hasCaret = true;
            if (p->waitingForCaret) {
                p->waitingForCaret = false;
                KillTimer(p->hwnd, kCaretTimer);
            }
            if (p->modelShown || p->noticeAlone) Render(p);
        }
        break;
    case OpNotice:
        // Not from a process without the foreground, and never over another session's panel.
        if (c->ownerPid && !OwnsForeground(c->ownerPid, c->ownerTrusted)) break;
        if (p->modelShown && p->visible && c->owner != p->owner) break;
        p->notice = c->text;
        SetTimer(p->hwnd, kNoticeTimer, (UINT)std::max(c->durationMs, 300), nullptr);
        if (p->modelShown && p->visible && c->owner == p->owner) {
            Render(p);
        } else {
            p->owner = c->owner;
            p->ownerPid = c->ownerPid;
            p->ownerTrusted = c->ownerTrusted;
            p->model = Model();
            p->modelShown = false;
            p->noticeAlone = true;
            if (c->hasCaret) {
                p->caret = c->caret;
                p->hasCaret = true;
            } else if (!p->hasCaret) {
                p->caret = FallbackCaret();
                p->hasCaret = true;
            }
            Render(p);
        }
        break;
    }
}

void CALLBACK ForegroundChanged(HWINEVENTHOOK, DWORD, HWND hwnd, LONG, LONG, DWORD, DWORD) {
    AioPanel *p = g_panel;
    if (!p || !p->visible || !hwnd) return;
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid == GetCurrentProcessId() || (p->ownerPid && InFront(hwnd, p->ownerPid, p->ownerTrusted))) return;
    // Another app took the foreground: the panel isn't for it.
    p->model = Model();
    p->notice.clear();
    HideWindow(p);
}

int RowAt(AioPanel *p, POINT pt) {
    for (size_t i = 0; i < p->rowRects.size(); ++i) {
        if (PtInRect(&p->rowRects[i], pt)) return (int)i;
    }
    return -1;
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    AioPanel *p = reinterpret_cast<AioPanel *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (message) {
    case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;  // a click never takes the focus from the app being typed in
    case WM_SETCURSOR:
        if (p) {
            POINT pt;
            GetCursorPos(&pt);
            ScreenToClient(hwnd, &pt);
            int row = RowAt(p, pt);
            SetCursor(LoadCursorW(nullptr, row >= 0 && p->rowPickable[row] ? IDC_HAND : IDC_ARROW));
            return TRUE;
        }
        break;
    case WM_LBUTTONUP:
        if (p && p->modelShown) {
            POINT pt = {(short)LOWORD(lParam), (short)HIWORD(lParam)};
            int row = RowAt(p, pt);
            if (row >= 0 && p->rowPickable[row] && p->callbacks.click) p->callbacks.click(p->callbacks.context, p->owner, row);
        }
        return 0;
    case WM_MOUSEWHEEL:
        if (p && p->modelShown && p->callbacks.scroll) {
            int delta = GET_WHEEL_DELTA_WPARAM(wParam);
            int steps = delta > 0 ? -1 : 1;
            p->callbacks.scroll(p->callbacks.context, p->owner, steps);
        }
        return 0;
    case WM_TIMER:
        if (!p) break;
        if (wParam == kNoticeTimer) {
            KillTimer(hwnd, kNoticeTimer);
            p->notice.clear();
            if (p->noticeAlone) {
                HideWindow(p);
            } else if (p->visible) {
                Render(p);
            } else {
                PublishState(p);
            }
        } else if (wParam == kImageTimer) {
            bool done = true;
            if (p->images) {
                std::lock_guard<std::mutex> lock(p->images->lock);
                done = ReadPending(p->images);
            }
            if (done) KillTimer(hwnd, kImageTimer);
        } else if (wParam == kCaretTimer) {
            KillTimer(hwnd, kCaretTimer);
            if (p->waitingForCaret) {
                p->waitingForCaret = false;
                p->caret = FallbackCaret();
                p->hasCaret = true;
                if (p->modelShown) Render(p);
            }
        }
        return 0;
    case kCommand: {
        Command *c = reinterpret_cast<Command *>(lParam);
        if (p) Handle(p, c);
        delete c;
        return 0;
    }
    case kSync:
        SetEvent(reinterpret_cast<HANDLE>(lParam));  // everything posted before is done
        return 0;
    case kImagesRead:
        if (p && p->visible && (p->modelShown || p->noticeAlone)) Render(p);  // an image came, or changed
        return 0;
    case kSavePng:
        break;
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
        if (p && p->visible) Render(p);  // another scale or theme
        break;
    case WM_CLOSE:
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

// What drawing made: the render target, the formats, the images, the factories, the bitmap.
void ReleaseDrawing(AioPanel *p) {
    SafeRelease(p->target);
    for (IDWriteTextFormat **format : {&p->textFormat, &p->labelFormat, &p->commentFormat, &p->footerFormat, &p->statusFormat,
                                       &p->iconFormat, &p->emojiFormat}) {
        SafeRelease(*format);
    }
    if (p->images) {
        // Its thread ends once a read under way is done (it keeps the loader till then); it tells no window any more.
        std::lock_guard<std::mutex> lock(p->images->lock);
        p->images->stopping = true;
        p->images->notify = nullptr;
        p->images->wake.notify_all();
    }
    p->images.reset();
    SafeRelease(p->wic);
    SafeRelease(p->dwrite);
    SafeRelease(p->d2d);
    if (p->bitmap) {
        SelectObject(p->memoryDC, p->oldBitmap);
        DeleteObject(p->bitmap);
        p->bitmap = nullptr;
    }
    if (p->memoryDC) DeleteDC(p->memoryDC);
    p->memoryDC = nullptr;
}

DWORD WINAPI ThreadMain(void *arg) {
    AioPanel *p = static_cast<AioPanel *>(arg);
    g_panel = p;
    // Per monitor (v2) for this thread's windows, whatever the process's default.
    SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), nullptr, reinterpret_cast<void **>(&p->d2d));
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(&p->dwrite));
    WNDCLASSEXW wc = {sizeof wc};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    RegisterClassExW(&wc);
    if (p->d2d && p->dwrite) {
        p->hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClassName,
                                  L"AllInOneIME candidates", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, wc.hInstance, nullptr);
    }
    if (p->hwnd) {
        SetWindowLongPtrW(p->hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(p));
        p->foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, ForegroundChanged, 0, 0,
                                            WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }
    SetEvent(p->ready);
    if (!p->hwnd) {
        CoUninitialize();
        return 1;
    }
    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    if (p->foregroundHook) UnhookWinEvent(p->foregroundHook);
    ReleaseDrawing(p);
    CoUninitialize();
    return 0;
}

// Waits until the window's thread has handled everything posted before (posted messages come in order; a sent one
// would overtake them).
void Sync(AioPanel *p) {
    if (!p || !p->hwnd || GetCurrentThreadId() == p->threadId) return;
    HANDLE done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!done) return;
    if (PostMessageW(p->hwnd, kSync, 0, reinterpret_cast<LPARAM>(done))) WaitForSingleObject(done, 5000);
    CloseHandle(done);
}

void Post(AioPanel *p, Command *c) {
    if (!p || !p->hwnd || !PostMessageW(p->hwnd, kCommand, 0, reinterpret_cast<LPARAM>(c))) delete c;
}

// The last drawing as a PNG (WIC), its premultiplied pixels made straight.
bool SavePng(AioPanel *p, const wchar_t *path) {
    if (!p->bits || p->size.cx <= 0 || p->size.cy <= 0) return false;
    IWICImagingFactory *wic = nullptr;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, __uuidof(IWICImagingFactory),
                                reinterpret_cast<void **>(&wic)))) {
        return false;
    }
    bool ok = false;
    IWICBitmap *bitmap = nullptr;
    IWICFormatConverter *converter = nullptr;
    IWICStream *stream = nullptr;
    IWICBitmapEncoder *encoder = nullptr;
    IWICBitmapFrameEncode *frame = nullptr;
    UINT stride = (UINT)p->bitmapWidth * 4;
    if (SUCCEEDED(wic->CreateBitmapFromMemory((UINT)p->size.cx, (UINT)p->size.cy, GUID_WICPixelFormat32bppPBGRA, stride,
                                              stride * (UINT)p->size.cy, static_cast<BYTE *>(p->bits), &bitmap)) &&
        SUCCEEDED(wic->CreateFormatConverter(&converter)) &&
        SUCCEEDED(converter->Initialize(bitmap, GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0,
                                        WICBitmapPaletteTypeCustom)) &&
        SUCCEEDED(wic->CreateStream(&stream)) && SUCCEEDED(stream->InitializeFromFilename(path, GENERIC_WRITE)) &&
        SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) &&
        SUCCEEDED(encoder->Initialize(stream, WICBitmapEncoderNoCache)) &&
        SUCCEEDED(encoder->CreateNewFrame(&frame, nullptr)) && SUCCEEDED(frame->Initialize(nullptr)) &&
        SUCCEEDED(frame->SetSize((UINT)p->size.cx, (UINT)p->size.cy))) {
        WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
        ok = SUCCEEDED(frame->SetPixelFormat(&format)) && SUCCEEDED(frame->WriteSource(converter, nullptr)) &&
             SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit());
    }
    SafeRelease(frame);
    SafeRelease(encoder);
    SafeRelease(stream);
    SafeRelease(converter);
    SafeRelease(bitmap);
    wic->Release();
    return ok;
}

}  // namespace

extern "C" {

AioPanel *aio_panel_create(AioPanelCallbacks callbacks) {
    AioPanel *p = new AioPanel();
    p->callbacks = callbacks;
    p->ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    p->thread = CreateThread(nullptr, 0, ThreadMain, p, 0, &p->threadId);
    if (!p->thread) {
        CloseHandle(p->ready);
        delete p;
        return nullptr;
    }
    WaitForSingleObject(p->ready, 10000);
    if (!p->hwnd) {
        WaitForSingleObject(p->thread, 2000);
        CloseHandle(p->thread);
        CloseHandle(p->ready);
        delete p;
        return nullptr;
    }
    return p;
}

void aio_panel_show(AioPanel *panel, const AioPanelModel *model, const AioCaret *caret, uint64_t owner, uint32_t ownerPid,
                    int32_t ownerTrusted) {
    Command *c = new Command();
    c->op = OpShow;
    c->model = CopyModel(model);
    c->hasCaret = caret != nullptr;
    if (caret) c->caret = *caret;
    c->owner = owner;
    c->ownerPid = ownerPid;
    c->ownerTrusted = ownerTrusted != 0;
    Post(panel, c);
}

void aio_panel_hide(AioPanel *panel, uint64_t owner) {
    Command *c = new Command();
    c->op = OpHide;
    c->owner = owner;
    Post(panel, c);
}

void aio_panel_move(AioPanel *panel, uint64_t owner, const AioCaret *caret) {
    if (!caret) return;
    Command *c = new Command();
    c->op = OpMove;
    c->owner = owner;
    c->caret = *caret;
    c->hasCaret = true;
    Post(panel, c);
}

void aio_panel_notice(AioPanel *panel, const uint16_t *text, uint64_t owner, uint32_t ownerPid, int32_t ownerTrusted,
                      const AioCaret *caret, int32_t durationMs) {
    Command *c = new Command();
    c->op = OpNotice;
    c->text = Copy(text);
    c->owner = owner;
    c->ownerPid = ownerPid;
    c->ownerTrusted = ownerTrusted != 0;
    c->hasCaret = caret != nullptr;
    if (caret) c->caret = *caret;
    c->durationMs = durationMs;
    Post(panel, c);
}

void aio_panel_state(AioPanel *panel, AioPanelState *state) {
    if (!panel || !state) return;
    // Everything posted before is handled before this returns.
    Sync(panel);
    std::lock_guard<std::mutex> lock(panel->stateLock);
    *state = panel->state;
}

void *aio_panel_window(AioPanel *panel) { return panel ? panel->hwnd : nullptr; }

int32_t aio_panel_row_rect(AioPanel *panel, int32_t row, int32_t *x, int32_t *y, int32_t *width, int32_t *height) {
    if (!panel || !panel->hwnd) return 0;
    Sync(panel);
    if (row < 0 || (size_t)row >= panel->rowRects.size()) return 0;
    const RECT &r = panel->rowRects[(size_t)row];
    if (r.bottom <= r.top) return 0;  // scrolled out of sight
    if (x) *x = r.left;
    if (y) *y = r.top;
    if (width) *width = r.right - r.left;
    if (height) *height = r.bottom - r.top;
    return 1;
}

int32_t aio_panel_save_png(AioPanel *panel, const uint16_t *path) {
    if (!panel || !panel->hwnd || !path) return 0;
    Sync(panel);
    // Drawn on the window's thread, read here once it is idle: the bitmap isn't touched meanwhile.
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    bool ok = SavePng(panel, reinterpret_cast<const wchar_t *>(path));
    return ok ? 1 : 0;
}

int32_t aio_panel_render_png(const AioPanelModel *model, int32_t dpi, int32_t dark, int32_t maxHeight, const uint16_t *path,
                             AioPanelState *state) {
    if (!path) return 0;
    const HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    AioPanel panel;
    D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), nullptr, reinterpret_cast<void **>(&panel.d2d));
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(&panel.dwrite));
    bool ok = false;
    if (panel.d2d && panel.dwrite) {
        panel.dpi = dpi > 0 ? (UINT)dpi : 96;
        panel.readImagesNow = true;  // no window to draw again once they are read
        panel.model = CopyModel(model);
        if (Paint(&panel, panel.model, dark != 0, (float)std::max(maxHeight, 0))) {
            ok = SavePng(&panel, reinterpret_cast<const wchar_t *>(path));
            panel.visible = true;
            PublishState(&panel);
            if (state) *state = panel.state;
        }
    }
    ReleaseDrawing(&panel);
    if (SUCCEEDED(init)) CoUninitialize();
    return ok ? 1 : 0;
}

int32_t aio_owns_foreground(uint32_t pid, int32_t trusted) { return OwnsForeground(pid, trusted != 0) ? 1 : 0; }

int32_t aio_in_front(void *foreground, void *focus, uint32_t pid, int32_t trusted) {
    return InFront(static_cast<HWND>(foreground), static_cast<HWND>(focus), pid, trusted != 0) ? 1 : 0;
}

int32_t aio_is_frame_host_window(void *window) { return IsFrameHostWindow(static_cast<HWND>(window)) ? 1 : 0; }

int32_t aio_client_rect_on_screen(void *window, int32_t left, int32_t top, int32_t right, int32_t bottom, AioCaret *out) {
    AioCaret c = {};
    if (!ClientRectOnScreen(static_cast<HWND>(window), RECT{left, top, right, bottom}, &c)) return 0;
    if (out) *out = c;
    return 1;
}

int32_t aio_caret_bounds(uint64_t hwnd, uint32_t pid, int32_t trusted, AioCaret *bounds) {
    HWND window = reinterpret_cast<HWND>(static_cast<uintptr_t>(hwnd));
    if (window) {
        if (!IsWindow(window) || !IsProcessWindow(window, pid)) return 0;
    } else {
        window = GetForegroundWindow();
        if (!InFront(window, pid, trusted != 0)) return 0;
    }
    // Physical pixels: the engine is per-monitor aware (and this thread too, whatever the process says).
    DPI_AWARENESS_CONTEXT previous = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    RECT r;
    BOOL ok = GetWindowRect(window, &r);
    if (previous) SetThreadDpiAwarenessContext(previous);
    if (!ok) return 0;
    if (bounds) *bounds = {r.left, r.top, r.right - r.left, r.bottom - r.top, 1};
    return 1;
}

void aio_panel_destroy(AioPanel *panel) {
    if (!panel) return;
    if (panel->hwnd) PostMessageW(panel->hwnd, WM_CLOSE, 0, 0);
    if (panel->thread) {
        WaitForSingleObject(panel->thread, 5000);
        CloseHandle(panel->thread);
    }
    if (panel->ready) CloseHandle(panel->ready);
    delete panel;
}

}  // extern "C"

#endif  // _WIN32
