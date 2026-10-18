// §5.1: the raw `key` of a key event, as the Windows DLL sends it.

#pragma once

#include <windows.h>

#include "wire/Wire.h"

namespace aio {

// VK 0x10–0x12, 0x5B, 0x5C and 0xA0–0xA5 (§5.2): the key-ups always sent.
bool IsModifierKey(WPARAM vk) noexcept;

// `vk`, `scan`, `extended` and `isRepeat` from the message; `text` and `textIgnoringModifiers` from ToUnicodeEx with
// the thread's keyboard state and layout (flag 0x4, so dead-key state is left alone); `modifiers` from GetKeyState,
// with the event's own modifier key applied, so they are the modifiers after the change on modifier keys.
wire::Key ReadKey(WPARAM wParam, LPARAM lParam, bool down);

} // namespace aio
