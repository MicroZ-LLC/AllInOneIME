import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation

/// A client's document as the DLL has it after applying outputs (§6), and the `ctx` it sends (§5.1): what makes a
/// golden's `>` lines what a real client would send.
struct Document {
    var text: [UInt16] = []
    var selection = 0..<0
    var composition: Range<Int>?
    /// The composition's text as typed (`composition.typed`), when that isn't what it shows.
    var typed: String?
    var contextBefore = 32

    var string: String { String(decoding: text, as: UTF16.self) }

    private mutating func replace(_ range: Range<Int>, with units: [UInt16]) {
        text.replaceSubrange(range, with: units)
    }

    private mutating func caret(_ at: Int) { selection = at..<at }

    mutating func apply(_ output: Output) {
        switch output {
        case let .commit(text, deleteBefore, deleteAfter, _):
            let base = composition ?? selection
            let range = max(0, base.lowerBound - deleteBefore)..<min(self.text.count, base.upperBound + deleteAfter)
            let units = Array(text.utf16)
            replace(range, with: units)
            composition = nil
            typed = nil
            caret(range.lowerBound + units.count)
        case let .composition(text, caret, _, typed):
            let range = composition ?? selection
            let units = Array(text.utf16)
            replace(range, with: units)
            self.typed = typed
            if units.isEmpty {
                composition = nil
                // The caret stays where it was in the text around (after the composition: moved back with it).
                let at = selection.lowerBound >= range.upperBound ? selection.lowerBound - range.count : range.lowerBound
                self.caret(at)
            } else {
                composition = range.lowerBound..<range.lowerBound + units.count
                self.caret(range.lowerBound + min(max(caret, 0), units.count))
            }
        case .panel, .allowForeground, .unknown:
            break
        }
    }

    /// The client ends the composition on its own (a key it gave up on, a lost engine: §2.5, §5.4): the text as typed
    /// stays, the caret after it.
    mutating func endKeepingTyped() {
        guard let range = composition else { return }
        let units = typed.map { Array($0.utf16) } ?? Array(text[range])
        replace(range, with: units)
        composition = nil
        typed = nil
        caret(range.lowerBound + units.count)
    }

    /// What the app does with a key it has: types the key's text over the selection.
    mutating func type(_ text: String) {
        let units = Array(text.utf16)
        let start = selection.lowerBound
        replace(selection, with: units)
        if let composition, composition.lowerBound >= selection.upperBound {
            self.composition = composition.lowerBound + units.count - selection.count..<composition.upperBound + units.count - selection.count
        }
        caret(start + units.count)
    }

    var context: FieldContext {
        let anchor = composition?.lowerBound ?? selection.lowerBound
        var start = max(0, anchor - contextBefore)
        if start > 0, start < text.count, UTF16.isTrailSurrogate(text[start]) { start += 1 }
        let selected = composition == nil && !selection.isEmpty ? String(decoding: text[selection], as: UTF16.self) : ""
        return FieldContext(sel: [selection.lowerBound, selection.upperBound],
                            before: String(decoding: text[start..<anchor], as: UTF16.self),
                            selText: selected, comp: composition?.count)
    }
}

/// Writes a golden by running a scenario against an in-process engine, as a client with a `Document` would: the `>`
/// lines with the context the document gives, the `<` lines the engine sends. Its outputs are applied to the document,
/// and each `apply` is answered with `applied`.
final class GoldenWriter {
    let engine: TestEngine
    private(set) var lines: [String] = []
    private var connection: ConnectionID?
    private var nextID: UInt32 = 1
    var t: UInt64 = 1000
    var documents: [UInt32: Document] = [:]
    /// Answer each `apply` with `applied` (else the scenario does).
    var answersApplies = true
    /// What a `<` line shows of an answer: all of it, unless a scenario leaves out what varies ("$any").
    var shown: (JSONValue) -> JSONValue = { $0 }
    private let directory: URL

    init(fixture: String?, directory: URL, inputLanguage: String = "english", header: [String]) throws {
        let fixtureValue = try fixture.map {
            try WireJSON.decode(ScriptedProvider.Fixture.self, from: Data(contentsOf: directory.appendingPathComponent($0)))
        }
        engine = TestEngine(fixture: fixtureValue, inputLanguage: Language(goldenName: inputLanguage) ?? .english)
        self.directory = directory
        lines += header.map { "# " + $0 }
        if let fixture { lines.append("#! provider \(fixture)") }
        lines.append("#! inputLanguage \(inputLanguage)")
        connection = engine.server.connect(WirePeer())
    }

    var text: String { lines.joined(separator: "\n") + "\n" }

    func comment(_ text: String) { lines.append("# " + text) }

    // MARK: Frames

    /// Sends a frame (its `id` the client's next unless given), writes it and what the engine answers, and acts on the
    /// answers as a client: a result's outputs go into the document of `sid`, an `apply` into its own.
    @discardableResult
    func send(_ fields: [String: JSONValue], id: UInt32? = nil, applyTo sid: UInt32? = nil,
              typed: String? = nil, timedOut: Bool = false) -> [JSONValue] {
        var value = JSONValue.object(fields)
        let frameID = id ?? nextID
        if id == nil { nextID += 1 }
        value = value.setting("id", to: .number(Double(frameID)))
        lines.append("> " + Self.line(value))
        let answers = engine.send(GoldenReplayer.outgoing(value), on: connection!).map {
            try! JSONValue(parsing: String(decoding: $0, as: UTF8.self))
        }
        var afterKey: [Output] = []
        for answer in answers {
            // The engine's version and process vary: "$any" (the spec's golden has them so).
            let written = answer["type"] == "welcome" ? answer.setting("engine", to: .any).setting("enginePid", to: .any)
                : answer.removing("v")
            lines.append("< " + Self.line(shown(written)))
            let frame = try! WireJSON.decode(EngineFrame.self, from: WireJSON.encode(answer))
            switch frame.message {
            case let .result(_, handled, outputs):
                guard let sid, !timedOut else { continue }
                for output in outputs {
                    if case let .commit(_, _, _, later) = output, later { afterKey.append(output) } else { documents[sid]?.apply(output) }
                }
                if !handled, let typed { documents[sid]?.type(typed) }
                for output in afterKey { documents[sid]?.apply(output) }
            case let .apply(applySid, _, outputs):
                pendingApplies.append((frame.id, applySid, outputs))
            default:
                break
            }
        }
        if timedOut, let sid {
            // The client gave up on the key: it ends the composition keeping the text as typed, and the app types the key.
            documents[sid]?.endKeepingTyped()
            if let typed { documents[sid]?.type(typed) }
        }
        answerApplies()
        return answers
    }

    private var pendingApplies: [(id: UInt32, sid: UInt32, outputs: [Output])] = []

    private func answerApplies() {
        guard answersApplies else { return }
        while !pendingApplies.isEmpty {
            let apply = pendingApplies.removeFirst()
            for output in apply.outputs { documents[apply.sid]?.apply(output) }
            var fields: [String: JSONValue] = ["type": "applied", "re": .number(Double(apply.id)), "ok": .bool(true)]
            if let ctx = documents[apply.sid]?.context { fields["ctx"] = Self.json(ctx) }
            send(fields)
        }
    }

    func directive(_ text: String) {
        lines.append("#! " + text)
        switch text {
        case "connect":
            connection = engine.server.connect(WirePeer())
            nextID = 1
        case "disconnect":
            engine.server.disconnect(connection!)
            engine.runUntilIdle()
            connection = nil
            // The client ends its compositions, keeping their text as typed (§2.5).
            for sid in documents.keys { documents[sid]?.endKeepingTyped() }
        case "closed":
            precondition(!engine.server.isOpen(connection!), "the engine didn't close the connection")
            engine.server.disconnect(connection!)
            connection = nil
        case let settings where settings.hasPrefix("settings "):
            let file = directory.appendingPathComponent(String(settings.dropFirst("settings ".count)))
            let config = String(decoding: try! Data(contentsOf: file), as: UTF8.self)
            precondition(engine.server.useTestSettings(config: config), "the test's settings couldn't be made")
        default:
            precondition(engine.server.perform(text, on: connection!), "unknown directive")
            engine.runUntilIdle()
            for data in engine.takePushes(for: connection!) {
                let answer = try! JSONValue(parsing: String(decoding: data, as: UTF8.self))
                lines.append("< " + Self.line(shown(answer.removing("v"))))
                if case let .apply(sid, _, outputs) = try! WireJSON.decode(EngineFrame.self, from: data).message {
                    pendingApplies.append((try! WireJSON.decode(EngineFrame.self, from: data).id, sid, outputs))
                }
            }
            answerApplies()
        }
    }

    // MARK: The protocol's frames

    func hello(capabilities: [String] = ["allowForeground"]) {
        send(["v": 1, "type": "hello", "versions": [1], "client": .any, "platform": "win", "arch": "x64",
              "pid": .any, "tid": .any, "capabilities": .array(capabilities.map(JSONValue.string))])
    }

    static let notepad = FieldInfo(app: "win:notepad.exe", process: "notepad.exe", scopes: [0], layout: "00000409")

    func open(_ sid: UInt32, field: FieldInfo = notepad) {
        if documents[sid] == nil { documents[sid] = Document() }
        send(["type": "open", "sid": .number(Double(sid)), "field": Self.json(field)])
    }

    func focus(_ sid: UInt32, serial: UInt32, field: FieldInfo? = nil) {
        var fields: [String: JSONValue] = ["type": "focus", "sid": .number(Double(sid)), "focus": .number(Double(serial))]
        if let field { fields["field"] = Self.json(field) }
        send(fields, applyTo: sid)
    }

    func blur(_ sid: UInt32) { send(["type": "blur", "sid": .number(Double(sid))], applyTo: sid) }

    func close(_ sid: UInt32) { send(["type": "close", "sid": .number(Double(sid))]) }

    func caret(_ sid: UInt32, rect: [Int] = [812, 440, 9, 20]) {
        send(["type": "caret", "sid": .number(Double(sid)), "rect": .array(rect.map { .number(Double($0)) }), "hwnd": .any])
    }

    func endComposition(_ sid: UInt32, reason: String) {
        send(["type": "endComposition", "sid": .number(Double(sid)), "reason": .string(reason)], applyTo: sid)
    }

    func ping() { send(["type": "ping"]) }

    /// `#! expect-document`: the client's document now, as the outputs left it (a Windows host checks its own against
    /// it; the engine's replayers skip it).
    func expectDocument(_ sid: UInt32) {
        lines.append("#! expect-document " + JSONValue.string(documents[sid]?.string ?? "").compact)
    }

    // MARK: Keys

    /// A key on a US layout: its virtual key, scan code and whether it takes Shift.
    static func usKey(_ c: Character) -> (vk: UInt16, scan: UInt16, shift: Bool)? {
        let letters: [UInt16] = [0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,
                                 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C]
        if let ascii = c.asciiValue, c.isLetter {
            let lower = ascii | 0x20
            return (UInt16(lower - 0x20), letters[Int(lower - 0x61)], c.isUppercase)
        }
        if let digit = c.wholeNumberValue, c.isASCII {
            return (UInt16(0x30 + digit), digit == 0 ? 0x0B : UInt16(digit + 1), false)
        }
        switch c {
        case " ": return (0x20, 0x39, false)
        case "@": return (0x32, 0x03, true)
        case "!": return (0x31, 0x02, true)
        case ".": return (0xBE, 0x34, false)
        case ",": return (0xBC, 0x33, false)
        case "?": return (0xBF, 0x35, true)
        case "-": return (0xBD, 0x0C, false)
        default: return nil
        }
    }

    static let shift: JSONValue = .array(["shift", "leftShift"])

    /// Types `text` on a US layout, a key-down for each character (Shift down and up around the shifted ones).
    func type(_ sid: UInt32, _ text: String, step: UInt64 = 100) {
        for c in text {
            guard let key = Self.usKey(c) else { fatalError("no key for \(c)") }
            if key.shift { shiftDown(sid) }
            keyDown(sid, vk: key.vk, scan: key.scan, text: String(c), modifiers: key.shift ? Self.shift : nil)
            if key.shift { shiftUp(sid) }
            t += step
        }
    }

    func keyDown(_ sid: UInt32, vk: UInt16, scan: UInt16, text: String? = nil, modifiers: JSONValue? = nil,
                 timedOut: Bool = false, extra: [String: JSONValue] = [:]) {
        var key: [String: JSONValue] = ["vk": .number(Double(vk)), "scan": .number(Double(scan))]
        if let text {
            key["text"] = .string(text)
            key["textIgnoringModifiers"] = .string(text)
        }
        if let modifiers { key["modifiers"] = modifiers }
        for (k, v) in extra { key[k] = v }
        var fields: [String: JSONValue] = ["type": "keyDown", "sid": .number(Double(sid)), "t": .number(Double(t)),
                                           "key": .object(key)]
        if let ctx = documents[sid]?.context { fields["ctx"] = Self.json(ctx) }
        let typed = text.flatMap { $0.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F } ? $0 : nil }
        send(fields, applyTo: sid, typed: typed, timedOut: timedOut)
    }

    func shiftDown(_ sid: UInt32) {
        keyDown(sid, vk: 0x10, scan: 0x2A, modifiers: Self.shift)
        t += 80
    }

    func shiftUp(_ sid: UInt32) {
        t += 70
        var fields: [String: JSONValue] = ["type": "keyUp", "sid": .number(Double(sid)), "t": .number(Double(t)),
                                           "key": ["vk": 16, "scan": 42]]
        if let ctx = documents[sid]?.context { fields["ctx"] = Self.json(ctx) }
        send(fields, applyTo: sid)
    }

    /// Keys typed in a field the client sends none from (a password field): `#! keys`, the app types them.
    func unsentKeys(_ sid: UInt32, _ text: String) {
        lines.append("#! keys \(text)")
        documents[sid]?.type(text)
        t += 100 * UInt64(text.count)
    }

    func enter(_ sid: UInt32) { keyDown(sid, vk: 0x0D, scan: 0x1C, text: "\r"); t += 100 }
    func escape(_ sid: UInt32) { keyDown(sid, vk: 0x1B, scan: 0x01, text: "\u{1B}"); t += 100 }
    func backspace(_ sid: UInt32) { keyDown(sid, vk: 0x08, scan: 0x0E, text: "\u{08}"); t += 100 }

    // MARK: Writing JSON

    static func json<T: Encodable>(_ value: T) -> JSONValue {
        try! WireJSON.decode(JSONValue.self, from: WireJSON.encode(value))
    }

    /// Keys in the spec's order (§10): the envelope first, then each message's own fields as the spec lists them.
    static let keyOrder = [
        "v", "id", "re", "type", "op", "sid", "focus", "ok", "t", "key", "ctx", "vk", "scan", "extended", "text",
        "textIgnoringModifiers", "isDeadKey", "isRepeat", "modifiers", "caret", "segments", "from", "to", "style",
        "deleteBefore", "deleteAfter", "afterKey", "sel", "before", "selText", "selTruncated", "comp", "handled", "outputs",
        "shown", "field", "app", "process", "secure", "readOnly", "scopes", "layout", "rect", "hwnd", "exact", "reason",
        "code", "message", "versions", "client", "platform", "arch", "pid", "tid", "version", "engine", "enginePid",
        "capabilities", "limits", "contextBefore", "selection", "retryMs", "directive",
        "action", "item", "value", "revision", "problem", "document",
    ]

    static func line(_ value: JSONValue) -> String {
        switch value {
        case let .object(fields):
            let rank = Dictionary(uniqueKeysWithValues: keyOrder.enumerated().map { ($0.element, $0.offset) })
            let keys = fields.keys.sorted { (rank[$0] ?? Int.max, $0) < (rank[$1] ?? Int.max, $1) }
            return "{" + keys.map { string($0) + ":" + line(fields[$0]!) }.joined(separator: ",") + "}"
        case let .array(items):
            return "[" + items.map(line).joined(separator: ",") + "]"
        default:
            return value.compact
        }
    }

    private static func string(_ s: String) -> String { JSONValue.string(s).compact }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
