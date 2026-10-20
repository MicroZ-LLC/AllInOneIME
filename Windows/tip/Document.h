// Reading a TSF context into the wire's FieldInfo (§4) and FieldContext (§5.1).

#pragma once

#include <windows.h>
#include <msctf.h>

#include "wire/Wire.h"

namespace aio {

class Composition;

// The field's identity and flags. `app`/`process` are this process's (the engine overrides them, §4); `scopes` and
// `secure` come from the GUID_PROP_INPUTSCOPE property at the selection, read under `ec` (TF_INVALID_EDIT_COOKIE to
// skip them); `readOnly` from the context's status; `layout` from the thread's KLID.
wire::FieldInfo ReadFieldInfo(ITfContext* context, TfEditCookie ec) noexcept;

// §8: IS_PASSWORD (31), IS_NUMERIC_PASSWORD (63) and the PIN scopes (64–66) make a field secure.
bool ScopesAreSecure(const std::vector<int64_t>& scopes) noexcept;

// The selection, the text before it (or before the composition), the selection text, and the composition length, read
// under a read lock (`ec`). `contextBefore` and `selection` cap `before` and `selText` (§5.1).
wire::FieldContext ReadFieldContext(TfEditCookie ec, ITfContext* context, const Composition& composition,
                                    int contextBefore, int selection) noexcept;

// The thread's keyboard layout as an 8-hex-digit KLID string ("00000409").
std::string ThreadLayoutKlid() noexcept;

// The context turned keyboard input off (GUID_COMPARTMENT_KEYBOARD_DISABLED), or is an empty context
// (GUID_COMPARTMENT_EMPTYCONTEXT): the DLL then treats it like a secure field and sends nothing (§8).
bool KeyboardDisabled(ITfContext* context) noexcept;

} // namespace aio
