#include "Keys.h"

#include <algorithm>
#include <iterator>

namespace aio {

namespace {

constexpr UINT kToUnicodeKeepState = 0x4;

bool Down(int vk) {
    return (GetKeyState(vk) & 0x8000) != 0;
}

// ToUnicodeEx's text: below zero is a dead key, whose text is the accent.
wire::Text Translate(UINT vk, UINT scan, const BYTE* state, HKL hkl, bool* isDead) {
    wchar_t buffer[16] = {};
    const int n = ToUnicodeEx(vk, scan, state, buffer, static_cast<int>(std::size(buffer)), kToUnicodeKeepState, hkl);
    if (isDead) *isDead = n < 0;
    if (n < 0) return wire::Text(1, buffer[0]);
    if (n == 0) return {};
    return wire::Text(buffer, static_cast<size_t>(std::min<int>(n, static_cast<int>(std::size(buffer)))));
}

// The bits of one modifier key, by its virtual key and, for the generic ones, its scan code or extended bit.
uint16_t ModifierBits(WPARAM vk, UINT scan, bool extended) {
    using namespace wire;
    switch (vk) {
    case VK_SHIFT: return scan == 0x36 ? (kShift | kRightShift) : (kShift | kLeftShift);
    case VK_LSHIFT: return kShift | kLeftShift;
    case VK_RSHIFT: return kShift | kRightShift;
    case VK_CONTROL: return extended ? (kControl | kRightControl) : (kControl | kLeftControl);
    case VK_LCONTROL: return kControl | kLeftControl;
    case VK_RCONTROL: return kControl | kRightControl;
    case VK_MENU: return extended ? (kOption | kRightOption) : (kOption | kLeftOption);
    case VK_LMENU: return kOption | kLeftOption;
    case VK_RMENU: return kOption | kRightOption;
    case VK_LWIN: return kCommand | kLeftCommand;
    case VK_RWIN: return kCommand | kRightCommand;
    default: return 0;
    }
}

uint16_t KeyStateModifiers() {
    using namespace wire;
    uint16_t m = 0;
    if (Down(VK_SHIFT)) m |= kShift;
    if (Down(VK_CONTROL)) m |= kControl;
    if (Down(VK_MENU)) m |= kOption;
    if (Down(VK_LWIN) || Down(VK_RWIN)) m |= kCommand;
    if (GetKeyState(VK_CAPITAL) & 1) m |= kCapsLock;
    if (Down(VK_LMENU)) m |= kLeftOption;
    if (Down(VK_RMENU)) m |= kRightOption;
    if (Down(VK_LSHIFT)) m |= kLeftShift;
    if (Down(VK_RSHIFT)) m |= kRightShift;
    if (Down(VK_LCONTROL)) m |= kLeftControl;
    if (Down(VK_RCONTROL)) m |= kRightControl;
    if (Down(VK_LWIN)) m |= kLeftCommand;
    if (Down(VK_RWIN)) m |= kRightCommand;
    return m;
}

} // namespace

bool IsModifierKey(WPARAM vk) noexcept {
    return (vk >= 0x10 && vk <= 0x12) || vk == 0x5B || vk == 0x5C || (vk >= 0xA0 && vk <= 0xA5);
}

wire::Key ReadKey(WPARAM wParam, LPARAM lParam, bool down) {
    using namespace wire;
    Key key;
    key.vk = static_cast<uint32_t>(wParam);
    key.scan = static_cast<uint32_t>((lParam >> 16) & 0xFF);
    key.extended = ((lParam >> 24) & 1) != 0;
    // Bit 30 is the previous key state: set on every key-up, so it means a repeat only on key-downs.
    key.isRepeat = down && ((lParam >> 30) & 1) != 0;

    uint16_t modifiers = KeyStateModifiers();
    // GetKeyState may not have taken this event yet (TSF sees keys before the app's queue does): apply it.
    if (const uint16_t bits = ModifierBits(wParam, key.scan, key.extended)) {
        const uint16_t sides = bits & ~(kShift | kControl | kOption | kCommand);
        const uint16_t kind = bits & (kShift | kControl | kOption | kCommand);
        if (down) {
            modifiers |= bits;
        } else {
            modifiers &= ~sides;
            const uint16_t kindSides = kind == kShift     ? (kLeftShift | kRightShift)
                                       : kind == kControl ? (kLeftControl | kRightControl)
                                       : kind == kOption  ? (kLeftOption | kRightOption)
                                                          : (kLeftCommand | kRightCommand);
            if (!(modifiers & kindSides)) modifiers &= ~kind;
        }
    }
    key.modifiers = modifiers;

    if (down && !IsModifierKey(wParam)) {
        BYTE state[256] = {};
        if (GetKeyboardState(state)) {
            const HKL hkl = GetKeyboardLayout(0);
            // The scan code alone: its bit 15 would mean a key-up.
            const UINT scan = key.scan;
            key.text = Translate(key.vk, scan, state, hkl, &key.isDeadKey);
            for (int vk : {VK_CONTROL, VK_LCONTROL, VK_RCONTROL, VK_MENU, VK_LMENU, VK_RMENU}) state[vk] = 0;
            key.textIgnoringModifiers = Translate(key.vk, scan, state, hkl, nullptr);
        }
    }
    return key;
}

} // namespace aio
