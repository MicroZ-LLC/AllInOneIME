#include "TextStore.h"

#include <olectl.h>

#include <algorithm>
#include <cstdio>

namespace aio::test {

// Reports a single input scope (IS_DEFAULT for a normal field, IS_PASSWORD for a secure one), so the DLL sees it at
// the selection (§4).
class InputScopeDefault final : public ITfInputScope {
public:
    explicit InputScopeDefault(InputScope scope) : scope_(scope) {}
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfInputScope)) {
            *ppv = static_cast<ITfInputScope*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return (ULONG)InterlockedIncrement(&refs_); }
    STDMETHODIMP_(ULONG) Release() override {
        LONG n = InterlockedDecrement(&refs_);
        if (!n) delete this;
        return (ULONG)n;
    }
    STDMETHODIMP GetInputScopes(InputScope** scopes, UINT* count) override {
        *scopes = (InputScope*)CoTaskMemAlloc(sizeof(InputScope));
        if (!*scopes) return E_OUTOFMEMORY;
        (*scopes)[0] = scope_;
        *count = 1;
        return S_OK;
    }
    STDMETHODIMP GetPhrase(BSTR**, UINT* count) override { *count = 0; return S_FALSE; }
    STDMETHODIMP GetRegularExpression(BSTR* re) override { *re = nullptr; return S_FALSE; }
    STDMETHODIMP GetSRGS(BSTR* srgs) override { *srgs = nullptr; return S_FALSE; }
    STDMETHODIMP GetXML(BSTR* xml) override { *xml = nullptr; return S_FALSE; }

    void Set(InputScope scope) { scope_ = scope; }

private:
    LONG refs_ = 1;
    InputScope scope_;
};

TextStore::TextStore(HWND wnd, InputScope scope) : wnd_(wnd) {
    inputScope_ = new InputScopeDefault(scope);
}

TextStore::~TextStore() {
    if (sink_) sink_->Release();
    if (inputScope_) inputScope_->Release();
}

STDMETHODIMP TextStore::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITextStoreACP)) {
        *ppv = static_cast<ITextStoreACP*>(this);
        AddRef();
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) TextStore::AddRef() { return (ULONG)InterlockedIncrement(&refs_); }
STDMETHODIMP_(ULONG) TextStore::Release() {
    LONG n = InterlockedDecrement(&refs_);
    if (!n) delete this;
    return (ULONG)n;
}

STDMETHODIMP TextStore::AdviseSink(REFIID riid, IUnknown* punk, DWORD mask) {
    if (!IsEqualIID(riid, IID_ITextStoreACPSink)) return E_INVALIDARG;
    if (sink_) {
        IUnknown* existing = nullptr;
        sink_->QueryInterface(IID_IUnknown, (void**)&existing);
        IUnknown* incoming = nullptr;
        punk->QueryInterface(IID_IUnknown, (void**)&incoming);
        bool same = existing == incoming;
        if (existing) existing->Release();
        if (incoming) incoming->Release();
        if (same) {
            sinkMask_ = mask;
            return S_OK;
        }
        return CONNECT_E_ADVISELIMIT;
    }
    HRESULT hr = punk->QueryInterface(IID_ITextStoreACPSink, (void**)&sink_);
    if (FAILED(hr)) return hr;
    sinkMask_ = mask;
    return S_OK;
}

STDMETHODIMP TextStore::UnadviseSink(IUnknown* punk) {
    (void)punk;
    if (sink_) {
        sink_->Release();
        sink_ = nullptr;
    }
    return S_OK;
}

STDMETHODIMP TextStore::RequestLock(DWORD lockFlags, HRESULT* sessionResult) {
    if (!sink_ || !sessionResult) return E_UNEXPECTED;
    *sessionResult = E_FAIL;
    if (Locked()) {
        // ITextStoreACP::RequestLock: a synchronous request can't be granted while locked; an asynchronous one (or a
        // read-to-write upgrade) is queued and granted when the current lock is released.
        if (lockFlags & TS_LF_SYNC) {
            *sessionResult = TS_E_SYNCHRONOUS;
            return S_OK;
        }
        queuedLock_ = (queuedLock_ & TS_LF_READWRITE) | (lockFlags & TS_LF_READWRITE);
        *sessionResult = TS_S_ASYNC;
        return S_OK;
    }
    lockType_ = lockFlags & TS_LF_READWRITE;
    *sessionResult = sink_->OnLockGranted(lockType_);
    lockType_ = 0;
    while (queuedLock_ && sink_) {
        const DWORD queued = queuedLock_;
        queuedLock_ = 0;
        lockType_ = queued;
        sink_->OnLockGranted(queued);
        lockType_ = 0;
    }
    return S_OK;
}

STDMETHODIMP TextStore::GetStatus(TS_STATUS* status) {
    if (!status) return E_INVALIDARG;
    status->dwDynamicFlags = 0; // not read-only
    status->dwStaticFlags = TS_SS_NOHIDDENTEXT;
    return S_OK;
}

STDMETHODIMP TextStore::QueryInsert(LONG start, LONG end, ULONG, LONG* resStart, LONG* resEnd) {
    const LONG len = (LONG)text_.size();
    if (start < 0 || end > len || start > end) return E_INVALIDARG;
    if (resStart) *resStart = start;
    if (resEnd) *resEnd = end;
    return S_OK;
}

STDMETHODIMP TextStore::GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP* sel, ULONG* fetched) {
    if (fetched) *fetched = 0;
    if (!Locked()) return TS_E_NOLOCK;
    if (count == 0) return S_OK;
    if (index != 0 && index != TS_DEFAULT_SELECTION) return E_INVALIDARG;
    sel[0].acpStart = selStart_;
    sel[0].acpEnd = selEnd_;
    sel[0].style.ase = TS_AE_END;
    sel[0].style.fInterimChar = FALSE;
    if (fetched) *fetched = 1;
    return S_OK;
}

STDMETHODIMP TextStore::SetSelection(ULONG count, const TS_SELECTION_ACP* sel) {
    if (!WriteLocked()) return TS_E_NOLOCK;
    if (count != 1 || !sel) return E_INVALIDARG;
    selStart_ = sel[0].acpStart;
    selEnd_ = sel[0].acpEnd;
    return S_OK;
}

STDMETHODIMP TextStore::GetText(LONG start, LONG end, WCHAR* plain, ULONG cchReq, ULONG* cchOut, TS_RUNINFO* runs,
                                ULONG runReq, ULONG* runOut, LONG* next) {
    if (!Locked()) return TS_E_NOLOCK;
    const LONG len = (LONG)text_.size();
    if (end < 0) end = len;
    if (start < 0 || start > len || end > len || start > end) return TS_E_INVALIDPOS;
    const ULONG avail = (ULONG)(end - start);
    const ULONG copy = plain ? std::min(avail, cchReq) : 0;
    if (plain && copy) memcpy(plain, text_.data() + start, copy * sizeof(WCHAR));
    if (cchOut) *cchOut = copy;
    if (runs && runReq) {
        runs[0].uCount = copy;
        runs[0].type = TS_RT_PLAIN;
        if (runOut) *runOut = 1;
    } else if (runOut) {
        *runOut = 0;
    }
    if (next) *next = start + (LONG)copy;
    return S_OK;
}

STDMETHODIMP TextStore::SetText(DWORD, LONG start, LONG end, const WCHAR* text, ULONG cch, TS_TEXTCHANGE* change) {
    if (!WriteLocked()) return TS_E_NOLOCK;
    const LONG len = (LONG)text_.size();
    if (end < 0) end = len;
    if (start < 0 || start > len || end > len || start > end) return TS_E_INVALIDPOS;
    text_.replace(start, end - start, text ? std::wstring(text, cch) : std::wstring());
    const LONG newEnd = start + (LONG)cch;
    selStart_ = selEnd_ = newEnd;
    if (change) {
        change->acpStart = start;
        change->acpOldEnd = end;
        change->acpNewEnd = newEnd;
    }
    return S_OK;
}

STDMETHODIMP TextStore::InsertTextAtSelection(DWORD flags, const WCHAR* text, ULONG cch, LONG* start, LONG* end,
                                              TS_TEXTCHANGE* change) {
    if (!WriteLocked() && !(flags & TS_IAS_QUERYONLY)) return TS_E_NOLOCK;
    if (!Locked()) return TS_E_NOLOCK;
    const LONG s = selStart_, e = selEnd_;
    if (flags & TS_IAS_QUERYONLY) {
        if (start) *start = s;
        if (end) *end = e;
        return S_OK;
    }
    text_.replace(s, e - s, text ? std::wstring(text, cch) : std::wstring());
    const LONG newEnd = s + (LONG)cch;
    selStart_ = selEnd_ = newEnd;
    if (start) *start = s;
    if (end) *end = newEnd;
    if (change) {
        change->acpStart = s;
        change->acpOldEnd = e;
        change->acpNewEnd = newEnd;
    }
    return S_OK;
}

STDMETHODIMP TextStore::RequestSupportedAttrs(DWORD, ULONG count, const TS_ATTRID* filter) {
    for (ULONG i = 0; i < count; ++i) {
        if (IsEqualGUID(filter[i], GUID_PROP_INPUTSCOPE)) inputScopeRequested_ = true;
    }
    return S_OK;
}

STDMETHODIMP TextStore::RequestAttrsAtPosition(LONG, ULONG count, const TS_ATTRID* filter, DWORD) {
    inputScopeRequested_ = false;
    for (ULONG i = 0; i < count; ++i) {
        if (IsEqualGUID(filter[i], GUID_PROP_INPUTSCOPE)) inputScopeRequested_ = true;
    }
    return S_OK;
}

STDMETHODIMP TextStore::RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) {
    return S_OK;
}

STDMETHODIMP TextStore::RetrieveRequestedAttrs(ULONG count, TS_ATTRVAL* vals, ULONG* fetched) {
    if (fetched) *fetched = 0;
    if (inputScopeRequested_ && count >= 1) {
        vals[0].idAttr = GUID_PROP_INPUTSCOPE;
        vals[0].dwOverlapId = 0;
        VariantInit(&vals[0].varValue);
        vals[0].varValue.vt = VT_UNKNOWN;
        inputScope_->AddRef();
        vals[0].varValue.punkVal = inputScope_;
        if (fetched) *fetched = 1;
        inputScopeRequested_ = false;
    }
    return S_OK;
}

STDMETHODIMP TextStore::GetEndACP(LONG* acp) {
    if (!Locked()) return TS_E_NOLOCK;
    if (!acp) return E_INVALIDARG;
    *acp = (LONG)text_.size();
    return S_OK;
}

STDMETHODIMP TextStore::GetActiveView(TsViewCookie* view) {
    if (!view) return E_INVALIDARG;
    *view = 1;
    return S_OK;
}

STDMETHODIMP TextStore::GetTextExt(TsViewCookie, LONG, LONG, RECT* rect, BOOL* clipped) {
    if (!Locked()) return TS_E_NOLOCK;
    if (!rect) return E_INVALIDARG;
    // The fixed caret box the golden expects: [812,440,9,20] as [left,top,width,height].
    rect->left = 812;
    rect->top = 440;
    rect->right = 812 + 9;
    rect->bottom = 440 + 20;
    if (clipped) *clipped = FALSE;
    return S_OK;
}

STDMETHODIMP TextStore::GetScreenExt(TsViewCookie, RECT* rect) {
    if (!rect) return E_INVALIDARG;
    rect->left = 0;
    rect->top = 0;
    rect->right = 1920;
    rect->bottom = 1080;
    return S_OK;
}

STDMETHODIMP TextStore::GetWnd(TsViewCookie, HWND* wnd) {
    if (!wnd) return E_INVALIDARG;
    *wnd = wnd_;
    return S_OK;
}

// Unused methods.
STDMETHODIMP TextStore::GetFormattedText(LONG, LONG, IDataObject**) { return E_NOTIMPL; }
STDMETHODIMP TextStore::GetEmbedded(LONG, REFGUID, REFIID, IUnknown**) { return E_NOTIMPL; }
STDMETHODIMP TextStore::QueryInsertEmbedded(const GUID*, const FORMATETC*, BOOL* insertable) {
    if (insertable) *insertable = FALSE;
    return S_OK;
}
STDMETHODIMP TextStore::InsertEmbedded(DWORD, LONG, LONG, IDataObject*, TS_TEXTCHANGE*) { return E_NOTIMPL; }
STDMETHODIMP TextStore::InsertEmbeddedAtSelection(DWORD, IDataObject*, LONG*, LONG*, TS_TEXTCHANGE*) { return E_NOTIMPL; }
STDMETHODIMP TextStore::FindNextAttrTransition(LONG, LONG, ULONG, const TS_ATTRID*, DWORD, LONG* next, BOOL* found,
                                               LONG* foundOffset) {
    if (next) *next = 0;
    if (found) *found = FALSE;
    if (foundOffset) *foundOffset = 0;
    return S_OK;
}
STDMETHODIMP TextStore::GetACPFromPoint(TsViewCookie, const POINT*, DWORD, LONG*) { return E_NOTIMPL; }

void TextStore::ExternalReplace(LONG start, LONG end, const std::wstring& text) {
    const LONG len = (LONG)text_.size();
    if (start < 0) start = 0;
    if (end < 0 || end > len) end = len;
    if (start > end) start = end;
    text_.replace(start, end - start, text);
    const LONG newEnd = start + (LONG)text.size();
    selStart_ = selEnd_ = newEnd;
    // Notify TSF of the external change so its ACP bookkeeping stays in step.
    if (sink_ && (sinkMask_ & TS_AS_TEXT_CHANGE)) {
        TS_TEXTCHANGE change = {start, end, newEnd};
        sink_->OnTextChange(0, &change);
    }
    if (sink_ && (sinkMask_ & TS_AS_SEL_CHANGE)) sink_->OnSelectionChange();
}

void TextStore::SetInputScope(InputScope scope) {
    if (inputScope_) inputScope_->Set(scope);
    if (sink_ && (sinkMask_ & TS_AS_ATTR_CHANGE)) {
        const TS_ATTRID changed = GUID_PROP_INPUTSCOPE;
        sink_->OnAttrsChange(0, static_cast<LONG>(text_.size()), 1, &changed);
    }
}

} // namespace aio::test
