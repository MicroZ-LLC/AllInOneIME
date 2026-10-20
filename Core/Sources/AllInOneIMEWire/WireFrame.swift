import Foundation

/// A frame on the wire (§2.2): a u32 little-endian body length, then that many bytes of UTF-8 JSON (one object). On a
/// Windows pipe in message mode a message is one frame, the prefix then redundant but kept, so that the same bytes go
/// over byte streams (the replay CLI, sockets in tests); transports that delimit calls themselves pass the body alone.
public enum WireFrame {
    /// The length prefix's size.
    public static let prefixSize = 4
    /// The largest body a client may send (DLL → engine).
    public static let clientLimit = 64 * 1024
    /// The largest body the engine may send (engine → DLL): a long answer committed in one frame.
    public static let engineLimit = 1024 * 1024
    /// The deepest a body's JSON may nest (§8): objects and arrays, the body itself one.
    public static let maxDepth = 16

    /// Why a frame was refused: both are fatal (§3), the connection closes.
    public enum Failure: Error, Equatable, Sendable {
        /// A bad length, invalid UTF-8 or JSON, or JSON nested deeper than `maxDepth`.
        case badFrame(String)
        /// Over the limit.
        case tooLarge(Int)

        public var code: WireErrorCode {
            switch self {
            case .badFrame: return .badFrame
            case .tooLarge: return .tooLarge
            }
        }

        /// For logs: never any of the frame's text.
        public var message: String {
            switch self {
            case let .badFrame(why): return why
            case let .tooLarge(size): return "frame of \(size) bytes is over the limit"
            }
        }
    }

    /// `body` with its length prefix.
    public static func frame(_ body: Data) -> Data {
        var out = Data(capacity: body.count + prefixSize)
        let n = UInt32(body.count)
        out.append(contentsOf: [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)])
        out.append(body)
        return out
    }

    /// The body of a message that is one frame (a pipe message): its prefix must equal its size minus 4, and the body
    /// be no longer than `limit`.
    public static func body(ofMessage message: Data, limit: Int) throws(Failure) -> Data {
        guard message.count >= prefixSize else { throw .badFrame("message of \(message.count) bytes has no length prefix") }
        let length = prefix(message)
        guard length <= limit else { throw .tooLarge(length) }
        guard length == message.count - prefixSize else {
            throw .badFrame("length prefix \(length) doesn't match the message's \(message.count - prefixSize) bytes")
        }
        return message.subdata(in: message.startIndex + prefixSize..<message.endIndex)
    }

    /// The length a prefix at the start of `data` (4 bytes at least) gives.
    static func prefix(_ data: Data) -> Int {
        let b = data.startIndex
        return Int(data[b]) | Int(data[b + 1]) << 8 | Int(data[b + 2]) << 16 | Int(data[b + 3]) << 24
    }

    /// Checks a body before it is read as a message: UTF-8, one JSON object, nested no deeper than `maxDepth`. (The JSON
    /// itself is checked as it is decoded.)
    public static func check(_ body: Data) throws(Failure) {
        guard isValidUTF8(body) else { throw .badFrame("body isn't valid UTF-8") }
        var depth = 0, inString = false, escaped = false, sawObject = false
        for byte in body {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x7B, 0x5B:  // { [
                if depth == 0 {
                    guard byte == 0x7B, !sawObject else { throw .badFrame("body isn't one JSON object") }
                    sawObject = true
                }
                depth += 1
                guard depth <= maxDepth else { throw .badFrame("JSON nested deeper than \(maxDepth)") }
            case 0x7D, 0x5D:  // } ]
                depth -= 1
                guard depth >= 0 else { throw .badFrame("unbalanced JSON") }
            case 0x20, 0x09, 0x0A, 0x0D:
                break
            default:
                guard depth > 0 else { throw .badFrame("body isn't one JSON object") }
            }
        }
        guard sawObject, depth == 0, !inString else { throw .badFrame("body isn't one JSON object") }
    }

    /// Strict UTF-8 (RFC 3629): no overlong forms, surrogates or code points past U+10FFFF.
    public static func isValidUTF8(_ data: Data) -> Bool {
        var i = data.startIndex
        let end = data.endIndex
        while i < end {
            let b0 = data[i]
            if b0 < 0x80 {
                i += 1
                continue
            }
            let count: Int, lower: UInt8, upper: UInt8
            switch b0 {
            case 0xC2...0xDF: (count, lower, upper) = (1, 0x80, 0xBF)
            case 0xE0: (count, lower, upper) = (2, 0xA0, 0xBF)
            case 0xE1...0xEC, 0xEE...0xEF: (count, lower, upper) = (2, 0x80, 0xBF)
            case 0xED: (count, lower, upper) = (2, 0x80, 0x9F)
            case 0xF0: (count, lower, upper) = (3, 0x90, 0xBF)
            case 0xF1...0xF3: (count, lower, upper) = (3, 0x80, 0xBF)
            case 0xF4: (count, lower, upper) = (3, 0x80, 0x8F)
            default: return false
            }
            guard end - i > count else { return false }
            guard (lower...upper).contains(data[i + 1]) else { return false }
            for k in 2..<(count + 1) where !(0x80...0xBF).contains(data[i + k]) { return false }
            i += count + 1
        }
        return true
    }

    /// Frames out of a byte stream (a socket, a file of frames): bytes in, whole bodies out.
    public struct Reader: Sendable {
        public let limit: Int
        private var buffer = Data()

        public init(limit: Int) { self.limit = limit }

        public mutating func append(_ bytes: Data) { buffer.append(bytes) }

        /// The next whole body, or nil until more bytes come.
        public mutating func next() throws(Failure) -> Data? {
            guard buffer.count >= prefixSize else { return nil }
            let length = prefix(buffer)
            guard length <= limit else { throw .tooLarge(length) }
            guard buffer.count >= prefixSize + length else { return nil }
            let start = buffer.startIndex + prefixSize
            let body = buffer.subdata(in: start..<start + length)
            buffer = buffer.subdata(in: start + length..<buffer.endIndex)
            return body
        }
    }
}

/// How long the fields of a message may be (§8), in UTF-16 units (`scopes`: entries). Over any: `badMessage`.
public enum FieldLimits {
    /// `key.text` and `key.textIgnoringModifiers`.
    public static let keyText = 64
    /// `ctx.before`.
    public static let before = 256
    /// `field.app`, `field.process` and `field.layout`.
    public static let app = 256
    public static let scopes = 32
    /// The most `welcome.limits.contextBefore` may be raised to.
    public static let maxContextBefore = 256
}
