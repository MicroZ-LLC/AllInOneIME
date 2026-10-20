// wiretest: the wire layer and the pipe client, with no TSF — so the wire half runs anywhere, including an SSH session
// on the service desktop. It checks:
//   1. WireJson: the canonical form of what the DLL sends (§1: defaults left out), UTF-16 offsets, and what the
//      decoder accepts and refuses (§2.2, §3, §6, §8, §9) without ever throwing.
//   2. PipeClient against FakeEngine: the §2.1 pipe, the server check, the handshake, and a keyDown request/response.
//      That half needs the interactive session (the DLL's §2.1 guard keeps it passive in session 0), so over SSH it
//      reports a skip.
//
// It is not the golden harness (that is tiptest, which drives real TSF).

#include <windows.h>

#include <cstdio>
#include <string>

#include <nlohmann/json.hpp>

#include "PipeClient.h"
#include "ProcessInfo.h"
#include "wire/Wire.h"
#include "test/common/FakeEngine.h"

using namespace aio;
using nlohmann::json;

namespace aio {
// The DLL's module/object-count symbols, which PipeClient and friends reference. In this exe there is no module.
HINSTANCE g_module = nullptr;
void DllAddRef() noexcept {}
void DllRelease() noexcept {}
LONG DllRefCount() noexcept { return 0; }
}

namespace {

int g_failures = 0;

void Check(bool ok, const char* what) {
    printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
    if (!ok) ++g_failures;
}

json Parsed(const std::string& body) {
    return json::parse(body, nullptr, false);
}

// A PipeEvents that records what the TSF thread would see.
struct Recorder : PipeEvents {
    bool connected = false;
    bool disconnected = false;
    wire::Welcome welcome;
    void OnPipeConnected(const wire::Welcome& w) override { connected = true; welcome = w; }
    void OnPipeDisconnected() override { disconnected = true; }
    void OnPipeMessage(const wire::EngineMessage&) override {}
    void OnPipeTimer(UINT_PTR) override {}
};

// Pumps the message loop for up to `ms`, so the pipe client's message-only window delivers its posts.
void Pump(DWORD ms) {
    ULONGLONG end = GetTickCount64() + ms;
    for (;;) {
        MSG msg;
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        LONGLONG left = (LONGLONG)end - (LONGLONG)GetTickCount64();
        if (left <= 0) break;
        MsgWaitForMultipleObjects(0, nullptr, FALSE, (DWORD)left, QS_ALLINPUT);
    }
}

void TestEncoders() {
    printf("encoders (canonical form, §1)\n");
    wire::KeyEvent k;
    k.id = 8; k.sid = 1; k.t = 1480; k.down = true;
    k.key.vk = 50; k.key.scan = 3; k.key.text = L"@"; k.key.textIgnoringModifiers = L"@";
    k.key.modifiers = wire::kShift | wire::kLeftShift;
    k.ctx.sel = {{3, 3}};
    k.ctx.before = L"hi ";
    Check(Parsed(wire::Encode(k)) ==
              json::parse(R"({"v":1,"id":8,"type":"keyDown","sid":1,"t":1480,"key":{"vk":50,"scan":3,"text":"@",)"
                          R"("textIgnoringModifiers":"@","modifiers":["shift","leftShift"]},"ctx":{"sel":[3,3],"before":"hi "}})"),
          "keyDown: §5.1's example, modifiers by name in bit order");

    wire::KeyEvent up;
    up.id = 10; up.sid = 1; up.down = false; up.key.vk = 16; up.key.scan = 42;
    up.ctx.sel = {{4, 4}}; up.ctx.before = L"hi "; up.ctx.comp = 1;
    Check(Parsed(wire::Encode(up)) ==
              json::parse(R"({"v":1,"id":10,"type":"keyUp","sid":1,"key":{"vk":16,"scan":42},"ctx":{"sel":[4,4],"before":"hi ","comp":1}})"),
          "keyUp: no t, no modifiers, no text when they hold their defaults; comp when composing");

    wire::KeyEvent sel;
    sel.id = 3; sel.sid = 2; sel.key.vk = 65; sel.key.isRepeat = true; sel.key.extended = true;
    sel.ctx.sel = {{0, 5}}; sel.ctx.selText = L"hello"; sel.ctx.selTruncated = true;
    const json s = Parsed(wire::Encode(sel));
    Check(s["key"].value("isRepeat", false) && s["key"].value("extended", false) && !s["key"].contains("scan") &&
              s["ctx"].value("selText", "") == "hello" && s["ctx"].value("selTruncated", false) &&
              !s["ctx"].contains("before"),
          "keyDown: isRepeat, extended, selText and selTruncated when set; scan 0 and empty before left out");

    wire::Open o;
    o.id = 2; o.sid = 1; o.field.app = "win:notepad.exe"; o.field.process = "notepad.exe"; o.field.scopes = {0};
    o.field.layout = "00000409";
    Check(Parsed(wire::Encode(o)) ==
              json::parse(R"({"v":1,"id":2,"type":"open","sid":1,"field":{"app":"win:notepad.exe","process":"notepad.exe","scopes":[0],"layout":"00000409"}})"),
          "open: §10's field; secure and readOnly left out when false");
    o.field.secure = true; o.field.readOnly = true; o.field.scopes = {};
    const json os = Parsed(wire::Encode(o));
    Check(os["field"].value("secure", false) && os["field"].value("readOnly", false) && !os["field"].contains("scopes"),
          "open: secure and readOnly when true, no scopes when there are none");

    wire::Focus f{3, 1, 1, std::nullopt};
    Check(Parsed(wire::Encode(f)) == json::parse(R"({"v":1,"id":3,"type":"focus","sid":1,"focus":1})"),
          "focus: no field unless re-sent for a changed one");

    wire::Caret c;
    c.id = 9; c.sid = 1; c.rect[0] = 812; c.rect[1] = 440; c.rect[2] = 9; c.rect[3] = 20; c.hwnd = 198940;
    Check(Parsed(wire::Encode(c)) == json::parse(R"({"v":1,"id":9,"type":"caret","sid":1,"rect":[812,440,9,20],"hwnd":198940})"),
          "caret: §6's example, exact left out");
    c.exact = false;
    Check(Parsed(wire::Encode(c)).value("exact", true) == false, "caret: exact:false for the window's box");

    wire::Applied a;
    a.id = 25; a.re = 22; a.ok = true; a.ctx = wire::FieldContext{};
    a.ctx->sel = {{9, 9}}; a.ctx->before = L"hi Hello.";
    Check(Parsed(wire::Encode(a)) == json::parse(R"({"v":1,"id":25,"re":22,"type":"applied","ok":true,"ctx":{"sel":[9,9],"before":"hi Hello."}})"),
          "applied: §7's example");
    wire::Applied refused;
    refused.id = 4; refused.re = 3; refused.ok = false; refused.reason = "notFocused";
    Check(Parsed(wire::Encode(refused)) == json::parse(R"({"v":1,"id":4,"re":3,"type":"applied","reason":"notFocused"})"),
          "applied: a refusal is ok:false (left out) with a reason, no ctx");

    wire::EndComposition e{5, 1, "timeout"};
    Check(Parsed(wire::Encode(e)) == json::parse(R"({"v":1,"id":5,"type":"endComposition","sid":1,"reason":"timeout"})"),
          "endComposition");

    // UTF-16 offsets (§1): text with a surrogate pair is 2 units in the document, 4 bytes on the wire.
    wire::KeyEvent emoji;
    emoji.id = 1; emoji.sid = 1; emoji.key.vk = 65;
    emoji.ctx.before = L"a\U0001F600";
    emoji.ctx.sel = {{3, 3}};
    const std::string emojiBody = wire::Encode(emoji);
    Check(emojiBody.find("a\xF0\x9F\x98\x80") != std::string::npos, "text: a surrogate pair is one UTF-8 character");
    Check(wire::ToUtf8(std::wstring(1, static_cast<wchar_t>(0xD800))) == "\xEF\xBF\xBD", "text: a lone surrogate is U+FFFD");
}

void TestDecoder() {
    printf("decoder (§2.2, §3, §6, §9)\n");
    wire::EngineMessage m;
    Check(wire::Decode(R"({"v":1,"id":6,"re":8,"type":"result","handled":true,"outputs":[{"op":"composition","text":"@","caret":1,)"
                       R"("segments":[{"from":0,"to":1,"style":"draft"}]},{"op":"panel","shown":true}]})", m) ==
                  wire::DecodeError::none &&
              m.type == wire::EngineType::result && m.result.handled && m.result.outputs.size() == 2,
          "result: §10's '@' result");
    if (m.result.outputs.size() == 2) {
        auto* comp = std::get_if<wire::CompositionOutput>(&m.result.outputs[0]);
        Check(comp && comp->text == L"@" && comp->caret == 1 && comp->segments.size() == 1 &&
                  comp->segments[0].style == wire::Style::draft,
              "composition output");
        auto* panel = std::get_if<wire::PanelOutput>(&m.result.outputs[1]);
        Check(panel && panel->shown, "panel output");
    }

    Check(wire::Decode(R"({"v":1,"id":2,"re":4,"type":"result"})", m) == wire::DecodeError::none && !m.result.handled &&
              m.result.outputs.empty(),
          "result: handled and outputs default to false and []");

    Check(wire::Decode(R"({"v":1,"id":3,"re":5,"type":"result","outputs":[{"op":"future","x":1},{"op":"commit","text":"x","afterKey":true,"deleteBefore":2}]})", m) ==
                  wire::DecodeError::none &&
              m.result.outputs.size() == 1 && std::get_if<wire::CommitOutput>(&m.result.outputs[0]) &&
              std::get<wire::CommitOutput>(m.result.outputs[0]).afterKey &&
              std::get<wire::CommitOutput>(m.result.outputs[0]).deleteBefore == 2,
          "an unknown op is skipped (§9); commit's afterKey and deleteBefore");

    Check(wire::Decode(R"({"v":1,"id":3,"re":5,"type":"result","outputs":[{"op":"composition","text":"ab","caret":2,"segments":[{"from":0,"to":2,"style":"sparkly"}]}]})", m) ==
                  wire::DecodeError::none &&
              std::get<wire::CompositionOutput>(m.result.outputs[0]).segments[0].style == wire::Style::raw,
          "an unknown style is raw (§6)");

    Check(wire::Decode(R"({"v":1,"id":20,"re":23,"type":"result","handled":true,"outputs":[{"op":"composition","text":"improve › helo","caret":14,"typed":"@improve helo"}]})", m) ==
                  wire::DecodeError::none &&
              std::get<wire::CompositionOutput>(m.result.outputs[0]).typed == std::optional<wire::Text>(L"@improve helo") &&
              std::get<wire::CompositionOutput>(m.result.outputs[0]).text.size() == 14,
          "composition: the draft as typed (spec notes), and the shown text with its one-unit '›'");
    Check(wire::Decode(R"({"v":1,"id":2,"re":4,"type":"result","outputs":[{"op":"composition","text":"@","caret":1}]})", m) ==
                  wire::DecodeError::none &&
              !std::get<wire::CompositionOutput>(m.result.outputs[0]).typed,
          "composition: no `typed` when it shows what was typed");
    Check(wire::Decode(R"({"v":1,"id":2,"re":4,"type":"result","outputs":[{"op":"composition","text":"i","typed":7}]})", m) ==
              wire::DecodeError::badMessage,
          "composition: a `typed` that isn't a string is a badMessage");

    Check(wire::Decode(R"({"v":1,"id":3,"re":5,"type":"result","outputs":[{"op":"composition","text":"😀","caret":2}]})", m) ==
                  wire::DecodeError::none &&
              std::get<wire::CompositionOutput>(m.result.outputs[0]).text.size() == 2,
          "text: an escaped surrogate pair is 2 UTF-16 units");

    Check(wire::Decode(R"({"v":1,"id":9,"type":"apply","sid":1,"focus":1,"outputs":[{"op":"commit","text":"Hello."}]})", m) ==
                  wire::DecodeError::none &&
              m.type == wire::EngineType::apply && m.sid == 1 && m.focus == 1 && m.result.outputs.size() == 1,
          "apply: §7's example");
    Check(wire::Decode(R"({"v":1,"id":9,"type":"apply","focus":1})", m) == wire::DecodeError::badMessage,
          "apply without sid: badMessage");

    Check(wire::Decode(R"({"v":1,"id":1,"re":1,"type":"welcome","version":1,"engine":"0.7.0","enginePid":3100,"capabilities":["keyUps"],"limits":{"contextBefore":1000,"selection":5}})", m) ==
                  wire::DecodeError::none &&
              m.welcome.version == 1 && m.welcome.enginePid == 3100 && m.welcome.limits.contextBefore == 256 &&
              m.welcome.limits.selection == 5 && m.welcome.capabilities.size() == 1,
          "welcome: limits read, contextBefore capped at 256 (§2.4)");
    Check(wire::Decode(R"({"v":1,"id":7,"type":"bye","reason":"update","retryMs":500})", m) == wire::DecodeError::none &&
              m.type == wire::EngineType::bye && m.retryMs.value_or(0) == 500,
          "bye: retryMs (§2.5)");
    Check(wire::Decode(R"({"v":1,"id":9,"re":4,"type":"error","code":"noSession","message":"..."})", m) ==
                  wire::DecodeError::none &&
              m.type == wire::EngineType::error && m.code == "noSession" && m.re.value_or(0) == 4,
          "error: code and re (§3)");
    Check(wire::Decode(R"({"v":1,"id":1,"type":"nonsense","x":[1,2]})", m) == wire::DecodeError::none &&
              m.type == wire::EngineType::unknown,
          "an unknown type decodes as unknown, for the DLL to ignore (§9)");

    Check(wire::Decode(R"({"v":1,"id":2,"type":"result"})", m) == wire::DecodeError::badMessage, "result without re: badMessage");
    Check(wire::Decode(R"({"v":1,"id":2,"re":1,"type":"result","handled":"yes"})", m) == wire::DecodeError::badMessage,
          "a field of the wrong type: badMessage");
    Check(wire::Decode(R"({"v":2,"id":2,"re":1,"type":"result"})", m) == wire::DecodeError::badMessage, "another version's frame: badMessage");
    Check(wire::Decode("{not json", m) == wire::DecodeError::badFrame, "not JSON: badFrame");
    Check(wire::Decode("[1,2]", m) == wire::DecodeError::badFrame, "not an object: badFrame");
    Check(wire::Decode("{\"v\":1,\"id\":1,\"type\":\"result\",\"re\":1,\"x\":\"\xC3\x28\"}", m) == wire::DecodeError::badFrame,
          "invalid UTF-8: badFrame (§8)");
    std::string deep = R"({"v":1,"id":1,"re":1,"type":"result","x":)";
    for (int i = 0; i < 17; ++i) deep += "[";
    for (int i = 0; i < 17; ++i) deep += "]";
    deep += "}";
    Check(wire::Decode(deep, m) == wire::DecodeError::badFrame, "nested deeper than 16: badFrame (§8)");

    // Framing (§2.2).
    const std::string body = R"({"v":1,"id":3,"type":"ping"})";
    const std::string framed = wire::Frame(body);
    std::string_view inner;
    Check(framed.size() == body.size() + 4 && static_cast<size_t>(static_cast<unsigned char>(framed[0])) == body.size() &&
              wire::Unframe(framed, inner) && std::string(inner) == body,
          "frame: a u32 little-endian length, then the body");
    Check(!wire::Unframe(framed.substr(0, framed.size() - 1), inner) && !wire::Unframe("ab", inner),
          "unframe: a prefix that isn't the message size minus 4 is refused");
}

void TestHandshake() {
    printf("pipe client handshake + keyDown\n");
    using namespace aio::test;
    Transcript t;
    // The PipeClient sends hello (id 1) on connect; this exe sends a keyDown (id 2) below.
    const char* lines[] = {
        R"(> {"v":1,"id":1,"type":"hello","versions":[1],"platform":"win","arch":"x64","client":"$any","pid":"$any","tid":"$any","capabilities":["allowForeground"]})",
        R"(< {"v":1,"id":1,"re":1,"type":"welcome","version":1,"engine":"$any","enginePid":"$any","capabilities":[],"limits":{"contextBefore":32,"selection":10002}})",
        R"(> {"v":1,"id":2,"type":"keyDown","sid":1,"key":{"vk":72,"scan":35,"text":"h","textIgnoringModifiers":"h"},"ctx":{"sel":[0,0]}})",
        R"(< {"v":1,"id":2,"re":2,"type":"result"})",
    };
    std::string tmp = std::string(getenv("TEMP") ? getenv("TEMP") : ".") + "\\wiretest-handshake.jsonl";
    FILE* f = fopen(tmp.c_str(), "wb");
    for (auto* l : lines) { fputs(l, f); fputs("\n", f); }
    fclose(f);
    std::string err;
    Check(Transcript::Load(tmp, t, err), "transcript loads");

    // This process's own pipe (AIO_TIP_PIPE), so the DLLs in the user's apps never meet the fake engine.
    const std::wstring pipeName = FakeEngine::RealPipeName(FakeEngine::CurrentUserSid()) + L"-wiretest-" +
                                  std::to_wstring(GetCurrentProcessId());
    SetEnvironmentVariableW(L"AIO_TIP_PIPE", pipeName.c_str());
    FakeEngine engine(t, pipeName);
    engine.Start();
    while (!engine.PipeReady()) Sleep(5);

    Recorder rec;
    PipeClient pipe(&rec);
    Check(pipe.Start(), "pipe client starts");

    // Wait for the welcome to reach us.
    ULONGLONG end = GetTickCount64() + 3000;
    while (!rec.connected && GetTickCount64() < end) Pump(50);
    Check(rec.connected, "connected (handshake succeeded, server check passed)");
    Check(rec.welcome.version == 1 && rec.welcome.limits.contextBefore == 32, "welcome limits received");

    // Send a keyDown and wait for the result.
    wire::KeyEvent k;
    k.sid = 1; k.down = true; k.t = 1000;
    k.key.vk = 72; k.key.scan = 35; k.key.text = L"h"; k.key.textIgnoringModifiers = L"h";
    k.ctx.sel = {{0, 0}};
    wire::EngineMessage response;
    auto outcome = pipe.Request([&k](uint32_t id) { k.id = id; return wire::Encode(k); }, 1000, response);
    Check(outcome == PipeClient::Outcome::response && response.type == wire::EngineType::result,
          "keyDown got a result");

    pipe.Stop();
    engine.Join();
    const auto& r = engine.Result();
    printf("  engine: %s\n", r.summary.c_str());
    for (const auto& n : r.notes) printf("    . %s\n", n.c_str());
    Check(r.ok, "fake engine saw the expected frames");
    DeleteFileA(tmp.c_str());
}

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0); // flush as we go, so a scheduled-task log shows progress
    // A hard watchdog, so the test can never hang a scheduled task.
    HANDLE wd = CreateThread(nullptr, 0, [](void*) -> DWORD {
        Sleep(60000);
        fprintf(stderr, "watchdog: timed out\n");
        ExitProcess(2);
    }, nullptr, 0, nullptr);
    if (wd) CloseHandle(wd);

    const auto& me = CurrentProcess();
    printf("session %lu, integrity 0x%lx\n", me.sessionId, me.integrity);

    TestEncoders();
    TestDecoder();
    const char* why = "";
    if (!MayConnect(&why)) {
        // §2.1/§8: in a service or session-0 context the DLL stays passive by design, so the pipe test can't run
        // here. This is a skip, not a failure; run the test in the interactive session (see README).
        printf("pipe client handshake + keyDown\n  [skip] this context may not connect: %s\n", why);
    } else {
        TestHandshake();
    }
    printf("\n%s (%d failures)\n", g_failures == 0 ? "PASS" : "FAIL", g_failures);
    return g_failures == 0 ? 0 : 1;
}
