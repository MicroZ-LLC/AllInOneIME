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

/// One row: its number, its text and a comment after it (a language, "original"...).
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
} AioPanelRow;

/// The status line's kind.
enum { AIO_STATUS_NONE = 0, AIO_STATUS_HINT = 1, AIO_STATUS_LOADING = 2, AIO_STATUS_ERROR = 3 };

typedef struct AioPanelModel {
    const AioPanelRow *rows;
    int32_t rowCount;
    /// -1: none.
    int32_t highlighted;
    /// The rows side by side (pinyin candidates).
    int32_t horizontal;
    int32_t statusKind;
    const uint16_t *status;
    /// A line of input above the rows (a command written on the selection, a refine instruction).
    const uint16_t *input;
    /// A line above the rows: what the panel works on.
    const uint16_t *header;
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
} AioPanelState;

/// Starts the window's thread and creates the window there (hidden). Nil if it couldn't (no desktop, no Direct2D).
AioPanel *aio_panel_create(AioPanelCallbacks callbacks);
/// Shows `model` for `owner` (drawn again if it is up), at `caret` if given, else where the last caret was. `ownerPid`
/// is the owner's process: the panel is drawn only while it owns the foreground (`aio_owns_foreground`), and hides when
/// another process takes it. 0: no process (tests).
void aio_panel_show(AioPanel *panel, const AioPanelModel *model, const AioCaret *caret, uint64_t owner, uint32_t ownerPid);
/// Hides the panel if `owner`'s is up (0: whosever it is).
void aio_panel_hide(AioPanel *panel, uint64_t owner);
/// The caret moved: the panel follows if it is `owner`'s.
void aio_panel_move(AioPanel *panel, uint64_t owner, const AioCaret *caret);
/// A notice for `durationMs`: beside the footer if `owner`'s panel is up, else on its own at `caret` (nil: the last
/// caret, else where the foreground window's caret is). Only while `ownerPid` owns the foreground, and never over
/// another owner's panel.
void aio_panel_notice(AioPanel *panel, const uint16_t *text, uint64_t owner, uint32_t ownerPid, const AioCaret *caret,
                      int32_t durationMs);
/// Waits until the window's thread has done what was asked before, then reads its state.
void aio_panel_state(AioPanel *panel, AioPanelState *state);
/// The window (an HWND), for tests.
void *aio_panel_window(AioPanel *panel);
/// Where row `row` was drawn last, in the window's own pixels. 0 if there is no such row.
int32_t aio_panel_row_rect(AioPanel *panel, int32_t row, int32_t *x, int32_t *y, int32_t *width, int32_t *height);
/// Writes what was drawn last to a PNG file. 0 if it couldn't.
int32_t aio_panel_save_png(AioPanel *panel, const uint16_t *path);
/// Closes the window and ends its thread.
void aio_panel_destroy(AioPanel *panel);

/// Whether the process `pid` owns the foreground window: the window is its own, or, for a UWP app, it is
/// ApplicationFrameHost's frame around a window of the app's.
int32_t aio_owns_foreground(uint32_t pid);
/// Where a caret that the process `pid` reports in `hwnd` may be (§6 `caret`): that window's rectangle, in physical
/// screen pixels, if the window is the process's; with no window (0), the foreground window's, if the process owns it
/// (`aio_owns_foreground`). 0 if neither: the report isn't the process's to make.
int32_t aio_caret_bounds(uint64_t hwnd, uint32_t pid, AioCaret *bounds);
/// A rectangle in `window`'s client coordinates (its own pixels: logical ones for an app that isn't per-monitor aware)
/// in physical screen pixels: how the panel places itself at a system caret when the DLL hasn't reported one. 0 if it
/// can't be mapped.
int32_t aio_client_rect_on_screen(void *window, int32_t left, int32_t top, int32_t right, int32_t bottom, AioCaret *out);

#ifdef __cplusplus
}
#endif

#endif
