import Foundation

/// A JSON value, for the goldens: read, compared, written back.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case let .object(fields) = self { return fields[key] }
        return nil
    }

    public var intValue: Int? {
        if case let .number(n) = self, n == n.rounded(), abs(n) < 9_007_199_254_740_992 { return Int(n) }
        return nil
    }

    public var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    /// `self` with `key` set (an object's).
    public func setting(_ key: String, to value: JSONValue) -> JSONValue {
        guard case var .object(fields) = self else { return self }
        fields[key] = value
        return .object(fields)
    }

    public func removing(_ key: String) -> JSONValue {
        guard case var .object(fields) = self else { return self }
        fields[key] = nil
        return .object(fields)
    }

    /// The goldens' wildcard: matches any value (§10).
    public static let any = JSONValue.string("$any")

    /// Whether `actual` matches `self`, an expected value: the same JSON value, key order aside, "$any" matching
    /// anything (present). A mismatch's path otherwise.
    public func mismatch(_ actual: JSONValue, at path: String = "") -> String? {
        if self == .any { return nil }
        switch (self, actual) {
        case let (.object(expected), .object(got)):
            for key in Set(expected.keys).union(got.keys).sorted() {
                let at = path.isEmpty ? key : path + "." + key
                guard let e = expected[key] else { return "\(at): not expected" }
                guard let g = got[key] else { return "\(at): missing" }
                if let m = e.mismatch(g, at: at) { return m }
            }
            return nil
        case let (.array(expected), .array(got)):
            guard expected.count == got.count else { return "\(path): \(got.count) elements, expected \(expected.count)" }
            for (i, (e, g)) in zip(expected, got).enumerated() {
                if let m = e.mismatch(g, at: "\(path)[\(i)]") { return m }
            }
            return nil
        default:
            return self == actual ? nil : "\(path.isEmpty ? "frame" : path): \(actual.compact), expected \(compact)"
        }
    }

    /// One line, keys sorted.
    public var compact: String {
        guard let data = try? WireJSON.encode(self) else { return "?" }
        return String(decoding: data, as: UTF8.self)
    }

    public init(parsing text: String) throws {
        self = try WireJSON.decode(JSONValue.self, from: Data(text.utf8))
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n):
            if let i = intValue { try c.encode(i) } else { try c.encode(n) }
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}

/// A golden transcript (§10): what the client sends (`>`), what the engine answers or pushes (`<`), comments (`#`)
/// and fixture directives (`#!`), one a line.
public struct WireTranscript: Sendable {
    public enum Step: Equatable, Sendable {
        /// A frame from the client. Its `v`, left out in the goldens but for the handshake, is added when sent.
        case send(JSONValue, line: Int)
        /// A frame the engine must send next, compared as a JSON value ("$any" matches anything). A `v` left out isn't
        /// compared.
        case expect(JSONValue, line: Int)
        /// `#! …`
        case directive(String, line: Int)

        public var line: Int {
            switch self {
            case let .send(_, line), let .expect(_, line), let .directive(_, line): return line
            }
        }
    }

    public var steps: [Step]

    public struct ParseError: Error, CustomStringConvertible {
        public var line: Int
        public var message: String
        public var description: String { "line \(line): \(message)" }
    }

    public init(_ text: String) throws {
        var steps: [Step] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let number = index + 1
            if line.isEmpty { continue }
            if line.hasPrefix("#!") {
                // A directive ends where its comment starts: "#! run tasks   (the versions stream in)".
                var directive = String(line.dropFirst(2))
                if let paren = directive.range(of: "  (") { directive = String(directive[..<paren.lowerBound]) }
                steps.append(.directive(directive.trimmingCharacters(in: .whitespaces), line: number))
            } else if line.hasPrefix("#") {
                continue
            } else if line.hasPrefix(">") || line.hasPrefix("<") {
                let body = String(line.dropFirst())
                let value: JSONValue
                do {
                    value = try JSONValue(parsing: body)
                } catch {
                    throw ParseError(line: number, message: "not JSON")
                }
                steps.append(line.hasPrefix(">") ? .send(value, line: number) : .expect(value, line: number))
            } else {
                throw ParseError(line: number, message: "a line starts with >, <, # or #!")
            }
        }
        self.steps = steps
    }

    public init(contentsOf url: URL) throws {
        try self.init(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    /// The frame to send for a `>` line: with `v`, as every frame has it.
    public static func outgoing(_ value: JSONValue, version: Int = WireVersion.current) -> JSONValue {
        value["v"] == nil ? value.setting("v", to: .number(Double(version))) : value
    }

    /// Whether `actual` matches a `<` line's `expected` (its `v` compared only where the line has one).
    public static func mismatch(expected: JSONValue, actual: JSONValue) -> String? {
        let actual = expected["v"] == nil ? actual.removing("v") : actual
        return expected.mismatch(actual)
    }
}
