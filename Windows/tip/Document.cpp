#include "Document.h"

#include <inputscope.h>

#include <algorithm>
#include <vector>

#include "Composition.h"
#include "Log.h"
#include "ProcessInfo.h"

namespace aio {

namespace {

template <class T>
void Release(T*& p) {
    if (p) {
        p->Release();
        p = nullptr;
    }
}

} // namespace

bool ScopesAreSecure(const std::vector<int64_t>& scopes) noexcept {
    for (int64_t s : scopes) {
        if (s == IS_PASSWORD || s == IS_NUMERIC_PASSWORD || s == IS_NUMERIC_PIN || s == IS_ALPHANUMERIC_PIN ||
            s == IS_ALPHANUMERIC_PIN_SET) {
            return true;
        }
    }
    return false;
}

std::string ThreadLayoutKlid() noexcept {
    // GetKeyboardLayoutNameW names the calling thread's active layout: "00010409" for US-Dvorak, which an HKL's low
    // word alone can't tell from US.
    wchar_t name[KL_NAMELENGTH] = {};
    if (GetKeyboardLayoutNameW(name)) {
        char klid[KL_NAMELENGTH] = {};
        for (int i = 0; i < KL_NAMELENGTH - 1 && name[i]; ++i) klid[i] = name[i] < 0x80 ? static_cast<char>(name[i]) : '?';
        return klid;
    }
    const HKL hkl = GetKeyboardLayout(0);
    const auto langid = static_cast<unsigned>(reinterpret_cast<uintptr_t>(hkl) & 0xFFFF);
    char klid[9];
    _snprintf_s(klid, sizeof klid, _TRUNCATE, "%08X", langid);
    return klid;
}

bool KeyboardDisabled(ITfContext* context) noexcept {
    if (!context) return false;
    ITfCompartmentMgr* compartments = nullptr;
    if (FAILED(context->QueryInterface(IID_ITfCompartmentMgr, reinterpret_cast<void**>(&compartments))) ||
        !compartments) {
        return false;
    }
    bool disabled = false;
    for (const GUID* guid : {&GUID_COMPARTMENT_KEYBOARD_DISABLED, &GUID_COMPARTMENT_EMPTYCONTEXT}) {
        ITfCompartment* compartment = nullptr;
        if (SUCCEEDED(compartments->GetCompartment(*guid, &compartment)) && compartment) {
            VARIANT var;
            VariantInit(&var);
            if (SUCCEEDED(compartment->GetValue(&var)) && var.vt == VT_I4 && var.lVal != 0) disabled = true;
            VariantClear(&var);
            compartment->Release();
        }
    }
    compartments->Release();
    return disabled;
}

// The ITfInputScope at the selection: GUID_PROP_INPUTSCOPE is an *application* property (set by the control or by
// SetInputScopes), so it is read with GetAppProperty; its value is an IUnknown that QIs to ITfInputScope.
static void ReadInputScopes(TfEditCookie ec, ITfContext* context, std::vector<int64_t>& scopes) {
    ITfReadOnlyProperty* prop = nullptr;
    if (FAILED(context->GetAppProperty(GUID_PROP_INPUTSCOPE, &prop)) || !prop) return;
    TF_SELECTION sel = {};
    ULONG fetched = 0;
    if (SUCCEEDED(context->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &fetched)) && fetched == 1) {
        VARIANT var;
        VariantInit(&var);
        if (SUCCEEDED(prop->GetValue(ec, sel.range, &var)) && var.vt == VT_UNKNOWN && var.punkVal) {
            ITfInputScope* inputScope = nullptr;
            if (SUCCEEDED(var.punkVal->QueryInterface(IID_ITfInputScope, reinterpret_cast<void**>(&inputScope))) &&
                inputScope) {
                InputScope* raw = nullptr;
                UINT count = 0;
                if (SUCCEEDED(inputScope->GetInputScopes(&raw, &count)) && raw) {
                    for (UINT i = 0; i < count && scopes.size() < 32; ++i) scopes.push_back(raw[i]);
                    CoTaskMemFree(raw);
                }
                inputScope->Release();
            }
        }
        VariantClear(&var);
        sel.range->Release();
    }
    prop->Release();
}

wire::FieldInfo ReadFieldInfo(ITfContext* context, TfEditCookie ec) noexcept {
    wire::FieldInfo field;
    const auto& me = CurrentProcess();
    field.app = me.app;
    field.process = me.exeName;
    field.layout = ThreadLayoutKlid();
    if (!context) return field;

    // Read-only (§4): from the context's status.
    TF_STATUS status = {};
    if (SUCCEEDED(context->GetStatus(&status)) && (status.dwDynamicFlags & TF_SD_READONLY)) field.readOnly = true;

    if (ec != TF_INVALID_EDIT_COOKIE) {
        ReadInputScopes(ec, context, field.scopes);
        field.secure = ScopesAreSecure(field.scopes);
    }
    return field;
}

wire::FieldContext ReadFieldContext(TfEditCookie ec, ITfContext* context, const Composition& composition,
                                    int contextBefore, int selection) noexcept {
    wire::FieldContext ctx;
    if (!context) return ctx;

    TF_SELECTION sel = {};
    ULONG fetched = 0;
    if (FAILED(context->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &sel, &fetched)) || fetched != 1) {
        return ctx; // selection unknown: `sel` stays omitted
    }
    ITfRange* selRange = sel.range;

    // Absolute ACP of the selection, via the ACP store if the app is one.
    ITfRangeACP* acp = nullptr;
    LONG selStart = -1, selLen = 0;
    if (SUCCEEDED(selRange->QueryInterface(IID_ITfRangeACP, reinterpret_cast<void**>(&acp))) && acp) {
        acp->GetExtent(&selStart, &selLen);
        acp->Release();
    }
    if (selStart >= 0) {
        ctx.sel = {selStart, selStart + selLen};
    }

    // `before`: up to `contextBefore` units before the selection start (or before our composition, if composing).
    ITfRange* anchor = nullptr;
    LONG compLen = 0;
    const bool composing = composition.CompositionLength(ec, compLen);
    ITfRange* compRange = nullptr;
    if (composing && SUCCEEDED(composition.GetRange(&compRange)) && compRange) {
        compRange->Clone(&anchor);
    } else {
        selRange->Clone(&anchor);
    }
    if (anchor) {
        anchor->Collapse(ec, TF_ANCHOR_START);
        ITfRange* beforeRange = nullptr;
        if (SUCCEEDED(anchor->Clone(&beforeRange)) && beforeRange) {
            LONG shifted = 0;
            beforeRange->ShiftStart(ec, -contextBefore, &shifted, nullptr); // shifted is negative or zero
            wchar_t buffer[256];
            const ULONG want = std::min<ULONG>(static_cast<ULONG>(contextBefore), static_cast<ULONG>(std::size(buffer)));
            ULONG got = 0;
            if (want && SUCCEEDED(beforeRange->GetText(ec, 0, buffer, want, &got))) {
                ctx.before.assign(buffer, got);
            }
            beforeRange->Release();
        }
        anchor->Release();
    }
    Release(compRange);

    if (composing) ctx.comp = compLen;

    // `selText`: a non-empty selection, capped at `selection` (§5.1).
    if (selLen > 0 && selection > 0) {
        std::wstring text;
        ITfRange* cursor = nullptr;
        if (SUCCEEDED(selRange->Clone(&cursor)) && cursor) {
            for (;;) {
                wchar_t buffer[256];
                ULONG got = 0;
                if (FAILED(cursor->GetText(ec, TF_TF_MOVESTART, buffer, static_cast<ULONG>(std::size(buffer)), &got))) {
                    break;
                }
                text.append(buffer, got);
                if (got < std::size(buffer)) break;
                if (text.size() > static_cast<size_t>(selection)) break;
            }
            cursor->Release();
        }
        if (text.size() > static_cast<size_t>(selection)) {
            text.resize(static_cast<size_t>(selection));
            ctx.selTruncated = true;
        }
        ctx.selText = std::move(text);
    }

    selRange->Release();
    return ctx;
}

} // namespace aio
