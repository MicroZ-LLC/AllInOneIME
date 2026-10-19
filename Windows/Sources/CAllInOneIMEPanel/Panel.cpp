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
// - It is drawn only while its owner's process owns the foreground, and hides when another process takes it
//   (EVENT_SYSTEM_FOREGROUND): a background or sandboxed client can't put it, with its text, over another app.
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
#include <wincodec.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
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

struct Row {
    std::wstring label, text, comment;
    int style = 0;
    bool pickable = true;
    bool complete = true;
};

struct Model {
    std::vector<Row> rows;
    int highlighted = -1;
    bool horizontal = false;
    int statusKind = AIO_STATUS_NONE;
    std::wstring status, input, header, footer, detail;
    bool empty() const {
        return rows.empty() && statusKind == AIO_STATUS_NONE && input.empty() && header.empty() && footer.empty() &&
               detail.empty();
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
        model.rows.push_back(std::move(row));
    }
    model.highlighted = m->highlighted;
    model.horizontal = m->horizontal != 0;
    model.statusKind = m->statusKind;
    model.status = Copy(m->status);
    model.input = Copy(m->input);
    model.header = Copy(m->header);
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
    std::wstring text;
    int durationMs = 0;
};

const UINT kCommand = WM_APP + 1;
const UINT kSync = WM_APP + 2;
const UINT kSavePng = WM_APP + 3;
const UINT_PTR kNoticeTimer = 1;
const UINT_PTR kCaretTimer = 2;
const wchar_t kClassName[] = L"AllInOneIME.CandidateWindow";

struct Colors {
    D2D1_COLOR_F background, border, text, secondary, highlight, highlightText, error;
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
                Rgb(0xFF99A4)};
    }
    return {Rgb(0xF9F9F9, 0.98f), Rgb(0xD5D5D5), Rgb(0x1A1A1A), Rgb(0x6B6B6B), Rgb(0x0067C0), Rgb(0xFFFFFF),
            Rgb(0xC42B1C)};
}

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
                      *statusFormat = nullptr;
    UINT formatsDpi = 0;

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
    bool hasCaret = false;
    AioCaret caret = {};
    bool waitingForCaret = false;
    std::wstring notice;
    bool noticeAlone = false;  // the notice is all there is
    std::vector<RECT> rowRects;
    std::vector<bool> rowPickable;
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

void MakeFormats(AioPanel *p) {
    if (p->formatsDpi == p->dpi && p->textFormat) return;
    SafeRelease(p->textFormat);
    SafeRelease(p->labelFormat);
    SafeRelease(p->commentFormat);
    SafeRelease(p->footerFormat);
    SafeRelease(p->statusFormat);
    p->textFormat = MakeFormat(p, 16.0f);
    p->labelFormat = MakeFormat(p, 12.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD);
    p->commentFormat = MakeFormat(p, 12.0f);
    p->footerFormat = MakeFormat(p, 11.5f);
    p->statusFormat = MakeFormat(p, 13.5f);
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

// Whether process `pid` is System32's ApplicationFrameHost.exe, which draws the frame of every UWP app's window.
bool IsFrameHost(DWORD pid) {
    wchar_t system[MAX_PATH];
    UINT count = GetSystemDirectoryW(system, MAX_PATH);
    if (!count || count >= MAX_PATH) return false;
    std::wstring expected = std::wstring(system, count) + L"\\ApplicationFrameHost.exe";
    return CompareStringOrdinal(ProcessImage(pid).c_str(), -1, expected.c_str(), -1, TRUE) == CSTR_EQUAL;
}

// Whether `window` is process `pid`'s: its own, or ApplicationFrameHost's frame with a window of `pid`'s inside (a UWP
// app: its CoreWindow is a child of the frame).
bool BelongsTo(HWND window, DWORD pid) {
    if (!window || !pid) return false;
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner == pid) return true;
    if (!owner || !IsFrameHost(owner)) return false;
    struct Search {
        DWORD pid;
        bool found;
    } search = {pid, false};
    EnumChildWindows(
        window,
        [](HWND child, LPARAM lParam) -> BOOL {
            Search *s = reinterpret_cast<Search *>(lParam);
            DWORD childPid = 0;
            GetWindowThreadProcessId(child, &childPid);
            if (childPid == s->pid) {
                s->found = true;
                return FALSE;
            }
            return TRUE;
        },
        reinterpret_cast<LPARAM>(&search));
    return search.found;
}

bool OwnsForeground(DWORD pid) { return BelongsTo(GetForegroundWindow(), pid); }

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

// Lays the panel out at the caret's monitor's DPI, draws it and puts it on screen: only while its owner owns the
// foreground (which may have changed since it was asked, while the panel waited for the caret).
void Render(AioPanel *p) {
    if (p->ownerPid && !OwnsForeground(p->ownerPid)) {
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
    MakeFormats(p);
    const float s = Scale(p);
    const bool dark = DarkTheme();
    const Colors colors = ThemeColors(dark);

    const float padding = std::round(6 * s), insetX = std::round(8 * s), insetY = std::round(4 * s);
    const float labelGap = std::round(8 * s), commentGap = std::round(12 * s), lineGap = std::round(4 * s);
    const float maxText = std::round(520 * s), minWidth = std::round(260 * s), maxRow = std::round(600 * s);
    const float radius = std::round(8 * s);

    // Measure.
    float labelWidth = 0;
    for (const Row &row : model.rows) labelWidth = std::max(labelWidth, Measure(p, row.label, p->labelFormat, maxText).width);
    float textHeight = Measure(p, L"Ag中", p->textFormat, maxText).height;
    float rowHeight = textHeight + 2 * insetY;
    float footerHeight = Measure(p, L"Ag中", p->footerFormat, maxText).height;
    float statusHeight = Measure(p, L"Ag中", p->statusFormat, maxText).height;

    struct Placed {
        float x, y, w, h;
        float textW, commentW;
    };
    std::vector<Placed> placed;
    float contentWidth = 0, y = padding;
    std::vector<std::pair<std::wstring, float>> topLines;  // input, header, status
    auto addLine = [&](const std::wstring &text, IDWriteTextFormat *format, float height) {
        if (text.empty()) return;
        D2D1_SIZE_F size = Measure(p, text, format, maxRow);
        contentWidth = std::max(contentWidth, size.width + 2 * insetX);
        topLines.push_back({text, y});
        y += height + lineGap;
    };
    addLine(model.input, p->textFormat, textHeight);
    addLine(model.header, p->statusFormat, statusHeight);
    float statusY = -1;
    if (model.statusKind != AIO_STATUS_NONE && !model.status.empty()) {
        // The status may have several lines (a hint): measured wrapped at the widest row.
        D2D1_SIZE_F size = Measure(p, model.status, p->statusFormat, maxRow);
        statusY = y;
        contentWidth = std::max(contentWidth, size.width + 2 * insetX);
        y += statusHeight + lineGap;
    }
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
            placed.push_back({x, lineY, cell, rowHeight, w, 0});
            x += cell + std::round(2 * s);
            contentWidth = std::max(contentWidth, x);
        }
        if (!model.rows.empty()) y = lineY + rowHeight + lineGap;
    } else {
        for (const Row &row : model.rows) {
            float w = Measure(p, row.text, p->textFormat, maxText).width;
            float cw = row.comment.empty() ? 0 : Measure(p, row.comment, p->commentFormat, std::round(200 * s)).width;
            float rowWidth = insetX + labelWidth + labelGap + w + (cw > 0 ? commentGap + cw : 0) + insetX;
            placed.push_back({0, y, rowWidth, rowHeight, w, cw});
            contentWidth = std::max(contentWidth, rowWidth);
            y += rowHeight;
        }
        if (!model.rows.empty()) y += lineGap;
    }
    float footerY = -1;
    if (!model.footer.empty() || !model.detail.empty()) {
        float fw = Measure(p, model.footer, p->footerFormat, maxRow).width;
        float dw = Measure(p, model.detail, p->footerFormat, maxText).width;
        contentWidth = std::max(contentWidth, insetX + fw + (dw > 0 ? commentGap + dw : 0) + insetX);
        footerY = y;
        y += footerHeight + insetY;
    }
    // A notice on its own is only as wide as it needs.
    float width = std::ceil(std::min(std::max(contentWidth, p->noticeAlone ? 0.0f : minWidth), maxRow + 2 * insetX) + 2 * padding);
    float height = std::ceil(y + padding - (footerY < 0 && !model.rows.empty() ? lineGap : 0));
    int w = (int)width, h = (int)height;
    if (!EnsureBitmap(p, w, h)) return;

    // Draw.
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
    if (!p->target) p->d2d->CreateDCRenderTarget(&props, &p->target);
    if (!p->target) return;
    RECT bind = {0, 0, w, h};
    p->target->BindDC(p->memoryDC, &bind);
    p->target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    p->target->BeginDraw();
    p->target->Clear(D2D1::ColorF(0, 0, 0, 0));
    D2D1_RECT_F outer = D2D1::RectF(0.5f, 0.5f, width - 0.5f, height - 0.5f);
    FillRounded(p, outer, radius, colors.border);
    FillRounded(p, D2D1::RectF(1.5f, 1.5f, width - 1.5f, height - 1.5f), radius - 1, colors.background);
    const float inner = width - 2 * padding;
    size_t line = 0;
    if (!model.input.empty()) {
        DrawText(p, model.input, p->textFormat, padding + insetX, topLines[line++].second, inner - 2 * insetX, textHeight, colors.text);
    }
    if (!model.header.empty()) {
        DrawText(p, model.header, p->statusFormat, padding + insetX, topLines[line++].second, inner - 2 * insetX, statusHeight,
                 colors.secondary);
    }
    if (statusY >= 0) {
        D2D1_COLOR_F color = model.statusKind == AIO_STATUS_ERROR ? colors.error : model.statusKind == AIO_STATUS_LOADING
                                                                                       ? colors.secondary
                                                                                       : colors.text;
        DrawText(p, model.status, p->statusFormat, padding + insetX, statusY, inner - 2 * insetX, statusHeight, color);
    }
    p->rowRects.clear();
    p->rowPickable.clear();
    for (size_t i = 0; i < model.rows.size(); ++i) {
        const Row &row = model.rows[i];
        const Placed &pl = placed[i];
        float x = padding + pl.x, top = pl.y;
        float rowW = model.horizontal ? pl.w : inner;
        bool lit = (int)i == model.highlighted;
        if (lit) FillRounded(p, D2D1::RectF(x, top, x + rowW, top + pl.h), std::round(5 * s), colors.highlight);
        D2D1_COLOR_F textColor = lit ? colors.highlightText
                                     : (row.style == 1 || !row.complete) ? colors.secondary : colors.text;
        D2D1_COLOR_F dim = lit ? colors.highlightText : colors.secondary;
        float lw = model.horizontal ? Measure(p, row.label, p->labelFormat, maxText).width : labelWidth;
        float labelY = top + insetY + (textHeight - Measure(p, L"0", p->labelFormat, maxText).height) / 2;
        DrawText(p, row.label, p->labelFormat, x + insetX, labelY, lw + 1, textHeight, dim);
        float tx = x + insetX + lw + (model.horizontal ? std::round(4 * s) : labelGap);
        float textRoom = model.horizontal ? pl.textW + 1 : std::min(pl.textW + 1, x + rowW - insetX - tx);
        DrawText(p, row.text, p->textFormat, tx, top + insetY, textRoom, textHeight, textColor);
        if (!model.horizontal && pl.commentW > 0) {
            float cx = x + rowW - insetX - pl.commentW;
            cx = std::max(cx, tx + pl.textW + commentGap);
            float cy = top + insetY + (textHeight - Measure(p, L"Ag", p->commentFormat, maxText).height) / 2;
            DrawText(p, row.comment, p->commentFormat, cx, cy, x + rowW - insetX - cx + 1, textHeight, dim);
        }
        RECT r = {(LONG)x, (LONG)top, (LONG)(x + rowW), (LONG)(top + pl.h)};
        p->rowRects.push_back(r);
        p->rowPickable.push_back(row.pickable);
    }
    if (footerY >= 0) {
        float dw = Measure(p, model.detail, p->footerFormat, maxText).width;
        DrawText(p, model.footer, p->footerFormat, padding + insetX, footerY, inner - 2 * insetX - (dw > 0 ? dw + commentGap : 0),
                 footerHeight, colors.secondary);
        if (dw > 0) {
            DrawText(p, model.detail, p->footerFormat, width - padding - insetX - dw - 1, footerY, dw + 1, footerHeight,
                     p->notice.empty() ? colors.secondary : colors.text);
        }
    }
    HRESULT hr = p->target->EndDraw();
    if (hr == D2DERR_RECREATE_TARGET) SafeRelease(p->target);

    // Place it: the first row's text under the caret, below the caret line, or above it when there is no room; inside
    // the monitor's work area.
    float textInset = padding + insetX + (model.horizontal ? 0 : labelWidth + labelGap);
    int x = p->caret.x - (int)textInset;
    int top = p->caret.y + p->caret.height + (int)std::round(4 * s);
    if (top + h > work.bottom) top = p->caret.y - h - (int)std::round(4 * s);
    x = std::max<int>(work.left, std::min<int>(x, work.right - w));
    top = std::max<int>(work.top, std::min<int>(top, work.bottom - h));
    p->position = {x, top};
    p->size = {w, h};

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
        if (c->ownerPid && !OwnsForeground(c->ownerPid)) {
            if (c->owner == p->owner) {
                p->model = Model();
                HideWindow(p);
            }
            break;
        }
        bool newOwner = c->owner != p->owner;
        p->owner = c->owner;
        p->ownerPid = c->ownerPid;
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
        if (c->ownerPid && !OwnsForeground(c->ownerPid)) break;
        if (p->modelShown && p->visible && c->owner != p->owner) break;
        p->notice = c->text;
        SetTimer(p->hwnd, kNoticeTimer, (UINT)std::max(c->durationMs, 300), nullptr);
        if (p->modelShown && p->visible && c->owner == p->owner) {
            Render(p);
        } else {
            p->owner = c->owner;
            p->ownerPid = c->ownerPid;
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
    if (pid == GetCurrentProcessId() || (p->ownerPid && BelongsTo(hwnd, p->ownerPid))) return;
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
    SafeRelease(p->target);
    SafeRelease(p->textFormat);
    SafeRelease(p->labelFormat);
    SafeRelease(p->commentFormat);
    SafeRelease(p->footerFormat);
    SafeRelease(p->statusFormat);
    SafeRelease(p->dwrite);
    SafeRelease(p->d2d);
    if (p->bitmap) {
        SelectObject(p->memoryDC, p->oldBitmap);
        DeleteObject(p->bitmap);
    }
    if (p->memoryDC) DeleteDC(p->memoryDC);
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

void aio_panel_show(AioPanel *panel, const AioPanelModel *model, const AioCaret *caret, uint64_t owner, uint32_t ownerPid) {
    Command *c = new Command();
    c->op = OpShow;
    c->model = CopyModel(model);
    c->hasCaret = caret != nullptr;
    if (caret) c->caret = *caret;
    c->owner = owner;
    c->ownerPid = ownerPid;
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

void aio_panel_notice(AioPanel *panel, const uint16_t *text, uint64_t owner, uint32_t ownerPid, const AioCaret *caret,
                      int32_t durationMs) {
    Command *c = new Command();
    c->op = OpNotice;
    c->text = Copy(text);
    c->owner = owner;
    c->ownerPid = ownerPid;
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

int32_t aio_owns_foreground(uint32_t pid) { return OwnsForeground(pid) ? 1 : 0; }

int32_t aio_client_rect_on_screen(void *window, int32_t left, int32_t top, int32_t right, int32_t bottom, AioCaret *out) {
    AioCaret c = {};
    if (!ClientRectOnScreen(static_cast<HWND>(window), RECT{left, top, right, bottom}, &c)) return 0;
    if (out) *out = c;
    return 1;
}

int32_t aio_caret_bounds(uint64_t hwnd, uint32_t pid, AioCaret *bounds) {
    HWND window = reinterpret_cast<HWND>(static_cast<uintptr_t>(hwnd));
    if (window) {
        DWORD owner = 0;
        if (!IsWindow(window) || !GetWindowThreadProcessId(window, &owner) || owner != pid) return 0;
    } else {
        window = GetForegroundWindow();
        if (!BelongsTo(window, pid)) return 0;
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
