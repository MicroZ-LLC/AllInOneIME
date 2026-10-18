// The display attributes of the composition's styles (§6): raw, draft, converted, target.
//
// The text service is their ITfDisplayAttributeProvider (TSF asks it by CLSID); this file has the info objects, their
// enumerator, and the GUID atoms the composition's ranges are marked with.

#pragma once

#include <windows.h>
#include <msctf.h>

#include "wire/Wire.h"

namespace aio {

// The info of one style.
class DisplayAttributeInfo final : public ITfDisplayAttributeInfo {
public:
    explicit DisplayAttributeInfo(wire::Style style);

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    STDMETHODIMP GetGUID(GUID* guid) override;
    STDMETHODIMP GetDescription(BSTR* description) override;
    STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE* attribute) override;
    STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE* attribute) override;
    STDMETHODIMP Reset() override;

private:
    ~DisplayAttributeInfo();
    LONG refs_ = 1;
    wire::Style style_;
};

class EnumDisplayAttributeInfo final : public IEnumTfDisplayAttributeInfo {
public:
    EnumDisplayAttributeInfo();

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo** clone) override;
    STDMETHODIMP Next(ULONG count, ITfDisplayAttributeInfo** infos, ULONG* fetched) override;
    STDMETHODIMP Reset() override;
    STDMETHODIMP Skip(ULONG count) override;

private:
    ~EnumDisplayAttributeInfo();
    LONG refs_ = 1;
    ULONG index_ = 0;
};

// The GUID of a style's display attribute; the style of a GUID.
const GUID& DisplayAttributeGuid(wire::Style style) noexcept;
bool StyleOfGuid(REFGUID guid, wire::Style& style) noexcept;

// The atoms ranges are marked with (GUID_PROP_ATTRIBUTE holds a TfGuidAtom).
class DisplayAttributeAtoms {
public:
    void Register() noexcept; // through ITfCategoryMgr::RegisterGUID
    TfGuidAtom Atom(wire::Style style) const noexcept;

private:
    TfGuidAtom atoms_[4] = {TF_INVALID_GUIDATOM, TF_INVALID_GUIDATOM, TF_INVALID_GUIDATOM, TF_INVALID_GUIDATOM};
};

} // namespace aio
