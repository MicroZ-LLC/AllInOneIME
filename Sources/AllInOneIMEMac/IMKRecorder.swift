import AllInOneIMECore
import AppKit
import InputMethodKit
import os

/// The developer's IMK call recorder: every call the input method's controller makes of a field's client
/// (`IMKTextInput`) and what it answered, with the events they came in (a key down, a modifier change, the field
/// activated, left, committed or cancelled), written as the host-call recording's JSONL lines (`HostCallRecording`) to
/// a file, so that a session in a real app can become a host profile or a scenario (Core/Tests/HostScenarios) later.
///
/// Off unless the input method's process starts with `ALLINONEIME_IMK_RECORD` set: an absolute path to write to, or
/// `1` for ~/Library/Logs/AllInOneIME/imk-recording.jsonl (a developer's, e.g. `launchctl setenv ALLINONEIME_IMK_RECORD 1`
/// and the input method started again: `killall AllInOneIME`). No setting turns it on. Off, it does nothing at all: the
/// controller's client is IMK's own. Typed text is never written unless `ALLINONEIME_IMK_RECORD_TEXT=1` is set too: what
/// a field holds or is given is recorded as its length, a key that types as "text" and its length (`HostCallRecording`).
/// The file is written off the main thread, appended to, and left alone once it is `maxBytes` long.
public final class IMKRecorder: @unchecked Sendable {
    /// The input method's: as its process was started.
    public static let shared = IMKRecorder(environment: ProcessInfo.processInfo.environment)

    /// The variables that turn it on, and that keep the typed text in what it writes.
    public static let switchVariable = "ALLINONEIME_IMK_RECORD"
    public static let textVariable = "ALLINONEIME_IMK_RECORD_TEXT"
    /// Where `1` writes.
    public static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AllInOneIME/imk-recording.jsonl")
    }

    /// How long the file may grow (with what was there): a recording left on doesn't fill the disk.
    public static let maxBytes = 50_000_000

    /// It records (`ALLINONEIME_IMK_RECORD` set).
    public let isOn: Bool
    public let format: HostCallRecording
    /// Where it writes (nil: off, or a test's `sink`).
    public let file: URL?
    private let sink: (String) -> Void
    private let started = ProcessInfo.processInfo.systemUptime
    /// The proxy last made, reused for the same client: the controller tells fields apart by their client object.
    private var last: RecordingTextInput?

    /// From the process's `environment`; `sink` takes each line instead of the file (a test's).
    public init(environment: [String: String], sink: ((String) -> Void)? = nil) {
        let value = environment[Self.switchVariable] ?? ""
        isOn = !value.isEmpty && value != "0"
        format = HostCallRecording(keepsText: environment[Self.textVariable] == "1")
        guard isOn else {
            (file, self.sink) = (nil, { _ in })
            return
        }
        if let sink {
            (file, self.sink) = (nil, sink)
        } else {
            let file = value.hasPrefix("/") ? URL(fileURLWithPath: value) : Self.defaultFile
            self.file = file
            self.sink = Self.appending(to: file)
            fieldLog.notice("IMK calls recorded to \(file.path, privacy: .public) (typed text: \(self.format.keepsText ? "kept" : "lengths only", privacy: .public))")
        }
        self.sink(format.header())
    }

    /// `client`, through a proxy that records every call of it when this is on; else `client` itself.
    @MainActor
    public func recording(_ client: (any IMKTextInput & NSObjectProtocol)?) -> (any IMKTextInput & NSObjectProtocol)? {
        guard isOn, let client else { return client }
        if let proxy = client as? RecordingTextInput { return proxy }
        if let last, last.client === client { return last }
        let proxy = RecordingTextInput(client, recorder: self)
        last = proxy
        return proxy
    }

    /// `sender` (what IMK hands an entry point), through `recording`.
    @MainActor
    public func recording(sender: Any?) -> (any IMKTextInput & NSObjectProtocol)? {
        recording(sender as? (any IMKTextInput & NSObjectProtocol))
    }

    /// An event the calls after it come in ("activate", "deactivate", "commitComposition", "cancelComposition"), with the
    /// field's app.
    public func event(_ name: String, client: Any? = nil, _ fields: [String: HostCallRecording.Field] = [:]) {
        guard isOn else { return }
        var fields = fields
        if let app = (client as? IMKTextInput)?.bundleIdentifier() { fields["app"] = .name(app) }
        sink(format.event(name, at: now, fields))
    }

    /// A key down or a modifier change handed over; once it is answered, whether it was taken (`handled`).
    public func event(_ event: NSEvent, handled: Bool? = nil) {
        guard isOn else { return }
        if let handled {
            sink(format.event("answered", at: now, ["handled": .bool(handled)]))
            return
        }
        switch event.type {
        case .keyDown:
            sink(format.event("keyDown", at: now, format.key(MacKeyEvents.key(event))))
        case .flagsChanged:
            let modifiers = HostCallRecording.modifierNames(MacKeyEvents.modifiers(event.modifierFlags))
            sink(format.event("flagsChanged", at: now, ["code": .int(Int(event.keyCode)), "mods": .name(modifiers.joined(separator: "+"))]))
        default:
            break
        }
    }

    /// A call made through the proxy, its arguments and answer.
    func call(_ name: String, _ fields: [String: HostCallRecording.Field]) {
        sink(format.call(name, at: now, fields))
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime - started }

    /// Each line appended to `file` on a queue of its own (never the main thread's: rule 6), up to `maxBytes`.
    private static func appending(to file: URL) -> (String) -> Void {
        let queue = DispatchQueue(label: "com.allinoneime.imk-recorder")
        let state = Locked<FileHandle?>(initialState: nil)
        queue.async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            let handle = try? FileHandle(forWritingTo: file)
            _ = try? handle?.seekToEnd()
            state.withLock { $0 = handle }
        }
        return { line in
            queue.async {
                state.withLock { handle in
                    guard let open = handle else { return }
                    guard let size = try? open.offset(), size < UInt64(maxBytes) else {
                        try? open.close()
                        handle = nil
                        return
                    }
                    try? open.write(contentsOf: Data((line + "\n").utf8))
                }
            }
        }
    }
}

/// A field's client that hands every call to the real one and has `IMKRecorder` record it with its answer: only while
/// recording is on (`IMKRecorder.recording`). Anything else asked of it (IMK's own messages to its client proxy) goes to
/// the real client as it is.
final class RecordingTextInput: NSObject, IMKTextInput {
    let client: any IMKTextInput & NSObjectProtocol
    private let recorder: IMKRecorder

    init(_ client: any IMKTextInput & NSObjectProtocol, recorder: IMKRecorder) {
        (self.client, self.recorder) = (client, recorder)
        super.init()
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? { client }
    override func responds(to aSelector: Selector!) -> Bool { super.responds(to: aSelector) || client.responds(to: aSelector) }

    private typealias Field = HostCallRecording.Field

    private static func range(_ range: NSRange) -> Field { .range(location: range.location, length: range.length) }
    private static func rect(_ rect: NSRect) -> Field {
        .rect(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }

    private static func text(_ value: Any?) -> String? {
        (value as? NSAttributedString)?.string ?? value as? String
    }

    // MARK: IMKTextInput

    func insertText(_ string: Any!, replacementRange: NSRange) {
        recorder.call("insertText", ["text": .text(Self.text(string)), "replacement": Self.range(replacementRange)])
        client.insertText(string, replacementRange: replacementRange)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        recorder.call("setMarkedText", ["text": .text(Self.text(string)), "selection": Self.range(selectionRange),
                                        "replacement": Self.range(replacementRange)])
        client.setMarkedText(string, selectionRange: selectionRange, replacementRange: replacementRange)
    }

    func selectedRange() -> NSRange {
        let answer = client.selectedRange()
        recorder.call("selectedRange", ["answer": Self.range(answer)])
        return answer
    }

    func markedRange() -> NSRange {
        let answer = client.markedRange()
        recorder.call("markedRange", ["answer": Self.range(answer)])
        return answer
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        let answer = client.attributedSubstring(from: range)
        recorder.call("attributedSubstring", ["range": Self.range(range), "answer": .text(answer?.string)])
        return answer
    }

    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        let answer = client.string(from: range, actualRange: actualRange)
        recorder.call("string", ["range": Self.range(range), "answer": .text(answer)])
        return answer
    }

    func length() -> Int {
        let answer = client.length()
        recorder.call("length", ["answer": .int(answer)])
        return answer
    }

    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int {
        let answer = client.characterIndex(for: point, tracking: mappingMode, inMarkedRange: inMarkedRange)
        recorder.call("characterIndex", ["point": .point(x: Double(point.x), y: Double(point.y)), "answer": .int(answer)])
        return answer
    }

    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        let answer = client.attributes(forCharacterIndex: index, lineHeightRectangle: lineRect)
        recorder.call("attributes", ["index": .int(index), "line": lineRect.map { Self.rect($0.pointee) } ?? .none])
        return answer
    }

    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
        let answer = client.firstRect(forCharacterRange: aRange, actualRange: actualRange)
        recorder.call("firstRect", ["range": Self.range(aRange), "answer": Self.rect(answer),
                                    "actual": actualRange.map { Self.range($0.pointee) } ?? .none])
        return answer
    }

    func validAttributesForMarkedText() -> [Any]! { client.validAttributesForMarkedText() }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {
        recorder.call("overrideKeyboard", ["layout": keyboardUniqueName.map { .name($0) } ?? .none])
        client.overrideKeyboard(withKeyboardNamed: keyboardUniqueName)
    }

    func selectMode(_ modeIdentifier: String!) { client.selectMode(modeIdentifier) }
    func supportsUnicode() -> Bool { client.supportsUnicode() }

    func bundleIdentifier() -> String! {
        let answer = client.bundleIdentifier()
        recorder.call("bundleIdentifier", ["answer": answer.map { .name($0) } ?? .none])
        return answer
    }

    func windowLevel() -> CGWindowLevel { client.windowLevel() }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { client.supportsProperty(property) }
    func uniqueClientIdentifierString() -> String! { client.uniqueClientIdentifierString() }
}
