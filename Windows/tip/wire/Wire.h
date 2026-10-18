// The wire protocol v1 (Core/docs/wire-protocol-v1.md) as plain structs: what the DLL sends and what it reads.
//
// Text the document has (TSF's, UTF-16) stays UTF-16 here; WireJson.cpp converts it to and from the UTF-8 of the
// frames. Offsets and lengths are UTF-16 code units, as on the wire. Nothing in here throws: encoders return an empty
// string and the decoder an error when something is wrong.

#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace aio::wire {

inline constexpr int kVersion = 1;

// §2.2: the body sizes, without the 4-byte prefix.
inline constexpr size_t kMaxClientBody = 64 * 1024;
inline constexpr size_t kMaxEngineBody = 1024 * 1024;

// TSF's text: UTF-16 code units, as the wire counts them.
using Text = std::wstring;

// The core's `Modifiers` (KeyInput.swift), bit for bit; written as the names in `kModifierNames`, in bit order.
enum Modifier : uint16_t {
    kShift = 1 << 0,
    kControl = 1 << 1,
    kOption = 1 << 2,  // Alt
    kCommand = 1 << 3, // the Windows key
    kCapsLock = 1 << 4,
    kLeftOption = 1 << 5,
    kRightOption = 1 << 6,
    kFunction = 1 << 7,
    kLeftShift = 1 << 8,
    kRightShift = 1 << 9,
    kLeftControl = 1 << 10,
    kRightControl = 1 << 11,
    kLeftCommand = 1 << 12,
    kRightCommand = 1 << 13,
    kAltGraph = 1 << 14,
};
inline constexpr const char* kModifierNames[] = {
    "shift", "control", "option", "command", "capsLock", "leftOption", "rightOption", "function",
    "leftShift", "rightShift", "leftControl", "rightControl", "leftCommand", "rightCommand", "altGraph",
};

// §4.
struct FieldInfo {
    std::string app;     // UTF-8: "win:<exe>" or "win:<AUMID>"
    std::string process; // UTF-8
    bool secure = false;
    bool readOnly = false;
    std::vector<int64_t> scopes;
    std::string layout; // the KLID, "00000409"

    bool operator==(const FieldInfo&) const = default;
};

// §5.1 `ctx`.
struct FieldContext {
    std::optional<std::pair<int64_t, int64_t>> sel;
    Text before;
    Text selText;
    bool selTruncated = false;
    std::optional<int64_t> comp;

    bool operator==(const FieldContext&) const = default;
};

// §5.1 `key`. The Windows DLL sends the raw values only (no `key`, no `usage`).
struct Key {
    uint32_t vk = 0;
    uint32_t scan = 0;
    bool extended = false;
    Text text;
    Text textIgnoringModifiers;
    bool isDeadKey = false;
    bool isRepeat = false;
    uint16_t modifiers = 0;
};

// §6.
enum class Style { raw, draft, converted, target };

struct Segment {
    int64_t from = 0;
    int64_t to = 0;
    Style style = Style::raw;
};

struct CommitOutput {
    Text text;
    int64_t deleteBefore = 0;
    int64_t deleteAfter = 0;
    bool afterKey = false;
};

struct CompositionOutput {
    Text text;
    int64_t caret = 0;
    std::vector<Segment> segments;
};

struct PanelOutput {
    bool shown = false;
};

struct AllowForegroundOutput {};

// Unknown ops are skipped when decoding (§9), so they never get here.
using Output = std::variant<CommitOutput, CompositionOutput, PanelOutput, AllowForegroundOutput>;

// §5.3.
struct Result {
    bool handled = false;
    std::vector<Output> outputs;
};

// §2.4.
struct Limits {
    int contextBefore = 32; // the engine may raise it to 256
    int selection = 10002;  // the spec gives no default; this is the golden's value
};

// ---- DLL → engine -------------------------------------------------------------------------------------------------

struct Hello {
    uint32_t id = 0;
    std::vector<int> versions{kVersion};
    std::string client; // "tip/0.6.4"
    std::string arch;   // "x64"
    uint32_t pid = 0;
    uint32_t tid = 0;
    std::vector<std::string> capabilities;
};

struct Open {
    uint32_t id = 0;
    uint32_t sid = 0;
    FieldInfo field;
};

struct Focus {
    uint32_t id = 0;
    uint32_t sid = 0;
    uint32_t focus = 0;
    std::optional<FieldInfo> field; // only when re-sent for a changed layout or input scope
};

struct Blur {
    uint32_t id = 0;
    uint32_t sid = 0;
};

struct Close {
    uint32_t id = 0;
    uint32_t sid = 0;
};

struct KeyEvent {
    uint32_t id = 0;
    bool down = true; // keyDown or keyUp
    uint32_t sid = 0;
    uint64_t t = 0;
    Key key;
    FieldContext ctx;
};

struct EndComposition {
    uint32_t id = 0;
    uint32_t sid = 0;
    std::string reason; // "terminated" or "timeout"
};

struct Ping {
    uint32_t id = 0;
};

struct Caret {
    uint32_t id = 0;
    uint32_t sid = 0;
    int32_t rect[4] = {}; // left, top, width, height in physical screen pixels
    bool exact = true;
    uint64_t hwnd = 0;
};

struct Applied {
    uint32_t id = 0;
    uint32_t re = 0;
    bool ok = true;
    std::string reason; // with ok:false: notFocused, gone, readOnly, denied
    std::optional<FieldContext> ctx;
};

// Each returns the frame's UTF-8 JSON body (no prefix) in canonical form (§1: defaults left out), or "" if it couldn't
// be built.
std::string Encode(const Hello&) noexcept;
std::string Encode(const Open&) noexcept;
std::string Encode(const Focus&) noexcept;
std::string Encode(const Blur&) noexcept;
std::string Encode(const Close&) noexcept;
std::string Encode(const KeyEvent&) noexcept;
std::string Encode(const EndComposition&) noexcept;
std::string Encode(const Ping&) noexcept;
std::string Encode(const Caret&) noexcept;
std::string Encode(const Applied&) noexcept;

// ---- engine → DLL -------------------------------------------------------------------------------------------------

enum class EngineType { welcome, result, pong, error, bye, apply, unknown };

struct Welcome {
    int version = 0;
    std::string engine;
    uint32_t enginePid = 0;
    std::vector<std::string> capabilities;
    Limits limits;
};

struct EngineMessage {
    EngineType type = EngineType::unknown;
    std::string typeName;
    uint32_t id = 0;
    std::optional<uint32_t> re;

    Welcome welcome;   // welcome
    Result result;     // result; for apply, `result.outputs` holds the outputs
    std::string code;  // error
    std::string reason;          // bye
    std::optional<uint32_t> retryMs; // bye
    uint32_t sid = 0;   // apply
    uint32_t focus = 0; // apply
};

enum class DecodeError {
    none,
    badFrame,   // not JSON, not UTF-8, not an object, or nested deeper than 16
    badMessage, // a field of a known type missing or of the wrong type
};

// Reads one body. Never throws. An unknown `type` decodes fine, as `EngineType::unknown`.
DecodeError Decode(std::string_view body, EngineMessage& out) noexcept;

// ---- framing (§2.2) -----------------------------------------------------------------------------------------------

// The u32 little-endian length, then the body.
std::string Frame(std::string_view body);

// The body of one pipe message, if its prefix equals its size minus 4.
bool Unframe(std::string_view message, std::string_view& body) noexcept;

// ---- text ---------------------------------------------------------------------------------------------------------

// Lone surrogates become U+FFFD.
std::string ToUtf8(std::wstring_view text) noexcept;
// Invalid UTF-8 gives false.
bool FromUtf8(std::string_view utf8, std::wstring& out) noexcept;

const char* StyleName(Style) noexcept;

} // namespace aio::wire
