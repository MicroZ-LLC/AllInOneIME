// The engine's candidate window (M6): a Win32 layered, no-activate, topmost tool window, drawn with Direct2D and
// DirectWrite, on a thread of its own with its own message loop. The engine hands it what to show (a flat copy of its
// PanelModel) and the caret rectangle the DLL reported (§6), from any thread; a click on a row or the wheel comes back
// through the callbacks, on the window's thread.
//
// A plain C interface, so Swift imports it as it is. Strings are UTF-16 (Windows' wchar_t), NUL-terminated, nullable.
#ifndef ALLINONEIME_PANEL_H
#define ALLINONEIME_PANEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AioPanel AioPanel;

/// A row's icon (the core's IconToken): a glyph drawn white on a rounded square of `color`, or an emoji or an image in
/// the square's place.
enum { AIO_ICON_NONE = 0, AIO_ICON_GLYPH = 1, AIO_ICON_EMOJI = 2, AIO_ICON_IMAGE = 3 };

typedef struct AioPanelIcon {
    int32_t kind;
    /// AIO_ICON_GLYPH: the glyph, a character of Segoe Fluent Icons (Segoe MDL2 Assets on Windows 10); AIO_ICON_EMOJI:
    /// the emoji; AIO_ICON_IMAGE: the image file's path (read with WIC).
    const uint16_t *text;
    /// The glyph drawn on the square instead where the emoji or the image can't be.
    const uint16_t *fallback;
    /// The square's color, 0xRRGGBB.
    uint32_t color;
} AioPanelIcon;

/// One row: its number, its icon, its text and a comment after it (a language, "original"...).
typedef struct AioPanelRow {
    const uint16_t *label;
    const uint16_t *text;
    const uint16_t *comment;
    /// 0: a candidate, 1: the original (dimmed), 2: a result.
    int32_t style;
    /// A click picks it.
    int32_t pickable;
    /// Still streaming in: dimmed.
    int32_t complete;
    AioPanelIcon icon;
} AioPanelRow;

/// The status line's kind. AIO_STATUS_LIST: a hint with a list under it (`statusItems`, a line each).
enum { AIO_STATUS_NONE = 0, AIO_STATUS_HINT = 1, AIO_STATUS_LOADING = 2, AIO_STATUS_ERROR = 3, AIO_STATUS_LIST = 4 };

/// The core's PanelModel, flat. From top to bottom: where a conversation can go on (the hand-off: its title, then a chip
/// per destination), the line of input, the header's lines, the rows, the status, and the footer with the detail on its
/// right.
typedef struct AioPanelModel {
    const AioPanelRow *rows;
    int32_t rowCount;
    /// -1: none.
    int32_t highlighted;
    /// The rows side by side (pinyin candidates).
    int32_t horizontal;
    /// The rows are a conversation (@question): their text wraps, and the panel is no taller than half the monitor,
    /// scrolled to the last row (or to the highlighted one when it is above).
    int32_t transcript;
    int32_t statusKind;
    const uint16_t *status;
    const uint16_t *const *statusItems;
    int32_t statusItemCount;
    /// The line of input (a command written on the selection, a refine instruction, the next question): nil for none.
    /// Its prompt is drawn dimmed before its text; the caret is at `inputCaret` in the text, in UTF-16 units (-1: none,
    /// the text only shown).
    const uint16_t *inputPrompt;
    const uint16_t *inputText;
    int32_t inputCaret;
    /// The lines above the rows, each its own: what the panel works on, what a draft has attached.
    const uint16_t *const *headerLines;
    int32_t headerCount;
    /// Where a conversation can go on: a title, and a chip per destination, its shortcut and its name.
    const uint16_t *handoffTitle;
    const uint16_t *const *handoffShortcuts;
    const uint16_t *const *handoffNames;
    int32_t handoffCount;
    const uint16_t *footer;
    /// On the footer's right: the page, a request's time.
    const uint16_t *detail;
} AioPanelModel;

/// A caret rectangle in physical screen pixels (§6 `caret`). `exact` 0: the field's window, not its caret.
typedef struct AioCaret {
    int32_t x, y, width, height;
    int32_t exact;
} AioCaret;

typedef struct AioPanelCallbacks {
    void *context;
    /// A pickable row clicked, in the panel `owner` showed.
    void (*click)(void *context, uint64_t owner, int32_t row);
    /// The wheel over the panel: rows to move, down positive.
    void (*scroll)(void *context, uint64_t owner, int32_t steps);
} AioPanelCallbacks;

/// What the window is doing, for tests and logs.
typedef struct AioPanelState {
    int32_t visible;
    int32_t x, y, width, height;
    uint64_t owner;
    int32_t rows;
    int32_t highlighted;
    /// The DPI it was last drawn at (that of the monitor the caret is on).
    int32_t dpi;
    /// How many times it was drawn.
    int32_t draws;
    /// A notice is up (beside the footer or on its own).
    int32_t notice;
    /// Where the input's caret was drawn, in the window's pixels (its top); -1: none.
    int32_t caretX, caretY;
    /// How far a conversation's rows are scrolled (pixels): its first rows out of sight above.
    int32_t scrolled;
} AioPanelState;

/// Starts the window's thread and creates the window there (hidden). Nil if it couldn't (no desktop, no Direct2D).
AioPanel *aio_panel_create(AioPanelCallbacks callbacks);
/// Shows `model` for `owner` (drawn again if it is up), at `caret` if given, else where the last caret was. `ownerPid`
/// is the owner's process: the panel is drawn only while it owns the foreground (`aio_owns_foreground`, with
/// `ownerTrusted`: whether that client is trusted, §8), and hides when another process takes it. 0: no process (tests).
void aio_panel_show(AioPanel *panel, const AioPanelModel *model, const AioCaret *caret, uint64_t owner, uint32_t ownerPid,
                    int32_t ownerTrusted);
/// Hides the panel if `owner`'s is up (0: whosever it is).
void aio_panel_hide(AioPanel *panel, uint64_t owner);
/// The caret moved: the panel follows if it is `owner`'s.
void aio_panel_move(AioPanel *panel, uint64_t owner, const AioCaret *caret);
/// A notice for `durationMs`: beside the footer if `owner`'s panel is up, else on its own at `caret` (nil: the last
/// caret, else where the foreground window's caret is). Only while `ownerPid` owns the foreground (`ownerTrusted` as
/// for `aio_panel_show`), and never over another owner's panel.
void aio_panel_notice(AioPanel *panel, const uint16_t *text, uint64_t owner, uint32_t ownerPid, int32_t ownerTrusted,
                      const AioCaret *caret, int32_t durationMs);
/// Waits until the window's thread has done what was asked before, then reads its state.
void aio_panel_state(AioPanel *panel, AioPanelState *state);
/// The window (an HWND), for tests.
void *aio_panel_window(AioPanel *panel);
/// Where row `row` was drawn last, in the window's own pixels (what is shown of it). 0 if there is no such row, or it is
/// a conversation's row scrolled out of sight.
int32_t aio_panel_row_rect(AioPanel *panel, int32_t row, int32_t *x, int32_t *y, int32_t *width, int32_t *height);
/// Writes what was drawn last to a PNG file. 0 if it couldn't.
int32_t aio_panel_save_png(AioPanel *panel, const uint16_t *path);
/// Draws `model` as the window would at `dpi`, in the dark or light theme, no taller than `maxHeight` pixels for a
/// conversation (0: no limit), into a PNG file, without a window (any thread, any session); `state`, if given, says
/// what was drawn (its size, the input's caret, the scroll). 0 if it couldn't.
int32_t aio_panel_render_png(const AioPanelModel *model, int32_t dpi, int32_t dark, int32_t maxHeight, const uint16_t *path,
                             AioPanelState *state);
/// Closes the window and ends its thread.
void aio_panel_destroy(AioPanel *panel);

/// Whether the process `pid` is the app in front (`aio_in_front` with the foreground window and its thread's focus).
int32_t aio_owns_foreground(uint32_t pid, int32_t trusted);
/// Whether the process `pid` is the app in front when `foreground` is the foreground window and `focus` (nullable) the
/// focus window of its thread: the foreground window is the process's (a classic console's window is its conhost's,
/// though the window says it is its client's), or the focus is in a window of the process's (a WebView2's, in its
/// host's window), or a window inside the foreground window is: in ApplicationFrameHost's frame (a UWP app's), or, for
/// a `trusted` client (medium integrity or higher, no AppContainer, §8), anywhere.
int32_t aio_in_front(void *foreground, void *focus, uint32_t pid, int32_t trusted);
/// Where a caret that the process `pid` reports in `hwnd` may be (§6 `caret`): that window's rectangle, in physical
/// screen pixels, if the window is the process's (a classic console's, its conhost's); with no window (0), the
/// foreground window's, if the process is the app in front (`aio_owns_foreground`, `trusted` as there). 0 if neither:
/// the report isn't the process's to make.
int32_t aio_caret_bounds(uint64_t hwnd, uint32_t pid, int32_t trusted, AioCaret *bounds);
/// A rectangle in `window`'s client coordinates (its own pixels: logical ones for an app that isn't per-monitor aware)
/// in physical screen pixels: how the panel places itself at a system caret when the DLL hasn't reported one. 0 if it
/// can't be mapped.
int32_t aio_client_rect_on_screen(void *window, int32_t left, int32_t top, int32_t right, int32_t bottom, AioCaret *out);

#ifdef __cplusplus
}
#endif

#endif
