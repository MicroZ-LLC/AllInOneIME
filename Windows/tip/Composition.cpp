#include "Composition.h"

#include <algorithm>

#include "Globals.h"
#include "Log.h"

namespace aio {

namespace {

// A COM pointer that releases on scope exit.
template <class T>
struct Com {
    T* p = nullptr;
    Com() = default;
    explicit Com(T* raw) : p(raw) {}
    Com(const Com&) = delete;
    Com& operator=(const Com&) = delete;
    ~Com() {
        if (p) p->Release();
    }
    T** operator&() { return &p; }
    T* operator->() const { return p; }
    operator T*() const { return p; }
    T* Detach() {
        T* r = p;
        p = nullptr;
        return r;
    }
};

} // namespace

Composition::Composition(ITfContext* context, TfClientId clientId, const DisplayAttributeAtoms* atoms,
                         ITfCompositionSink* sink) noexcept
    : context_(context), clientId_(clientId), atoms_(atoms), sink_(sink) {
    if (context_) context_->AddRef();
}

Composition::~Composition() {
    if (terminatedRange_) terminatedRange_->Release();
    if (composition_) composition_->Release();
    if (context_) context_->Release();
}

void Composition::Terminated() noexcept {
    ForgetRange();
    shown_.clear();
    typed_.clear();
    if (composition_) {
        ITfRange* range = nullptr;
        if (SUCCEEDED(composition_->GetRange(&range)) && range) terminatedRange_ = range;
        composition_->Release();
        composition_ = nullptr;
    }
}

void Composition::ForgetRange() noexcept {
    if (terminatedRange_) {
        terminatedRange_->Release();
        terminatedRange_ = nullptr;
    }
}

HRESULT Composition::Start(TfEditCookie ec) noexcept {
    if (composition_) return S_OK;
    Com<ITfInsertAtSelection> insert;
    HRESULT hr = context_->QueryInterface(IID_ITfInsertAtSelection, reinterpret_cast<void**>(&insert));
    if (FAILED(hr)) return hr;
    Com<ITfRange> range;
    hr = insert->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0, &range);
    if (FAILED(hr)) return hr;
    Com<ITfContextComposition> contextComposition;
    hr = context_->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void**>(&contextComposition));
    if (FAILED(hr)) return hr;
    hr = contextComposition->StartComposition(ec, range, sink_, &composition_);
    if (FAILED(hr)) {
        composition_ = nullptr;
        return hr;
    }
    if (!composition_) return E_FAIL;
    return S_OK;
}

HRESULT Composition::SetSelection(TfEditCookie ec, ITfRange* start, LONG offset) noexcept {
    Com<ITfRange> caret;
    HRESULT hr = start->Clone(&caret);
    if (FAILED(hr)) return hr;
    hr = caret->Collapse(ec, TF_ANCHOR_START);
    if (FAILED(hr)) return hr;
    if (offset != 0) {
        LONG shifted = 0;
        caret->ShiftEnd(ec, offset, &shifted, nullptr);
        caret->ShiftStart(ec, offset, &shifted, nullptr);
    }
    caret->Collapse(ec, TF_ANCHOR_START);
    TF_SELECTION sel = {};
    sel.range = caret;
    sel.style.ase = TF_AE_NONE;
    sel.style.fInterimChar = FALSE;
    return context_->SetSelection(ec, 1, &sel);
}

HRESULT Composition::ClearDisplayAttributes(TfEditCookie ec) noexcept {
    if (!composition_) return S_OK;
    Com<ITfRange> range;
    HRESULT hr = composition_->GetRange(&range);
    if (FAILED(hr)) return hr;
    Com<ITfProperty> prop;
    hr = context_->GetProperty(GUID_PROP_ATTRIBUTE, &prop);
    if (FAILED(hr)) return hr;
    return prop->Clear(ec, range);
}

HRESULT Composition::MarkSegments(TfEditCookie ec, ITfRange* fullRange, const wire::CompositionOutput& output) noexcept {
    Com<ITfProperty> prop;
    HRESULT hr = context_->GetProperty(GUID_PROP_ATTRIBUTE, &prop);
    if (FAILED(hr)) return hr;
    prop->Clear(ec, fullRange);

    const LONG length = static_cast<LONG>(output.text.size());
    // Parts no segment covers are raw (§6): start by marking the whole range raw, then lay the segments over it.
    auto mark = [&](LONG from, LONG to, wire::Style style) -> HRESULT {
        from = std::clamp<LONG>(from, 0, length);
        to = std::clamp<LONG>(to, 0, length);
        if (to <= from) return S_OK;
        Com<ITfRange> segment;
        HRESULT h = fullRange->Clone(&segment);
        if (FAILED(h)) return h;
        h = segment->Collapse(ec, TF_ANCHOR_START);
        if (FAILED(h)) return h;
        LONG shifted = 0;
        segment->ShiftEnd(ec, to, &shifted, nullptr);
        segment->ShiftStart(ec, from, &shifted, nullptr);
        const TfGuidAtom atom = atoms_ ? atoms_->Atom(style) : TF_INVALID_GUIDATOM;
        if (atom == TF_INVALID_GUIDATOM) return S_OK;
        VARIANT var;
        VariantInit(&var);
        var.vt = VT_I4;
        var.lVal = atom;
        return prop->SetValue(ec, segment, &var);
    };

    HRESULT result = mark(0, length, wire::Style::raw);
    for (const auto& seg : output.segments) {
        const HRESULT h = mark(static_cast<LONG>(seg.from), static_cast<LONG>(seg.to), seg.style);
        if (FAILED(h)) result = h;
    }
    return result;
}

HRESULT Composition::SetComposition(TfEditCookie ec, const wire::CompositionOutput& output) noexcept {
    if (output.text.empty()) {
        // §6: empty text removes the text and ends the composition.
        if (!composition_) return S_OK;
        Com<ITfRange> range;
        HRESULT hr = composition_->GetRange(&range);
        if (SUCCEEDED(hr)) hr = range->SetText(ec, 0, L"", 0);
        if (SUCCEEDED(hr)) SetSelection(ec, range, 0);
        composition_->EndComposition(ec);
        composition_->Release();
        composition_ = nullptr;
        shown_.clear();
        typed_.clear();
        return hr;
    }
    ForgetRange();
    shown_ = output.text;
    typed_ = output.typed && *output.typed != output.text ? *output.typed : wire::Text();

    HRESULT hr = Start(ec);
    if (FAILED(hr)) return hr;
    Com<ITfRange> range;
    hr = composition_->GetRange(&range);
    if (FAILED(hr)) return hr;
    hr = range->SetText(ec, 0, output.text.c_str(), static_cast<LONG>(output.text.size()));
    if (FAILED(hr)) return hr;
    // GetRange's range tracks the text, but SetText may have left it collapsed at the end: re-fetch.
    Com<ITfRange> full;
    hr = composition_->GetRange(&full);
    if (FAILED(hr)) return hr;
    MarkSegments(ec, full, output);
    const LONG caret = std::clamp<LONG>(static_cast<LONG>(output.caret), 0, static_cast<LONG>(output.text.size()));
    return SetSelection(ec, full, caret);
}

HRESULT Composition::Commit(TfEditCookie ec, const wire::CommitOutput& output) noexcept {
    Com<ITfRange> range;
    HRESULT hr = S_OK;
    if (composition_) {
        hr = composition_->GetRange(&range);
    } else if (terminatedRange_) {
        range.p = terminatedRange_; // takes our reference
        terminatedRange_ = nullptr;
    } else {
        // R is the selection.
        TF_SELECTION sel = {};
        ULONG fetched = 0;
        hr = context_->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &fetched);
        if (SUCCEEDED(hr) && fetched == 1) {
            range.p = sel.range; // takes the reference GetSelection returned
        } else if (SUCCEEDED(hr)) {
            hr = E_FAIL;
        }
    }
    if (FAILED(hr)) return hr;

    LONG shifted = 0;
    if (output.deleteBefore > 0) range->ShiftStart(ec, -static_cast<LONG>(output.deleteBefore), &shifted, nullptr);
    if (output.deleteAfter > 0) range->ShiftEnd(ec, static_cast<LONG>(output.deleteAfter), &shifted, nullptr);

    hr = range->SetText(ec, 0, output.text.c_str(), static_cast<LONG>(output.text.size()));
    if (FAILED(hr)) return hr;

    // Clear any display attribute left on the committed range, then end and place the caret after the text.
    Com<ITfProperty> prop;
    if (SUCCEEDED(context_->GetProperty(GUID_PROP_ATTRIBUTE, &prop))) prop->Clear(ec, range);

    const LONG length = static_cast<LONG>(output.text.size());
    hr = SetSelection(ec, range, length);
    if (composition_) {
        composition_->EndComposition(ec);
        composition_->Release();
        composition_ = nullptr;
    }
    shown_.clear();
    typed_.clear();
    return hr;
}

HRESULT Composition::EndKeepingText(TfEditCookie ec) noexcept {
    ForgetRange();
    if (!composition_) return S_OK;
    // The user's text stays as they typed it, "@" and all, rather than as the engine showed it. Only over what we set:
    // if the app changed the composition's text, that is what the document keeps.
    Com<ITfRange> range;
    if (!typed_.empty() && SUCCEEDED(composition_->GetRange(&range)) && range) {
        wire::Text now;
        if (ReadText(ec, range, now) && now == shown_ &&
            SUCCEEDED(range->SetText(ec, 0, typed_.c_str(), static_cast<LONG>(typed_.size())))) {
            Com<ITfRange> full;
            if (SUCCEEDED(composition_->GetRange(&full)) && full) {
                SetSelection(ec, full, static_cast<LONG>(typed_.size()));
            }
        }
    }
    ClearDisplayAttributes(ec);
    HRESULT hr = composition_->EndComposition(ec);
    composition_->Release();
    composition_ = nullptr;
    shown_.clear();
    typed_.clear();
    return hr;
}

bool Composition::ReadText(TfEditCookie ec, ITfRange* range, wire::Text& out) noexcept {
    Com<ITfRange> cursor;
    if (FAILED(range->Clone(&cursor))) return false;
    out.clear();
    for (;;) {
        ULONG got = 0;
        wchar_t buffer[256];
        if (FAILED(cursor->GetText(ec, TF_TF_MOVESTART, buffer, static_cast<ULONG>(std::size(buffer)), &got))) return false;
        out.append(buffer, got);
        if (got < std::size(buffer)) return true;
    }
}

bool Composition::CompositionLength(TfEditCookie ec, LONG& length) const noexcept {
    if (!composition_) return false;
    Com<ITfRange> cursor;
    if (FAILED(composition_->GetRange(&cursor))) return false;
    // Read the range's text in chunks; TF_TF_MOVESTART advances the clone past what it returns, so the loop ends when
    // the range is exhausted. This is the length the document actually holds (§5.1 `comp`).
    LONG total = 0;
    for (;;) {
        ULONG got = 0;
        wchar_t buffer[256];
        if (FAILED(cursor->GetText(ec, TF_TF_MOVESTART, buffer, static_cast<ULONG>(std::size(buffer)), &got))) break;
        total += static_cast<LONG>(got);
        if (got < std::size(buffer)) break;
    }
    length = total;
    return true;
}

HRESULT Composition::GetRange(ITfRange** range) const noexcept {
    if (!range) return E_INVALIDARG;
    *range = nullptr;
    if (!composition_) return S_FALSE;
    return composition_->GetRange(range);
}

} // namespace aio
