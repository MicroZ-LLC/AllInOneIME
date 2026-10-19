// A minimal in-memory ITextStoreACP for tiptest: a backing string, one selection, synchronous locks, a fixed caret
// rect, and an input scope of IS_DEFAULT. Enough for a TIP to open a session, compose, and commit.
//
// It also offers ExternalReplace, which tiptest uses to emulate the application inserting a passed-through key, and
// notifies the TSF sink so ACP positions stay consistent.

#pragma once

#include <windows.h>
#include <msctf.h>
#include <textstor.h>
#include <inputscope.h>

#include <string>

namespace aio::test {

class InputScopeDefault;

class TextStore final : public ITextStoreACP {
public:
    // `scope` is the single input scope the store reports (IS_DEFAULT for a normal field, IS_PASSWORD for a secure one).
    explicit TextStore(HWND wnd, InputScope scope = IS_DEFAULT);

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITextStoreACP
    STDMETHODIMP AdviseSink(REFIID riid, IUnknown* punk, DWORD mask) override;
    STDMETHODIMP UnadviseSink(IUnknown* punk) override;
    STDMETHODIMP RequestLock(DWORD lockFlags, HRESULT* sessionResult) override;
    STDMETHODIMP GetStatus(TS_STATUS* status) override;
    STDMETHODIMP QueryInsert(LONG start, LONG end, ULONG cch, LONG* resStart, LONG* resEnd) override;
    STDMETHODIMP GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP* sel, ULONG* fetched) override;
    STDMETHODIMP SetSelection(ULONG count, const TS_SELECTION_ACP* sel) override;
    STDMETHODIMP GetText(LONG start, LONG end, WCHAR* plain, ULONG cchReq, ULONG* cchOut, TS_RUNINFO* runs,
                         ULONG runReq, ULONG* runOut, LONG* next) override;
    STDMETHODIMP SetText(DWORD flags, LONG start, LONG end, const WCHAR* text, ULONG cch, TS_TEXTCHANGE* change) override;
    STDMETHODIMP GetFormattedText(LONG start, LONG end, IDataObject** obj) override;
    STDMETHODIMP GetEmbedded(LONG pos, REFGUID service, REFIID riid, IUnknown** obj) override;
    STDMETHODIMP QueryInsertEmbedded(const GUID* service, const FORMATETC* fmt, BOOL* insertable) override;
    STDMETHODIMP InsertEmbedded(DWORD flags, LONG start, LONG end, IDataObject* obj, TS_TEXTCHANGE* change) override;
    STDMETHODIMP InsertTextAtSelection(DWORD flags, const WCHAR* text, ULONG cch, LONG* start, LONG* end,
                                       TS_TEXTCHANGE* change) override;
    STDMETHODIMP InsertEmbeddedAtSelection(DWORD flags, IDataObject* obj, LONG* start, LONG* end,
                                           TS_TEXTCHANGE* change) override;
    STDMETHODIMP RequestSupportedAttrs(DWORD flags, ULONG count, const TS_ATTRID* filter) override;
    STDMETHODIMP RequestAttrsAtPosition(LONG pos, ULONG count, const TS_ATTRID* filter, DWORD flags) override;
    STDMETHODIMP RequestAttrsTransitioningAtPosition(LONG pos, ULONG count, const TS_ATTRID* filter, DWORD flags) override;
    STDMETHODIMP FindNextAttrTransition(LONG start, LONG halt, ULONG count, const TS_ATTRID* filter, DWORD flags,
                                        LONG* next, BOOL* found, LONG* foundOffset) override;
    STDMETHODIMP RetrieveRequestedAttrs(ULONG count, TS_ATTRVAL* vals, ULONG* fetched) override;
    STDMETHODIMP GetEndACP(LONG* acp) override;
    STDMETHODIMP GetActiveView(TsViewCookie* view) override;
    STDMETHODIMP GetACPFromPoint(TsViewCookie view, const POINT* pt, DWORD flags, LONG* acp) override;
    STDMETHODIMP GetTextExt(TsViewCookie view, LONG start, LONG end, RECT* rect, BOOL* clipped) override;
    STDMETHODIMP GetScreenExt(TsViewCookie view, RECT* rect) override;
    STDMETHODIMP GetWnd(TsViewCookie view, HWND* wnd) override;

    // For the test.
    const std::wstring& Text() const { return text_; }
    LONG SelStart() const { return selStart_; }
    LONG SelEnd() const { return selEnd_; }
    // Emulates the app replacing [start,end) with `text` (a passed-through key the TIP didn't handle), notifying TSF.
    void ExternalReplace(LONG start, LONG end, const std::wstring& text);
    // The field's input scope changes (the app made it a URL field, say): TSF is told the attribute changed.
    void SetInputScope(InputScope scope);

private:
    ~TextStore();
    bool Locked() const { return lockType_ != 0; }
    bool WriteLocked() const { return (lockType_ & TS_LF_READWRITE) == TS_LF_READWRITE; }

    LONG refs_ = 1;
    HWND wnd_ = nullptr;
    std::wstring text_;
    LONG selStart_ = 0;
    LONG selEnd_ = 0;
    ITextStoreACPSink* sink_ = nullptr;
    DWORD sinkMask_ = 0;
    DWORD lockType_ = 0;
    DWORD queuedLock_ = 0; // an asynchronous request made while locked
    bool inputScopeRequested_ = false;
    InputScopeDefault* inputScope_ = nullptr;
};

} // namespace aio::test
