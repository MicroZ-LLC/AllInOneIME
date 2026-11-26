import Foundation

/// A developer's recording of what a shell asked of a field's text-input API (IMK's `IMKTextInput` on the Mac) and what
/// the field answered, with the events each call came in (a key, a modifier change, the field activated or left): one
/// JSON object per line (JSONL, as the wire protocol's goldens are), so that a real app's session can become a host
/// profile or a scenario later (Tests/HostScenarios). The Mac's shell writes it (`IMKRecorder`), off unless a developer
/// turns it on; nothing in it leaves the Mac.
///
/// Typed text is never in it unless it was asked for in so many words (`keepsText`, the developer's own switch): what a
/// field holds or is given is recorded as its length (`{"len": n}`, UTF-16 units), and a key that types a character as
/// "text" and its length, without its key code or characters (`key(_:)`). Ranges, lengths, rects, the app's bundle id
/// and the names of the keys that type nothing (Return, ⌫, an arrow, a shortcut's letter with ⌘ or ⌃) are kept: they
/// are how the field behaves, not what was typed in it.
///
/// The lines (format `version` 1): `{"recording":"host-calls","v":1,"text":false}` first, then
/// `{"t":0.012,"event":"keyDown","key":"text","chars":{"len":1}}` and `{"t":0.013,"call":"selectedRange","answer":[3,0]}`,
/// `t` the seconds since the recording began; a range NSNotFound tells (no caret, nothing marked) is `null`.
public struct HostCallRecording: Sendable {
    public static let version = 1
    /// The format's name, in the first line.
    public static let format = "host-calls"

    /// Typed text is recorded as it is (else only its length).
    public let keepsText: Bool

    public init(keepsText: Bool) {
        self.keepsText = keepsText
    }

    /// A value a line records.
    public enum Field: Equatable, Sendable {
        /// Text the field holds or is given, or a key typed: its length only, unless the recording keeps text. Nil: none
        /// told (`null`).
        case text(String?)
        /// A range of UTF-16 offsets; one whose location is NSNotFound (or past `Int32.max`) is `null`.
        case range(location: Int, length: Int)
        case int(Int)
        case bool(Bool)
        /// A name that is no typed text: an app's bundle id, a key's name, a keyboard layout's id.
        case name(String)
        case rect(x: Double, y: Double, width: Double, height: Double)
        case point(x: Double, y: Double)
        /// Nothing told (`null`).
        case none
    }

    // MARK: Writing

    /// The recording's first line: its format, and whether it keeps text.
    public func header() -> String {
        Self.encode(["recording": Self.format, "v": Self.version, "text": keepsText])
    }

    /// A call of the field's API at `time` (seconds since the recording began), its arguments and answer in `fields`.
    public func call(_ name: String, at time: TimeInterval, _ fields: [String: Field] = [:]) -> String {
        line(kind: "call", name: name, time: time, fields)
    }

    /// An event the calls after it came in: "keyDown" (`key(_:)`'s fields), "flagsChanged", "activate", "deactivate"…
    public func event(_ name: String, at time: TimeInterval, _ fields: [String: Field] = [:]) -> String {
        line(kind: "event", name: name, time: time, fields)
    }

    /// A key down's fields: one that types text (a character, the space bar's excepted, with neither ⌘ nor ⌃ held) is
    /// `"key":"text"` and its length, its key code and characters only where the recording keeps text; any other key
    /// is its name (`Key.name`), code and modifiers, and a shortcut's characters ("v" of ⌘V). A dead key types too: as
    /// the Mac's key down tells it, it has no characters, with its modifiers or without them (the French ^, ⌥E).
    public func key(_ key: KeyEvent) -> [String: Field] {
        let modifiers = Self.modifierNames(key.modifiers)
        var fields: [String: Field] = ["mods": .name(modifiers.joined(separator: "+"))]
        if key.isRepeat { fields["repeat"] = .bool(true) }
        let shortcut = !key.modifiers.isDisjoint(with: [.command, .control])
        let typesText = key.key == .character && !shortcut
            && (key.isDeadKey || key.characters.unicodeScalars.allSatisfy(KeyEvent.isPrintable))
        if typesText {
            fields["key"] = .name("text")
            fields["chars"] = .text(key.characters)
            if keepsText { fields["code"] = .int(Int(key.keyCode)) }
        } else {
            fields["key"] = .name(key.key.name)
            fields["code"] = .int(Int(key.keyCode))
            // A shortcut's one ASCII character ("v" of ⌘V) by name; anything longer (a layout's or a made-up event's) as text.
            if shortcut, key.key == .character {
                let chars = key.charactersIgnoringModifiers
                let plain = chars.unicodeScalars.count == 1 && chars.unicodeScalars.allSatisfy(\.isASCII)
                fields["chars"] = plain ? .name(chars) : .text(chars)
            }
        }
        return fields
    }

    /// The modifiers held, by name ("shift", "command", "capsLock"), sides left out.
    public static func modifierNames(_ modifiers: Modifiers) -> [String] {
        let names: [(Modifiers, String)] = [(.shift, "shift"), (.control, "control"), (.option, "option"), (.command, "command"),
                                            (.capsLock, "capsLock"), (.function, "function")]
        return names.filter { modifiers.contains($0.0) }.map(\.1)
    }

    private func line(kind: String, name: String, time: TimeInterval, _ fields: [String: Field]) -> String {
        let milliseconds = max(time, 0) * 1000
        var object: [String: Any] = [kind: name, "t": milliseconds.isFinite ? milliseconds.rounded() / 1000 : 0]
        for (key, field) in fields { object[key] = value(field) }
        return Self.encode(object)
    }

    private func value(_ field: Field) -> Any {
        switch field {
        case let .text(text?):
            return keepsText ? text as Any : ["len": text.utf16.count]
        case .text(nil), .none:
            return NSNull()
        case let .range(location, length):
            let told = location >= 0 && location < Int(Int32.max) && length >= 0 && length < Int(Int32.max)
            return told ? [location, length] : NSNull()
        case let .int(number): return number
        case let .bool(flag): return flag
        case let .name(name): return name
        case let .rect(x, y, width, height):
            return [x, y, width, height].allSatisfy(\.isFinite) ? [x, y, width, height] : NSNull()
        case let .point(x, y): return x.isFinite && y.isFinite ? [x, y] : NSNull()
        }
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: Reading

    /// A JSON value of a line read back.
    public indirect enum Value: Equatable, Sendable {
        case null, bool(Bool), number(Double), string(String), array([Value]), object([String: Value])

        init(_ any: Any) {
            switch any {
            // Darwin's JSONSerialization gives a Boolean NSNumber for true and false, Linux's a Bool.
            case let flag as Bool where type(of: any) == Bool.self || String(describing: type(of: any)).hasSuffix("Boolean"):
                self = .bool(flag)
            case let number as NSNumber: self = .number(number.doubleValue)
            case let text as String: self = .string(text)
            case let list as [Any]: self = .array(list.map(Value.init))
            case let object as [String: Any]: self = .object(object.mapValues(Value.init))
            default: self = .null
            }
        }
    }

    /// A line read back: a call, an event or the header, its name, its time and its fields.
    public struct Line: Equatable, Sendable {
        public enum Kind: String, Sendable { case header, call, event }

        public var kind: Kind
        /// The call's or the event's name ("selectedRange", "keyDown"); the format's for the header.
        public var name: String
        public var time: TimeInterval?
        public var fields: [String: Value]

        /// A range field (`[location, length]`); nil where it is `null` or missing.
        public func range(_ key: String) -> Range<Int>? {
            guard case let .array(pair)? = fields[key], pair.count == 2, case let .number(location) = pair[0],
                  case let .number(length) = pair[1] else { return nil }
            guard let start = Int(exactly: location), let count = Int(exactly: length), start >= 0, count >= 0 else { return nil }
            let (end, overflow) = start.addingReportingOverflow(count)
            return overflow ? nil : start..<end
        }

        /// How long a text field is (UTF-16 units), whether the text was kept or only its length; nil where none was told.
        public func length(_ key: String) -> Int? {
            switch fields[key] {
            case let .string(text)?: text.utf16.count
            case let .object(object)?: object["len"].flatMap {
                if case let .number(length) = $0, let count = Int(exactly: length), count >= 0 { count } else { nil }
            }
            default: nil
            }
        }

        /// A text or name field as it was recorded; nil where only its length was (or nothing).
        public func string(_ key: String) -> String? {
            if case let .string(text)? = fields[key] { text } else { nil }
        }

        public func number(_ key: String) -> Double? {
            if case let .number(number)? = fields[key] { number } else { nil }
        }
    }

    /// `text`, one line of a recording, read back; nil where it isn't one.
    public static func parse(_ text: String) -> Line? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var fields = object.mapValues(Value.init)
        let time = fields.removeValue(forKey: "t").flatMap { if case let .number(seconds) = $0 { seconds } else { nil } }
        for kind in [Line.Kind.call, .event] {
            if case let .string(name)? = fields.removeValue(forKey: kind.rawValue) {
                return Line(kind: kind, name: name, time: time, fields: fields)
            }
        }
        guard case let .string(format)? = fields.removeValue(forKey: "recording") else { return nil }
        return Line(kind: .header, name: format, time: time, fields: fields)
    }
}
