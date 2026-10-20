import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation

/// The goldens (§10), as scenarios: what the client does. `GoldenWriter` runs each against the engine to write its
/// file (WIRE_WRITE_GOLDENS=1 `swift test --filter AllInOneIMEWireTests`); `WireGoldenTests` replays the files.
enum GoldenScenarios {
    static let fixture = "fixtures/improve-hello.json"

    static let all: [(name: String, write: @Sendable (URL) throws -> String)] = [
        ("notepad-improve", notepadImprove),
        ("notepad-improve-click", notepadImproveClick),
        ("secure-field", secureField),
        ("esc-mid-stream", escMidStream),
        ("blur-mid-stream", blurMidStream),
        ("terminated", terminated),
        ("focus-moves", focusMoves),
        ("focus-resent", focusResent),
        ("timeout-resync", timeoutResync),
        ("reconnect", reconnect),
        ("unknown-type", unknownType),
        ("limits", limits),
        ("settings", settings),
    ]

    /// Notepad, the handshake, "hi " and "@improve hello" up to its level two.
    static func improveHello(_ w: GoldenWriter) {
        w.hello()
        w.open(1)
        w.focus(1, serial: 1)
        w.comment("\"hi\" and a space: plain English passes through")
        w.type(1, "hi ")
        w.comment("Shift+2 types \"@\" after a space: a draft starts (after a letter, \"@\" would just be text)")
        w.shiftDown(1)
        w.keyDown(1, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.caret(1)
        w.shiftUp(1)
        w.t += 100
        w.comment("\"improve helo\" (a typo: \"hello\" would hide \"Hello.\", which only punctuates it): the command list")
        w.comment("narrows to improve while its name is typed (shown without the \"@\"), then the text after it")
        w.type(1, "improve helo", step: 200)
        w.comment("Return runs the command: level two, the draft converted while the versions stream in")
        w.enter(1)
    }

    static func notepadImprove(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "Notepad: \"hi \", then \"@improve helo\", Return, and the first version picked with 1 (§10).",
            "The provider's stream: \"Hello.\" / \"Hi there.\" / \"Hello!\" (fixtures/improve-hello.json).",
        ])
        improveHello(w)
        w.directive("run tasks")
        w.comment("1 picks the first version: it goes in and the panel closes")
        w.type(1, "1")
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func notepadImproveClick(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "The same pick made with the mouse (§10): the engine pushes the commit (apply) instead of returning it in a",
            "key's result, and the client answers with applied and the document after it.",
        ])
        improveHello(w)
        w.directive("run tasks")
        w.comment("The panel's rows: 0 the text as typed, then the versions. Row 1 is \"Hello.\"")
        w.directive("click row 1")
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func secureField(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "Password fields (§5.1, §8): the client sends no keys from them (#! keys: typed, not sent). A field that",
            "turns secure while a draft is pending (its input scope changed) gets the draft as typed, pushed.",
        ])
        w.hello()
        let password = WireField(app: "win:notepad.exe", process: "notepad.exe", secure: true, scopes: [31], layout: "00000409")
        w.open(1, field: password)
        w.focus(1, serial: 1)
        w.unsentKeys(1, "@improve")
        w.blur(1)
        w.comment("An ordinary field: a draft starts")
        w.open(2)
        w.focus(2, serial: 1)
        w.shiftDown(2)
        w.keyDown(2, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.shiftUp(2)
        w.type(2, "imp")
        w.comment("The field turns secure: the draft goes in as typed, and no more keys are sent")
        w.focus(2, serial: 1, field: password)
        w.unsentKeys(2, "x")
        w.blur(2)
        w.close(1)
        w.close(2)
        return w.text
    }

    static func escMidStream(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "Esc while the versions stream in (§7): an ordinary key. The request is cancelled and the draft comes back;",
            "what the stream sends later is dropped in the engine (its id no longer matches): no frames.",
        ])
        improveHello(w)
        w.directive("advance 150")
        w.comment("Esc: back to the draft")
        w.escape(1)
        w.directive("run tasks")
        w.comment("Esc again: the draft is given up")
        w.escape(1)
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func blurMidStream(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "Focus moves away while the versions stream in (§4, §7): blur's result carries the outputs (commitAll: the",
            "draft as typed goes in, the request stops), and nothing is pushed for that focus afterwards.",
        ])
        improveHello(w)
        w.directive("advance 150")
        w.blur(1)
        w.directive("run tasks")
        w.comment("Focused again: a fresh start")
        w.focus(1, serial: 2)
        w.type(1, "x")
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func terminated(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "The app ends our composition (§5.5, OnCompositionTerminated): what is pending goes in (commitAll), the",
            "commit replacing the range the composition covered.",
        ])
        w.hello()
        w.open(1)
        w.focus(1, serial: 1)
        w.shiftDown(1)
        w.keyDown(1, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.shiftUp(1)
        w.type(1, "improve hel")
        w.endComposition(1, reason: "terminated")
        w.comment("Typing goes on as plain text")
        w.type(1, "x")
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func focusMoves(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "The focus moves to another field mid-draft (§4, §5.5). TSF ends the composition before it moves the focus,",
            "so the client sends endComposition terminated first (the draft goes in as typed), then blur, which finds",
            "nothing left to commit.",
        ])
        w.hello()
        w.open(1)
        w.focus(1, serial: 1)
        w.shiftDown(1)
        w.keyDown(1, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.shiftUp(1)
        w.type(1, "improve hel")
        w.endComposition(1, reason: "terminated")
        w.blur(1)
        w.comment("The other field: plain typing")
        w.open(2)
        w.focus(2, serial: 1)
        w.type(2, "x")
        w.blur(2)
        w.close(1)
        w.close(2)
        w.expectDocument(1)
        return w.text
    }

    static func focusResent(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "focus re-sent while focused (§4): the layout changed mid-stream, so the client sends focus again with the new",
            "field and the same serial. Nothing is blurred or committed, the versions keep streaming, and the click's push",
            "carries that serial, so the client applies it.",
        ])
        improveHello(w)
        w.directive("advance 150")
        w.comment("A new keyboard layout under the same field: the same serial, the new field")
        let chineseLayout = WireField(app: "win:notepad.exe", process: "notepad.exe", scopes: [0], layout: "00000804")
        w.focus(1, serial: 1, field: chineseLayout)
        w.directive("run tasks")
        w.directive("click row 1")
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func timeoutResync(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "A key the client gave up on (§5.4): it ended its composition, leaving the draft as typed (composition.typed),",
            "passed the key to the app and dropped the late result, then sends endComposition timeout. The engine starts",
            "over and hides its panel, and sends no composition: an empty one would remove what the document kept.",
        ])
        w.hello()
        w.open(1)
        w.focus(1, serial: 1)
        w.shiftDown(1)
        w.keyDown(1, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.shiftUp(1)
        w.type(1, "im")
        w.comment("p: the engine answers, but after the client's 150 ms: the client typed p and drops the result")
        w.keyDown(1, vk: 0x50, scan: 0x19, text: "p", timedOut: true)
        w.t += 200
        w.endComposition(1, reason: "timeout")
        w.comment("Back in step: typing is plain text again")
        w.type(1, " x")
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func reconnect(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "The pipe breaks mid-draft (§2.5, §4): the engine closes the connection's sessions, with no outputs. The",
            "client ends its composition keeping the draft as typed (\"@imp\", not the \"imp\" shown), reconnects, says",
            "hello again (ids start over at 1 on both sides), re-opens its live context and focuses it with a new serial;",
            "session ids survive.",
        ])
        w.hello()
        w.open(1)
        w.focus(1, serial: 1)
        w.type(1, "hi ")
        w.shiftDown(1)
        w.keyDown(1, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.shiftUp(1)
        w.type(1, "imp")
        w.directive("disconnect")
        w.directive("connect")
        w.hello()
        w.open(1)
        w.focus(1, serial: 2)
        w.comment("The draft stayed as typed text: typing goes on plainly, and a new draft starts after a space")
        w.type(1, " ")
        w.shiftDown(1)
        w.keyDown(1, vk: 0x32, scan: 0x03, text: "@", modifiers: GoldenWriter.shift)
        w.shiftUp(1)
        w.escape(1)
        w.ping()
        w.blur(1)
        w.close(1)
        w.expectDocument(1)
        return w.text
    }

    static func unknownType(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "Forward compatibility (§9): an unknown type gets error unknownType and the connection goes on; unknown",
            "fields are ignored; an unknown session gets noSession, an unfocused one notFocused.",
        ])
        w.hello(capabilities: ["allowForeground", "somethingNew"])
        w.send(["type": "frobnicate", "sid": 1, "wobble": [1, 2, 3]])
        w.open(1)
        w.send(["type": "focus", "sid": 1, "focus": 1, "future": ["nested": true]])
        w.comment("A key with fields this version doesn't know: they are ignored")
        w.keyDown(1, vk: 0x48, scan: 0x23, text: "h", extra: ["isSystem": false, "pressure": .number(0.5)])
        w.t += 100
        w.comment("No such session; a session open but not focused")
        w.send(["type": "keyDown", "sid": 7, "t": .number(Double(w.t)), "key": ["vk": 73, "scan": 23, "text": "i"]])
        w.open(2)
        w.send(["type": "keyDown", "sid": 2, "t": .number(Double(w.t)), "key": ["vk": 73, "scan": 23, "text": "i"]])
        w.send(["type": "blur", "sid": 9])
        w.ping()
        w.blur(1)
        w.close(1)
        w.close(2)
        return w.text
    }

    /// A settings window (§12): the document, a change, one refused, a key (sent once, never back), a custom command; a
    /// client that didn't ask for the settings doesn't have them.
    static func settings(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: nil, directory: directory, header: [
            "A settings window (§12), Windows' Settings app: the settings as a document, one change at a time, a key and a",
            "custom command. The test's own config (fixtures/settings.json: in English) and keys in memory. The documents",
            "and messages are as the engine sends them, but for what is the engine's own (\"$any\"): where its config file",
            "is, where the jargon list goes by default, the interface languages it ships.",
        ])
        w.shown = { answer in
            guard answer["type"] == "settings", let document = answer["document"] else { return answer }
            return answer.setting("document", to: enginesOwn(document))
        }
        w.directive("settings fixtures/settings.json")
        w.hello(capabilities: ["settings"])
        w.comment("The settings as a document: sections of fields, for Windows (the Mac's own fields left out)")
        w.send(["type": "settingsGet"])
        w.comment("One change: saved, answered with the document, and every settings client told (this one too)")
        w.send(["type": "settingsSet", "field": "maxTokens", "value": 1500])
        w.comment("Refused, with why: out of its bounds; a field the Mac has and Windows doesn't; nothing changes")
        w.send(["type": "settingsSet", "field": "maxTokens", "value": 50])
        w.send(["type": "settingsSet", "field": "menuBarIcon", "value": false])
        w.comment("Null is a value: the base URL unset, the default applies (as it did: nothing changed, nobody told)")
        w.send(["type": "settingsSet", "field": "anthropic.baseURL", "value": .null])
        w.comment("Made on the document of an older revision (the settings changed since): stale, nothing changes")
        w.send(["type": "settingsSet", "field": "maxTokens", "value": 2000, "revision": 1])
        w.comment("On the revision now: taken")
        w.send(["type": "settingsSet", "field": "maxTokens", "value": 2000, "revision": 2])
        w.comment("A list as an edit of the one the window showed: \"Elsewhere\" (added since, as if by another window) stays")
        w.send(["type": "settingsSet", "field": "redaction.enabled", "value": true])
        w.send(["type": "settingsSet", "field": "redaction.customWords", "value": ["Acme", "Elsewhere"]])
        w.send(["type": "settingsSet", "field": "redaction.customWords", "value": ["Acme", "Mine"], "shown": ["Acme"]])
        w.comment("A key goes once, to the secret store; the document says only that it is saved, and its last 4")
        w.send(["type": "settingsAction", "field": "anthropic.key", "action": "setKey", "key": "sk-test-golden-0000-a1b2"])
        w.send(["type": "settingsAction", "field": "anthropic.key", "action": "removeKey"])
        w.comment("A custom command, with the editor's rules: saved, a name taken refused, deleted")
        w.send(["type": "settingsAction", "field": "commands.custom", "action": "save",
                "value": ["name": "polite", "type": "prompt", "prompt": "Make it polite"]])
        w.send(["type": "settingsAction", "field": "commands.custom", "action": "save",
                "value": ["name": "improve", "type": "prompt", "prompt": "Mine"]])
        w.send(["type": "settingsAction", "field": "commands.custom", "action": "delete", "item": "polite"])
        w.comment("A change without its value is no change: badMessage")
        w.send(["type": "settingsSet", "field": "maxTokens"])
        w.comment("A client that didn't ask for the settings (a text service's) doesn't have them")
        w.directive("connect")
        w.hello()
        w.send(["type": "settingsGet"])
        return w.text
    }

    /// A settings document with what is the engine's own left out ("$any"): the config file's path, the jargon list's
    /// default path, the interface languages it ships.
    static func enginesOwn(_ document: JSONValue) -> JSONValue {
        let own = ["configFile": "value", "jargonFile": "placeholder", "uiLanguage": "choices"]
        guard case let .array(sections)? = document["sections"] else { return document }
        return document.setting("sections", to: .array(sections.map { section in
            guard case let .array(fields)? = section["fields"] else { return section }
            return section.setting("fields", to: .array(fields.map { field in
                guard let key = field["id"]?.stringValue.flatMap({ own[$0] }), field[key] != nil else { return field }
                return field.setting(key, to: .any)
            }))
        }))
    }

    static func limits(_ directory: URL) throws -> String {
        let w = try GoldenWriter(fixture: fixture, directory: directory, header: [
            "Limits (§8): fields over their limit get badMessage (the connection goes on); more than 200 keys a second",
            "get limit (handled false, no work done); JSON nested deeper than 16 is a badFrame, and the connection closes.",
        ])
        w.hello()
        w.open(1)
        w.focus(1, serial: 1)
        w.comment("key.text over 64 units")
        w.send(["type": "keyDown", "sid": 1, "t": .number(Double(w.t)),
                "key": ["vk": 65, "scan": 30, "text": .string(String(repeating: "a", count: 65))]])
        w.comment("ctx.before over 256 units")
        w.send(["type": "keyDown", "sid": 1, "t": .number(Double(w.t)), "key": ["vk": 65, "scan": 30, "text": "a"],
                "ctx": ["sel": [300, 300], "before": .string(String(repeating: "b", count: 257))]])
        w.comment("field.scopes over 32 entries, field.app over 256 units")
        w.send(["type": "open", "sid": 2, "field": ["app": "win:x.exe", "scopes": .array((0..<33).map { .number(Double($0)) })]])
        w.send(["type": "open", "sid": 3, "field": ["app": .string("win:" + String(repeating: "x", count: 253))]])
        w.comment("A flood: 200 keys in the same instant are taken (these 2 above and 198 more), the next ones get limit")
        for _ in 0..<198 {
            w.send(["type": "keyUp", "sid": 1, "t": .number(Double(w.t)), "key": ["vk": 16, "scan": 42]])
        }
        w.send(["type": "keyUp", "sid": 1, "t": .number(Double(w.t)), "key": ["vk": 16, "scan": 42]])
        w.comment("A second later keys are taken again")
        w.directive("advance 1000")
        w.t += 1000
        w.keyDown(1, vk: 0x48, scan: 0x23, text: "h")
        w.comment("Nested deeper than 16: badFrame, and the engine closes the connection")
        var deep: JSONValue = []
        for _ in 0..<16 { deep = [deep] }
        w.send(["type": "ping", "deep": deep])
        w.directive("closed")
        return w.text
    }
}
