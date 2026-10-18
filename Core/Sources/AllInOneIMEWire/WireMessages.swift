import AllInOneIMECore
import Foundation

// The wire protocol's messages (docs/wire-protocol-v1.md): what a client (the Windows TSF DLL, later Android's JNI layer
// and the C ABI) and the engine send each other, as JSON bodies. Each body is one object: the envelope (`v`, `id`,
// `type`, `sid`, `re`) and the type's own fields, side by side. Written in canonical form (§1): keys sorted, an optional
// field that holds its default (`false`, `[]`, nil, 0, "") left out; read either way, unknown fields ignored, an unknown
// type kept as `.unknown(type)` (§9).

/// The protocol's versions (`hello.versions`, `welcome.version`).
public enum WireVersion {
    /// The highest this build speaks.
    public static let current = 1
    /// Every version this build speaks, oldest first: the current one and the one before it, once there is one (§9).
    public static let supported = [1]
}

// MARK: - Fields

/// The text field a session is (§4): `open`'s and `focus`'s `field`.
public struct FieldInfo: Codable, Equatable, Sendable {
    /// `win:<exe>`, or `win:<AUMID>` for packaged apps. The Windows engine derives it from the client's process.
    public var app: String
    /// The process's executable name.
    public var process: String
    /// A password, PIN or numeric-password field: the DLL sends no keys from it.
    public var secure: Bool
    public var readOnly: Bool
    /// The raw input scopes (`GUID_PROP_INPUTSCOPE`).
    public var scopes: [Int]
    /// The keyboard layout's KLID ("00000409").
    public var layout: String

    public init(app: String = "", process: String = "", secure: Bool = false, readOnly: Bool = false,
                scopes: [Int] = [], layout: String = "") {
        self.app = app
        self.process = process
        self.secure = secure
        self.readOnly = readOnly
        self.scopes = scopes
        self.layout = layout
    }

    enum CodingKeys: String, CodingKey { case app, process, secure, readOnly, scopes, layout }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        process = try c.decodeIfPresent(String.self, forKey: .process) ?? ""
        secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? false
        readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        scopes = try c.decodeIfPresent([Int].self, forKey: .scopes) ?? []
        layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeUnlessDefault(app, forKey: .app)
        try c.encodeUnlessDefault(process, forKey: .process)
        try c.encodeUnlessDefault(secure, forKey: .secure)
        try c.encodeUnlessDefault(readOnly, forKey: .readOnly)
        try c.encodeUnlessDefault(scopes, forKey: .scopes)
        try c.encodeUnlessDefault(layout, forKey: .layout)
    }
}

/// The document around the caret when a key is sent (§5.1 `ctx`, and `applied`'s). Offsets in UTF-16 units.
public struct FieldContext: Codable, Equatable, Sendable {
    /// The selection `[start, end]` in absolute ACP; nil when unknown.
    public var sel: [Int]?
    /// Up to `limits.contextBefore` units before the selection start, or before our composition if one exists.
    public var before: String
    /// The selected text, for a non-empty selection, capped at `limits.selection`.
    public var selText: String
    /// `selText` was cut off.
    public var selTruncated: Bool
    /// The length of our composition as the document has it now; nil with no composition.
    public var comp: Int?

    public init(sel: [Int]? = nil, before: String = "", selText: String = "", selTruncated: Bool = false, comp: Int? = nil) {
        self.sel = sel
        self.before = before
        self.selText = selText
        self.selTruncated = selTruncated
        self.comp = comp
    }

    /// `sel` as a range, when it is one.
    public var selection: Range<Int>? {
        guard let sel, sel.count == 2, sel[0] >= 0, sel[1] >= sel[0] else { return nil }
        return sel[0]..<sel[1]
    }

    enum CodingKeys: String, CodingKey { case sel, before, selText, selTruncated, comp }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sel = try c.decodeIfPresent([Int].self, forKey: .sel)
        before = try c.decodeIfPresent(String.self, forKey: .before) ?? ""
        selText = try c.decodeIfPresent(String.self, forKey: .selText) ?? ""
        selTruncated = try c.decodeIfPresent(Bool.self, forKey: .selTruncated) ?? false
        comp = try c.decodeIfPresent(Int.self, forKey: .comp)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sel, forKey: .sel)
        try c.encodeUnlessDefault(before, forKey: .before)
        try c.encodeUnlessDefault(selText, forKey: .selText)
        try c.encodeUnlessDefault(selTruncated, forKey: .selTruncated)
        if let comp, comp != 0 { try c.encode(comp, forKey: .comp) }
    }
}

/// A key as a client sends it (§5.1 `key`). The Windows DLL sends the raw `vk`, `scan` and `extended`, and the engine
/// works out `Key` and the usage (`WindowsKeyCodes`); other clients send `key` and `usage` instead. With both, the raw
/// values win.
public struct WireKey: Codable, Equatable, Sendable {
    /// `wParam`.
    public var vk: UInt16?
    /// `lParam` bits 16–23.
    public var scan: UInt16?
    /// `lParam` bit 24.
    public var extended: Bool
    /// What the key types (`ToUnicodeEx`); for a dead key, its accent.
    public var text: String
    /// The same with Ctrl and Alt cleared and Shift kept; nil: as `text`.
    public var textIgnoringModifiers: String?
    public var isDeadKey: Bool
    /// `lParam` bit 30.
    public var isRepeat: Bool
    /// `Modifiers`' names, side bits included (`GetKeyState`).
    public var modifiers: Modifiers
    /// Other clients': the key by name, and its USB HID usage.
    public var key: Key?
    public var usage: UInt16?

    public init(vk: UInt16? = nil, scan: UInt16? = nil, extended: Bool = false, text: String = "",
                textIgnoringModifiers: String? = nil, isDeadKey: Bool = false, isRepeat: Bool = false,
                modifiers: Modifiers = [], key: Key? = nil, usage: UInt16? = nil) {
        self.vk = vk
        self.scan = scan
        self.extended = extended
        self.text = text
        self.textIgnoringModifiers = textIgnoringModifiers
        self.isDeadKey = isDeadKey
        self.isRepeat = isRepeat
        self.modifiers = modifiers
        self.key = key
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case vk, scan, extended, text, textIgnoringModifiers, isDeadKey, isRepeat, modifiers, key, usage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vk = try c.decodeIfPresent(UInt16.self, forKey: .vk)
        scan = try c.decodeIfPresent(UInt16.self, forKey: .scan)
        extended = try c.decodeIfPresent(Bool.self, forKey: .extended) ?? false
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        textIgnoringModifiers = try c.decodeIfPresent(String.self, forKey: .textIgnoringModifiers)
        isDeadKey = try c.decodeIfPresent(Bool.self, forKey: .isDeadKey) ?? false
        isRepeat = try c.decodeIfPresent(Bool.self, forKey: .isRepeat) ?? false
        modifiers = try c.decodeIfPresent(Modifiers.self, forKey: .modifiers) ?? []
        key = try c.decodeIfPresent(Key.self, forKey: .key)
        usage = try c.decodeIfPresent(UInt16.self, forKey: .usage)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(vk, forKey: .vk)
        try c.encodeIfPresent(scan, forKey: .scan)
        try c.encodeUnlessDefault(extended, forKey: .extended)
        try c.encodeUnlessDefault(text, forKey: .text)
        if let textIgnoringModifiers, !textIgnoringModifiers.isEmpty {
            try c.encode(textIgnoringModifiers, forKey: .textIgnoringModifiers)
        }
        try c.encodeUnlessDefault(isDeadKey, forKey: .isDeadKey)
        try c.encodeUnlessDefault(isRepeat, forKey: .isRepeat)
        if !modifiers.isEmpty { try c.encode(modifiers, forKey: .modifiers) }
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(usage, forKey: .usage)
    }

    /// The virtual keys of the modifier keys (Shift, Ctrl, Alt, the Windows keys, each side's): their downs and ups
    /// are modifier changes (§5.2).
    public static func isModifier(vk: UInt16) -> Bool {
        (0x10...0x12).contains(vk) || vk == 0x5B || vk == 0x5C || (0xA0...0xA5).contains(vk)
    }
}

// MARK: - Outputs

/// A stretch of a composition and how it is shown (§6 `segments`).
public struct Segment: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int
    /// `raw`, `draft`, `converted` or `target` (`Segment.Style`); unknown ones show as `raw`.
    public var style: String

    public init(from: Int, to: Int, style: String) {
        self.from = from
        self.to = to
        self.style = style
    }

    public enum Style {
        public static let raw = "raw"
        public static let draft = "draft"
        public static let converted = "converted"
        public static let target = "target"
    }
}

/// One thing for the client to do to the document (§6), in `result.outputs` and `apply.outputs`.
public enum Output: Equatable, Sendable {
    /// Replace our composition (else the selection), extended by `deleteBefore` / `deleteAfter` units, with `text`;
    /// the composition ends. `afterKey`: once the app has had the key (the Composer's `commitAfterKey`).
    case commit(text: String, deleteBefore: Int = 0, deleteAfter: Int = 0, afterKey: Bool = false)
    /// Our composition's text, caret (UTF-16) and styled stretches; empty text ends it.
    case composition(text: String, caret: Int = 0, segments: [Segment] = [])
    /// The engine is (or no longer is) showing UI anchored at the caret: report `caret` while it is.
    case panel(shown: Bool)
    /// `AllowSetForegroundWindow(enginePid)`, for clients that announced `allowForeground`.
    case allowForeground
    /// An op this version doesn't know: skipped (§9).
    case unknown(op: String)

    public var op: String {
        switch self {
        case .commit: return "commit"
        case .composition: return "composition"
        case .panel: return "panel"
        case .allowForeground: return "allowForeground"
        case let .unknown(op): return op
        }
    }
}

extension Output: Codable {
    enum CodingKeys: String, CodingKey { case op, text, deleteBefore, deleteAfter, afterKey, caret, segments, shown }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(String.self, forKey: .op)
        switch op {
        case "commit":
            self = .commit(text: try c.decode(String.self, forKey: .text),
                           deleteBefore: try c.decodeIfPresent(Int.self, forKey: .deleteBefore) ?? 0,
                           deleteAfter: try c.decodeIfPresent(Int.self, forKey: .deleteAfter) ?? 0,
                           afterKey: try c.decodeIfPresent(Bool.self, forKey: .afterKey) ?? false)
        case "composition":
            self = .composition(text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
                                caret: try c.decodeIfPresent(Int.self, forKey: .caret) ?? 0,
                                segments: try c.decodeIfPresent([Segment].self, forKey: .segments) ?? [])
        case "panel":
            self = .panel(shown: try c.decodeIfPresent(Bool.self, forKey: .shown) ?? false)
        case "allowForeground":
            self = .allowForeground
        default:
            self = .unknown(op: op)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(op, forKey: .op)
        switch self {
        case let .commit(text, deleteBefore, deleteAfter, afterKey):
            try c.encode(text, forKey: .text)
            try c.encodeUnlessDefault(deleteBefore, forKey: .deleteBefore)
            try c.encodeUnlessDefault(deleteAfter, forKey: .deleteAfter)
            try c.encodeUnlessDefault(afterKey, forKey: .afterKey)
        case let .composition(text, caret, segments):
            // Its text is the composition itself: written even when empty (that ends it).
            try c.encode(text, forKey: .text)
            try c.encodeUnlessDefault(caret, forKey: .caret)
            try c.encodeUnlessDefault(segments, forKey: .segments)
        case let .panel(shown):
            // Its one field: written either way, as `applied`'s `ok`.
            try c.encode(shown, forKey: .shown)
        case .allowForeground, .unknown:
            break
        }
    }
}

// MARK: - Errors

/// An `error` frame's code (§3). Unknown codes are kept as they came.
public struct WireErrorCode: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
    public var description: String { rawValue }

    /// Bad length or invalid UTF-8/JSON: fatal, the sender closes.
    public static let badFrame = WireErrorCode(rawValue: "badFrame")
    /// A frame over the limit: fatal.
    public static let tooLarge = WireErrorCode(rawValue: "tooLarge")
    /// No common version: fatal.
    public static let unsupportedVersion = WireErrorCode(rawValue: "unsupportedVersion")
    public static let unknownType = WireErrorCode(rawValue: "unknownType")
    /// A required field missing or of the wrong type, or a field over its limit (§8).
    public static let badMessage = WireErrorCode(rawValue: "badMessage")
    public static let noSession = WireErrorCode(rawValue: "noSession")
    public static let notFocused = WireErrorCode(rawValue: "notFocused")
    /// A rate or count exceeded.
    public static let limit = WireErrorCode(rawValue: "limit")
    public static let `internal` = WireErrorCode(rawValue: "internal")

    /// The codes after which the connection closes.
    public var isFatal: Bool { self == .badFrame || self == .tooLarge || self == .unsupportedVersion }
}

// MARK: - Client → engine

/// `hello` (§2.4): its shape never changes.
public struct Hello: Codable, Equatable, Sendable {
    public var versions: [Int]
    /// "tip/0.7.0"
    public var client: String
    /// "win", "android" …
    public var platform: String
    public var arch: String
    public var pid: UInt32?
    public var tid: UInt32?
    public var capabilities: [String]

    public init(versions: [Int] = WireVersion.supported, client: String, platform: String = "win", arch: String = "x64",
                pid: UInt32? = nil, tid: UInt32? = nil, capabilities: [String] = []) {
        self.versions = versions
        self.client = client
        self.platform = platform
        self.arch = arch
        self.pid = pid
        self.tid = tid
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey { case versions, client, platform, arch, pid, tid, capabilities }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        versions = try c.decode([Int].self, forKey: .versions)
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? ""
        arch = try c.decodeIfPresent(String.self, forKey: .arch) ?? ""
        pid = try c.decodeIfPresent(UInt32.self, forKey: .pid)
        tid = try c.decodeIfPresent(UInt32.self, forKey: .tid)
        capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(versions, forKey: .versions)
        try c.encode(client, forKey: .client)
        try c.encode(platform, forKey: .platform)
        try c.encode(arch, forKey: .arch)
        try c.encodeIfPresent(pid, forKey: .pid)
        try c.encodeIfPresent(tid, forKey: .tid)
        try c.encode(capabilities, forKey: .capabilities)
    }

    /// The client capability for the `allowForeground` op (§9).
    public static let allowForeground = "allowForeground"
}

/// `keyDown` and `keyUp` (§5.1).
public struct KeyFrame: Codable, Equatable, Sendable {
    public var sid: UInt32
    /// `GetTickCount64()` in ms at the event: consistent within a connection.
    public var t: UInt64
    public var key: WireKey
    public var ctx: FieldContext?

    public init(sid: UInt32, t: UInt64, key: WireKey, ctx: FieldContext? = nil) {
        self.sid = sid
        self.t = t
        self.key = key
        self.ctx = ctx
    }
}

/// What a client sends (§3–§7). Each is a request (`hello`, `keyDown`, `keyUp`, `blur`, `endComposition`, `ping`), a
/// response (`applied`), or a notification.
public enum ClientMessage: Equatable, Sendable {
    case hello(Hello)
    case open(sid: UInt32, field: FieldInfo)
    /// `focus`: a serial per session, higher with each focus; re-sent with a new `field` while focused.
    case focus(sid: UInt32, focus: UInt32, field: FieldInfo?)
    case blur(sid: UInt32)
    case close(sid: UInt32)
    case keyDown(KeyFrame)
    case keyUp(KeyFrame)
    /// "terminated" (`OnCompositionTerminated`) or "timeout" (§5.4).
    case endComposition(sid: UInt32, reason: String)
    case ping
    /// The caret's rectangle `[x, y, width, height]` in physical screen pixels (§6).
    case caret(sid: UInt32, rect: [Int], hwnd: UInt64?, exact: Bool)
    /// The answer to the engine's `apply` `re`: `ok`, or why not (`reason`), and the document after it.
    case applied(re: UInt32, ok: Bool, reason: String?, ctx: FieldContext?)
    /// A type this version doesn't know.
    case unknown(type: String)

    public var type: String {
        switch self {
        case .hello: return "hello"
        case .open: return "open"
        case .focus: return "focus"
        case .blur: return "blur"
        case .close: return "close"
        case .keyDown: return "keyDown"
        case .keyUp: return "keyUp"
        case .endComposition: return "endComposition"
        case .ping: return "ping"
        case .caret: return "caret"
        case .applied: return "applied"
        case let .unknown(type): return type
        }
    }

    /// The session it is for, if any.
    public var sid: UInt32? {
        switch self {
        case let .open(sid, _), let .focus(sid, _, _), let .blur(sid), let .close(sid), let .endComposition(sid, _),
             let .caret(sid, _, _, _):
            return sid
        case let .keyDown(frame), let .keyUp(frame):
            return frame.sid
        case .hello, .ping, .applied, .unknown:
            return nil
        }
    }

    /// Whether the engine answers it (§3): a request.
    public var isRequest: Bool {
        switch self {
        case .hello, .keyDown, .keyUp, .blur, .endComposition, .ping: return true
        case .open, .focus, .close, .caret, .applied, .unknown: return false
        }
    }
}

/// A client's frame: the envelope and its message.
public struct ClientFrame: Equatable, Sendable {
    public var v: Int
    public var id: UInt32
    public var message: ClientMessage

    public init(v: Int = WireVersion.current, id: UInt32, _ message: ClientMessage) {
        self.v = v
        self.id = id
        self.message = message
    }
}

extension ClientFrame: Codable {
    enum CodingKeys: String, CodingKey {
        case v, id, type, sid, re, field, focus, t, key, ctx, reason, rect, hwnd, exact, ok
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 0
        id = try c.decode(UInt32.self, forKey: .id)
        let type = try c.decode(String.self, forKey: .type)
        func sid() throws -> UInt32 { try c.decode(UInt32.self, forKey: .sid) }
        switch type {
        case "hello":
            message = .hello(try Hello(from: decoder))
        case "open":
            message = .open(sid: try sid(), field: try c.decodeIfPresent(FieldInfo.self, forKey: .field) ?? FieldInfo())
        case "focus":
            message = .focus(sid: try sid(), focus: try c.decodeIfPresent(UInt32.self, forKey: .focus) ?? 0,
                             field: try c.decodeIfPresent(FieldInfo.self, forKey: .field))
        case "blur":
            message = .blur(sid: try sid())
        case "close":
            message = .close(sid: try sid())
        case "keyDown", "keyUp":
            let frame = KeyFrame(sid: try sid(), t: try c.decodeIfPresent(UInt64.self, forKey: .t) ?? 0,
                                 key: try c.decode(WireKey.self, forKey: .key),
                                 ctx: try c.decodeIfPresent(FieldContext.self, forKey: .ctx))
            message = type == "keyDown" ? .keyDown(frame) : .keyUp(frame)
        case "endComposition":
            message = .endComposition(sid: try sid(), reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "")
        case "ping":
            message = .ping
        case "caret":
            message = .caret(sid: try sid(), rect: try c.decode([Int].self, forKey: .rect),
                             hwnd: try c.decodeIfPresent(UInt64.self, forKey: .hwnd),
                             exact: try c.decodeIfPresent(Bool.self, forKey: .exact) ?? true)
        case "applied":
            message = .applied(re: try c.decode(UInt32.self, forKey: .re), ok: try c.decode(Bool.self, forKey: .ok),
                               reason: try c.decodeIfPresent(String.self, forKey: .reason),
                               ctx: try c.decodeIfPresent(FieldContext.self, forKey: .ctx))
        default:
            message = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(message.type, forKey: .type)
        try c.encodeIfPresent(message.sid, forKey: .sid)
        switch message {
        case let .hello(hello):
            try hello.encode(to: encoder)
        case let .open(_, field):
            try c.encode(field, forKey: .field)
        case let .focus(_, focus, field):
            try c.encode(focus, forKey: .focus)
            try c.encodeIfPresent(field, forKey: .field)
        case let .keyDown(frame), let .keyUp(frame):
            try c.encode(frame.t, forKey: .t)
            try c.encode(frame.key, forKey: .key)
            try c.encodeIfPresent(frame.ctx, forKey: .ctx)
        case let .endComposition(_, reason):
            try c.encode(reason, forKey: .reason)
        case let .caret(_, rect, hwnd, exact):
            try c.encode(rect, forKey: .rect)
            try c.encodeIfPresent(hwnd, forKey: .hwnd)
            if !exact { try c.encode(false, forKey: .exact) }
        case let .applied(re, ok, reason, ctx):
            try c.encode(re, forKey: .re)
            try c.encode(ok, forKey: .ok)
            try c.encodeIfPresent(reason, forKey: .reason)
            try c.encodeIfPresent(ctx, forKey: .ctx)
        case .blur, .close, .ping, .unknown:
            break
        }
    }
}

// MARK: - Engine → client

/// What the engine may raise in `welcome.limits` (§2.4).
public struct WireLimits: Codable, Equatable, Sendable {
    /// UTF-16 units of `ctx.before` the client sends (up to 256).
    public var contextBefore: Int
    /// UTF-16 units of `ctx.selText`.
    public var selection: Int

    public init(contextBefore: Int = 32, selection: Int = 10002) {
        self.contextBefore = contextBefore
        self.selection = selection
    }
}

/// `welcome` (§2.4): its shape never changes.
public struct Welcome: Codable, Equatable, Sendable {
    public var version: Int
    /// The engine's version ("0.7.0").
    public var engine: String
    public var enginePid: UInt32
    public var capabilities: [String]
    public var limits: WireLimits

    public init(version: Int = WireVersion.current, engine: String, enginePid: UInt32, capabilities: [String] = [],
                limits: WireLimits = WireLimits()) {
        self.version = version
        self.engine = engine
        self.enginePid = enginePid
        self.capabilities = capabilities
        self.limits = limits
    }

    /// The engine capability: the client sends every key-up (§5.2).
    public static let keyUps = "keyUps"
}

/// What the engine sends (§3–§7).
public enum EngineMessage: Equatable, Sendable {
    case welcome(re: UInt32, Welcome)
    /// A key's, `blur`'s or `endComposition`'s answer: whether the key was handled, and what to do to the document.
    case result(re: UInt32, handled: Bool = false, outputs: [Output] = [])
    /// `re`: the frame it answers, if any; `versions`: the engine's, for `unsupportedVersion`.
    case error(re: UInt32?, code: WireErrorCode, message: String, versions: [Int]? = nil)
    case pong(re: UInt32)
    /// Outputs for a session the engine pushes on its own (a click in its panel, a stream into the field).
    case apply(sid: UInt32, focus: UInt32, outputs: [Output])
    /// The engine is about to exit ("update", "restart"): reconnect after `retryMs`.
    case bye(reason: String, retryMs: Int)
    case unknown(type: String)

    public var type: String {
        switch self {
        case .welcome: return "welcome"
        case .result: return "result"
        case .error: return "error"
        case .pong: return "pong"
        case .apply: return "apply"
        case .bye: return "bye"
        case let .unknown(type): return type
        }
    }
}

/// An engine's frame: the envelope and its message.
public struct EngineFrame: Equatable, Sendable {
    public var v: Int
    public var id: UInt32
    public var message: EngineMessage

    public init(v: Int = WireVersion.current, id: UInt32, _ message: EngineMessage) {
        self.v = v
        self.id = id
        self.message = message
    }
}

extension EngineFrame: Codable {
    enum CodingKeys: String, CodingKey {
        case v, id, re, type, sid, handled, outputs, code, message, versions, focus, reason, retryMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 0
        id = try c.decode(UInt32.self, forKey: .id)
        let type = try c.decode(String.self, forKey: .type)
        func re() throws -> UInt32 { try c.decode(UInt32.self, forKey: .re) }
        switch type {
        case "welcome":
            message = .welcome(re: try re(), try Welcome(from: decoder))
        case "result":
            message = .result(re: try re(), handled: try c.decodeIfPresent(Bool.self, forKey: .handled) ?? false,
                              outputs: try c.decodeIfPresent([Output].self, forKey: .outputs) ?? [])
        case "error":
            message = .error(re: try c.decodeIfPresent(UInt32.self, forKey: .re), code: try c.decode(WireErrorCode.self, forKey: .code),
                             message: try c.decodeIfPresent(String.self, forKey: .message) ?? "",
                             versions: try c.decodeIfPresent([Int].self, forKey: .versions))
        case "pong":
            message = .pong(re: try re())
        case "apply":
            message = .apply(sid: try c.decode(UInt32.self, forKey: .sid), focus: try c.decodeIfPresent(UInt32.self, forKey: .focus) ?? 0,
                             outputs: try c.decodeIfPresent([Output].self, forKey: .outputs) ?? [])
        case "bye":
            message = .bye(reason: try c.decodeIfPresent(String.self, forKey: .reason) ?? "",
                           retryMs: try c.decodeIfPresent(Int.self, forKey: .retryMs) ?? 0)
        default:
            message = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(message.type, forKey: .type)
        switch message {
        case let .welcome(re, welcome):
            try c.encode(re, forKey: .re)
            try welcome.encode(to: encoder)
        case let .result(re, handled, outputs):
            try c.encode(re, forKey: .re)
            try c.encodeUnlessDefault(handled, forKey: .handled)
            try c.encodeUnlessDefault(outputs, forKey: .outputs)
        case let .error(re, code, message, versions):
            try c.encodeIfPresent(re, forKey: .re)
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
            try c.encodeIfPresent(versions, forKey: .versions)
        case let .pong(re):
            try c.encode(re, forKey: .re)
        case let .apply(sid, focus, outputs):
            try c.encode(sid, forKey: .sid)
            try c.encode(focus, forKey: .focus)
            try c.encode(outputs, forKey: .outputs)
        case let .bye(reason, retryMs):
            try c.encode(reason, forKey: .reason)
            try c.encodeUnlessDefault(retryMs, forKey: .retryMs)
        case .unknown:
            break
        }
    }
}

// MARK: - Canonical JSON

public enum WireJSON {
    /// The canonical form (§1, §11): keys sorted, "/" unescaped.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

extension KeyedEncodingContainer {
    /// Writes `value` unless it is its type's default (canonical form, §1).
    mutating func encodeUnlessDefault(_ value: Bool, forKey key: Key) throws {
        if value { try encode(value, forKey: key) }
    }

    mutating func encodeUnlessDefault(_ value: Int, forKey key: Key) throws {
        if value != 0 { try encode(value, forKey: key) }
    }

    mutating func encodeUnlessDefault(_ value: String, forKey key: Key) throws {
        if !value.isEmpty { try encode(value, forKey: key) }
    }

    mutating func encodeUnlessDefault<T: Encodable>(_ value: [T], forKey key: Key) throws {
        if !value.isEmpty { try encode(value, forKey: key) }
    }
}
