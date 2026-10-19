// A golden transcript (Core/docs §10 line format): `>` a frame the DLL must send, `<` a frame the engine sends, `#` a
// comment, `#!` a fixture directive. Bodies compare as JSON values, ignoring key order; `"$any"` matches any value.
//
// Two fields are normalized to `$any` before comparing, because a headless test host can't reproduce them bit for bit
// and the spec defines them as host-derived: the key timestamp `t` (GetTickCount64, §5.1), and — only inside a
// `field` object — `app`, `process` and `layout` (the engine derives `app`/`process`; the KLID is the test host's).
// This is the one accommodation the test makes; everything else is matched literally.
//
// The test host's directives (the spec's own, `provider`, `inputLanguage`, `run tasks`, `click …`, are the engine's and
// are ignored here):
//   #! no-engine                  no pipe at all: the DLL stays passive
//   #! secure                     the field's input scope is IS_PASSWORD
//   #! expect-silence             after the last line, the DLL sends nothing more (else: nothing but what is listed)
//   #! expect-document "<text>"   the document's text at the end
//   #! type down|up vk=N scan=N [char=c] [shift|lshift|rshift|ctrl|alt|extended]
//                                 a key to type that sends no frame (a secure field's, a non-modifier key-up); the
//                                 `>` keyDown/keyUp frames are typed too, all in transcript order
//   #! double-test                every key is tested twice before it is handled (an app that peeks at its messages)
//   #! terminate                  the app ends the composition (ITfContextOwnerCompositionServices)
//   #! wait <ms>                  the host runs its message loop for a while before the next step
//   #! reconnect                  the engine drops the connection and takes the DLL's next one
//   #! scope <n>                  the field's input scope becomes n (the DLL notices at its next key)
//
// The engine's goldens (Core/Tests/AllInOneIMEWireTests/WireGoldens) replay here too: a line without `v` gets
// `"v":1` (the spec notes' golden format: the engine sends `v` in every frame, and the DLL does), and an
// `expect-document` argument is a JSON string.

#pragma once

#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace aio::test {

struct TypeKey {
    bool down = true;
    WORD vk = 0;
    WORD scan = 0;
    bool extended = false;
    // Keyboard-state changes this key makes, so ToUnicodeEx/GetKeyState in the DLL see the right modifiers.
    bool shift = false, ctrl = false, alt = false; // aggregate held-after-this-event
    bool lshift = false, rshift = false, lctrl = false, rctrl = false, lalt = false, ralt = false;
    bool setsState = false; // this `#! type` carried explicit modifier flags
};

// What the test host does, in transcript order: type a key, or act as the app would.
struct Step {
    enum class Kind { key, terminate, wait, scope } kind = Kind::key;
    TypeKey key;    // for Kind::key
    DWORD waitMs = 0; // for Kind::wait
    int scope = 0;    // for Kind::scope
};

struct Line {
    enum class Kind { comment, directive, fromDll, fromEngine } kind;
    std::string directive;              // for Kind::directive: the word after "#!"
    std::string arg;                    // the rest of the directive line
    nlohmann::json body;                // for fromDll / fromEngine
};

struct Transcript {
    std::vector<Line> lines;
    bool noEngine = false;              // #! no-engine
    bool expectSilence = false;         // #! expect-silence (no session frames from the DLL)
    bool secure = false;                // #! secure (the field is a password field: IS_PASSWORD)
    bool doubleTest = false;            // #! double-test
    bool hasExpectDocument = false;
    std::wstring expectDocument;        // #! expect-document "<text>"
    // The host's steps, in order: the keys of `#! type …` and of the `>` keyDown/keyUp frames, `#! terminate` (the app
    // ends the composition: ITfContextOwnerCompositionServices::TerminateComposition) and `#! wait`.
    std::vector<Step> steps;

    static bool Load(const std::string& path, Transcript& out, std::string& error);
};

// Compares an actual frame body against an expected one, honoring `$any`.
bool Matches(const nlohmann::json& expected, const nlohmann::json& actual);

// Returns a copy of an expected `>` body with the host-dependent fields (see the file header) set to `$any`, so the
// literal golden still matches a real DLL's frames.
nlohmann::json NormalizeExpected(const nlohmann::json& expected);

// A one-line, human-readable form of a body, for failure messages.
std::string Brief(const nlohmann::json& body);

} // namespace aio::test
