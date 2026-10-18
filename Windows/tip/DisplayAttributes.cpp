#include "DisplayAttributes.h"

#include <iterator>

#include "Globals.h"

namespace aio {

namespace {

constexpr wire::Style kStyles[] = {wire::Style::raw, wire::Style::draft, wire::Style::converted, wire::Style::target};

// raw: dotted; draft: solid; converted: bold; target: highlighted. The app draws them (TSF tells it how).
TF_DISPLAYATTRIBUTE Attribute(wire::Style style) {
    TF_DISPLAYATTRIBUTE a = {};
    a.crText.type = TF_CT_NONE;
    a.crBk.type = TF_CT_NONE;
    a.crLine.type = TF_CT_NONE;
    a.fBoldLine = FALSE;
    switch (style) {
    case wire::Style::raw:
        a.lsStyle = TF_LS_DOT;
        a.bAttr = TF_ATTR_INPUT;
        break;
    case wire::Style::draft:
        a.lsStyle = TF_LS_SOLID;
        a.bAttr = TF_ATTR_INPUT;
        break;
    case wire::Style::converted:
        a.lsStyle = TF_LS_SOLID;
        a.fBoldLine = TRUE;
        a.bAttr = TF_ATTR_CONVERTED;
        break;
    case wire::Style::target:
        a.lsStyle = TF_LS_SOLID;
        a.fBoldLine = TRUE;
        a.crText.type = TF_CT_SYSCOLOR;
        a.crText.nIndex = COLOR_HIGHLIGHTTEXT;
        a.crBk.type = TF_CT_SYSCOLOR;
        a.crBk.nIndex = COLOR_HIGHLIGHT;
        a.bAttr = TF_ATTR_TARGET_CONVERTED;
        break;
    }
    return a;
}

const wchar_t* Description(wire::Style style) {
    switch (style) {
    case wire::Style::raw: return L"AllInOneIME raw";
    case wire::Style::draft: return L"AllInOneIME draft";
    case wire::Style::converted: return L"AllInOneIME converted";
    case wire::Style::target: return L"AllInOneIME target";
    }
    return L"AllInOneIME";
}

} // namespace

const GUID& DisplayAttributeGuid(wire::Style style) noexcept {
    switch (style) {
    case wire::Style::draft: return kGuidDisplayDraft;
    case wire::Style::converted: return kGuidDisplayConverted;
    case wire::Style::target: return kGuidDisplayTarget;
    case wire::Style::raw: break;
    }
    return kGuidDisplayRaw;
}

bool StyleOfGuid(REFGUID guid, wire::Style& style) noexcept {
    for (auto s : kStyles) {
        if (IsEqualGUID(guid, DisplayAttributeGuid(s))) {
            style = s;
            return true;
        }
    }
    return false;
}

// ---- DisplayAttributeInfo ----

DisplayAttributeInfo::DisplayAttributeInfo(wire::Style style) : style_(style) {
    DllAddRef();
}

DisplayAttributeInfo::~DisplayAttributeInfo() {
    DllRelease();
}

STDMETHODIMP DisplayAttributeInfo::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfDisplayAttributeInfo)) {
        *ppv = static_cast<ITfDisplayAttributeInfo*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) DisplayAttributeInfo::AddRef() {
    return static_cast<ULONG>(InterlockedIncrement(&refs_));
}

STDMETHODIMP_(ULONG) DisplayAttributeInfo::Release() {
    const LONG n = InterlockedDecrement(&refs_);
    if (n == 0) delete this;
    return static_cast<ULONG>(n);
}

STDMETHODIMP DisplayAttributeInfo::GetGUID(GUID* guid) {
    if (!guid) return E_INVALIDARG;
    *guid = DisplayAttributeGuid(style_);
    return S_OK;
}

STDMETHODIMP DisplayAttributeInfo::GetDescription(BSTR* description) {
    if (!description) return E_INVALIDARG;
    *description = SysAllocString(Description(style_));
    return *description ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP DisplayAttributeInfo::GetAttributeInfo(TF_DISPLAYATTRIBUTE* attribute) {
    if (!attribute) return E_INVALIDARG;
    *attribute = Attribute(style_);
    return S_OK;
}

STDMETHODIMP DisplayAttributeInfo::SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) {
    return E_NOTIMPL;
}

STDMETHODIMP DisplayAttributeInfo::Reset() {
    return S_OK;
}

// ---- EnumDisplayAttributeInfo ----

EnumDisplayAttributeInfo::EnumDisplayAttributeInfo() {
    DllAddRef();
}

EnumDisplayAttributeInfo::~EnumDisplayAttributeInfo() {
    DllRelease();
}

STDMETHODIMP EnumDisplayAttributeInfo::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_INVALIDARG;
    *ppv = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IEnumTfDisplayAttributeInfo)) {
        *ppv = static_cast<IEnumTfDisplayAttributeInfo*>(this);
        AddRef();
        return S_OK;
    }
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) EnumDisplayAttributeInfo::AddRef() {
    return static_cast<ULONG>(InterlockedIncrement(&refs_));
}

STDMETHODIMP_(ULONG) EnumDisplayAttributeInfo::Release() {
    const LONG n = InterlockedDecrement(&refs_);
    if (n == 0) delete this;
    return static_cast<ULONG>(n);
}

STDMETHODIMP EnumDisplayAttributeInfo::Clone(IEnumTfDisplayAttributeInfo** clone) {
    if (!clone) return E_INVALIDARG;
    return ComGuard([&] {
        auto* copy = new EnumDisplayAttributeInfo();
        copy->index_ = index_;
        *clone = copy;
        return S_OK;
    });
}

STDMETHODIMP EnumDisplayAttributeInfo::Next(ULONG count, ITfDisplayAttributeInfo** infos, ULONG* fetched) {
    if (!infos) return E_INVALIDARG;
    return ComGuard([&]() -> HRESULT {
        ULONG n = 0;
        while (n < count && index_ < std::size(kStyles)) {
            infos[n++] = new DisplayAttributeInfo(kStyles[index_++]);
        }
        if (fetched) *fetched = n;
        return n == count ? S_OK : S_FALSE;
    });
}

STDMETHODIMP EnumDisplayAttributeInfo::Reset() {
    index_ = 0;
    return S_OK;
}

STDMETHODIMP EnumDisplayAttributeInfo::Skip(ULONG count) {
    const ULONG left = static_cast<ULONG>(std::size(kStyles)) - index_;
    if (count > left) {
        index_ = static_cast<ULONG>(std::size(kStyles));
        return S_FALSE;
    }
    index_ += count;
    return S_OK;
}

// ---- atoms ----

void DisplayAttributeAtoms::Register() noexcept {
    ITfCategoryMgr* categories = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                reinterpret_cast<void**>(&categories)))) {
        return;
    }
    for (size_t i = 0; i < std::size(kStyles); ++i) {
        categories->RegisterGUID(DisplayAttributeGuid(kStyles[i]), &atoms_[i]);
    }
    categories->Release();
}

TfGuidAtom DisplayAttributeAtoms::Atom(wire::Style style) const noexcept {
    return atoms_[static_cast<size_t>(style)];
}

} // namespace aio
