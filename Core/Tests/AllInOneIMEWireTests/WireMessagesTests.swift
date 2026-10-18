import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation
import Testing

/// The messages' JSON (§1, §3–§7): canonical form out, either form in, unknown names kept or skipped.
struct WireMessagesTests {
    func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try WireJSON.encode(value), as: UTF8.self) }

    @Test func resultLeavesItsDefaultsOut() throws {
        #expect(try json(EngineFrame(id: 2, .result(re: 4))) == #"{"id":2,"re":4,"type":"result","v":1}"#)
        let handled = EngineFrame(id: 6, .result(re: 8, handled: true, outputs: [
            .composition(text: "@", caret: 1, segments: [Segment(from: 0, to: 1, style: Segment.Style.draft)]),
            .panel(shown: true),
        ]))
        #expect(try json(handled) == #"{"handled":true,"id":6,"outputs":[{"caret":1,"op":"composition","segments":[{"from":0,"style":"draft","to":1}],"text":"@"},{"op":"panel","shown":true}],"re":8,"type":"result","v":1}"#)
    }

    @Test func outputsKeepWhatTheyAre() throws {
        // An empty composition ends it: its text is written; a panel's one field always.
        #expect(try json(Output.composition(text: "")) == #"{"op":"composition","text":""}"#)
        #expect(try json(Output.panel(shown: false)) == #"{"op":"panel","shown":false}"#)
        #expect(try json(Output.commit(text: "Hello.")) == #"{"op":"commit","text":"Hello."}"#)
        #expect(try json(Output.commit(text: "x", deleteBefore: 2, afterKey: true))
            == #"{"afterKey":true,"deleteBefore":2,"op":"commit","text":"x"}"#)
        #expect(try json(Output.allowForeground) == #"{"op":"allowForeground"}"#)
    }

    @Test func outputsReadEitherForm() throws {
        let read = try WireJSON.decode([Output].self, from: Data(#"""
            [{"op":"commit","text":"a","deleteBefore":0,"afterKey":false},{"op":"panel"},{"op":"composition","text":"b"},
             {"op":"sparkle","glitter":3},{"op":"allowForeground"}]
            """#.utf8))
        #expect(read == [.commit(text: "a"), .panel(shown: false), .composition(text: "b"), .unknown(op: "sparkle"), .allowForeground])
    }

    @Test func welcomeKeepsItsShape() throws {
        let welcome = EngineFrame(id: 1, .welcome(re: 1, Welcome(engine: "0.7.0", enginePid: 3100)))
        // Its shape never changes (§2.4): `capabilities` even when empty.
        #expect(try json(welcome) == #"{"capabilities":[],"engine":"0.7.0","enginePid":3100,"id":1,"limits":{"contextBefore":32,"selection":10002},"re":1,"type":"welcome","v":1,"version":1}"#)
    }

    @Test func clientFramesReadAsTheSpecWritesThem() throws {
        let hello = try WireJSON.decode(ClientFrame.self, from: Data(#"""
            {"v":1,"id":1,"type":"hello","versions":[1],"client":"tip/0.7.0","platform":"win","arch":"x64","pid":4242,"tid":4250,"capabilities":["allowForeground"]}
            """#.utf8))
        #expect(hello == ClientFrame(id: 1, .hello(Hello(client: "tip/0.7.0", pid: 4242, tid: 4250, capabilities: ["allowForeground"]))))

        let key = try WireJSON.decode(ClientFrame.self, from: Data(#"""
            {"v":1,"id":8,"type":"keyDown","sid":1,"t":5000100,"key":{"vk":50,"scan":3,"text":"@","textIgnoringModifiers":"@","modifiers":["shift","leftShift"]},"ctx":{"sel":[3,3],"before":"hi "}}
            """#.utf8))
        let wire = WireKey(vk: 50, scan: 3, text: "@", textIgnoringModifiers: "@", modifiers: [.shift, .leftShift])
        #expect(key == ClientFrame(id: 8, .keyDown(KeyFrame(sid: 1, t: 5_000_100, key: wire, ctx: FieldContext(sel: [3, 3], before: "hi ")))))

        let applied = try WireJSON.decode(ClientFrame.self, from: Data(#"{"v":1,"id":5,"re":22,"type":"applied","ok":false,"reason":"gone"}"#.utf8))
        #expect(applied.message == .applied(re: 22, ok: false, reason: "gone", ctx: nil))

        let caret = try WireJSON.decode(ClientFrame.self, from: Data(#"{"v":1,"id":9,"type":"caret","sid":1,"rect":[812,440,9,20],"hwnd":198940,"exact":false}"#.utf8))
        #expect(caret.message == .caret(sid: 1, rect: [812, 440, 9, 20], hwnd: 198940, exact: false))
    }

    @Test func everyClientFrameRoundTrips() throws {
        let frames: [ClientMessage] = [
            .hello(Hello(client: "tip/0.7.0", pid: 1, tid: 2, capabilities: ["allowForeground"])),
            .open(sid: 1, field: FieldInfo(app: "win:notepad.exe", process: "notepad.exe", secure: true, scopes: [31], layout: "00000409")),
            .focus(sid: 1, focus: 2, field: nil),
            .focus(sid: 1, focus: 3, field: FieldInfo(readOnly: true)),
            .blur(sid: 1), .close(sid: 1), .ping,
            .keyDown(KeyFrame(sid: 1, t: 9, key: WireKey(vk: 0x41, scan: 0x1E, extended: true, text: "a", isDeadKey: true, isRepeat: true),
                              ctx: FieldContext(sel: [1, 4], before: "x", selText: "abc", selTruncated: true, comp: 2))),
            .keyUp(KeyFrame(sid: 1, t: 10, key: WireKey(key: .modifier(.shift, .left), usage: 0xE1))),
            .endComposition(sid: 1, reason: "terminated"),
            .caret(sid: 1, rect: [1, 2, 3, 4], hwnd: 7, exact: true),
            .applied(re: 3, ok: true, reason: nil, ctx: FieldContext(sel: [9, 9], before: "hi Hello.")),
        ]
        for (i, message) in frames.enumerated() {
            let frame = ClientFrame(id: UInt32(i + 1), message)
            #expect(try WireJSON.decode(ClientFrame.self, from: WireJSON.encode(frame)) == frame)
        }
    }

    @Test func everyEngineFrameRoundTrips() throws {
        let frames: [EngineMessage] = [
            .welcome(re: 1, Welcome(engine: "0.7.0", enginePid: 3100, capabilities: ["keyUps"], limits: WireLimits(contextBefore: 64))),
            .result(re: 2, handled: true, outputs: [.commit(text: "Hello."), .panel(shown: false)]),
            .error(re: 3, code: .noSession, message: "no session 7"),
            .error(re: nil, code: .unsupportedVersion, message: "no common version", versions: [1]),
            .pong(re: 4),
            .apply(sid: 1, focus: 1, outputs: [.composition(text: "ab", caret: 2, segments: [Segment(from: 0, to: 2, style: "target")])]),
            .bye(reason: "update", retryMs: 500),
        ]
        for (i, message) in frames.enumerated() {
            let frame = EngineFrame(id: UInt32(i + 1), message)
            #expect(try WireJSON.decode(EngineFrame.self, from: WireJSON.encode(frame)) == frame)
        }
    }

    @Test func unknownTypesAreKept() throws {
        let client = try WireJSON.decode(ClientFrame.self, from: Data(#"{"v":1,"id":3,"type":"frobnicate","sid":1}"#.utf8))
        #expect(client.message == .unknown(type: "frobnicate"))
        let engine = try WireJSON.decode(EngineFrame.self, from: Data(#"{"v":1,"id":3,"type":"sparkle","stars":5}"#.utf8))
        #expect(engine.message == .unknown(type: "sparkle"))
    }

    @Test func missingRequiredFieldsDontRead() {
        #expect(throws: DecodingError.self) { try WireJSON.decode(ClientFrame.self, from: Data(#"{"v":1,"type":"ping"}"#.utf8)) }
        #expect(throws: DecodingError.self) {
            try WireJSON.decode(ClientFrame.self, from: Data(#"{"v":1,"id":2,"type":"keyDown","sid":1}"#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try WireJSON.decode(ClientFrame.self, from: Data(#"{"v":1,"id":2,"type":"blur","sid":"one"}"#.utf8))
        }
    }

    @Test func modifierKeys() {
        for vk: UInt16 in [0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5] { #expect(WireKey.isModifier(vk: vk)) }
        for vk: UInt16 in [0x0D, 0x14, 0x20, 0x41, 0x5D, 0xA6] { #expect(!WireKey.isModifier(vk: vk)) }
    }

    /// The engine reads raw Windows codes into the Composer's keys (§5.1).
    @Test func readingKeys() throws {
        let enter = try #require(ComposerSession.read(WireKey(vk: 0x0D, scan: 0x1C, text: "\r")))
        #expect(enter.key == .enter && enter.usage == 0x28)
        let keypadEnter = try #require(ComposerSession.read(WireKey(vk: 0x0D, scan: 0x1C, extended: true, text: "\r")))
        #expect(keypadEnter.key == .keypadEnter)
        let rightCtrl = try #require(ComposerSession.read(WireKey(vk: 0x11, scan: 0x1D, extended: true, modifiers: [.control, .rightControl])))
        #expect(rightCtrl.key == .modifier(.control, .right))
        // A fake Shift (E0 2A) is no key at all.
        #expect(ComposerSession.read(WireKey(vk: 0x10, scan: 0x2A, extended: true, modifiers: [.shift])) == nil)
        // AltGr+Q on a German layout: Ctrl+Alt with the right Alt down types "@", marked AltGr, and the event is text.
        let altGr = try #require(ComposerSession.read(WireKey(vk: 0x51, scan: 0x10, text: "@", textIgnoringModifiers: "q",
                                                              modifiers: [.control, .option, .leftControl, .rightOption])))
        #expect(altGr.modifiers.contains(.altGraph))
        let event = altGr.event(modifiers: altGr.modifiers.subtracting(.sides))
        #expect(event.modifiers.isEmpty && event.printableText == "@")
        // Other clients send the key by name and its usage.
        let named = try #require(ComposerSession.read(WireKey(text: "a", key: .character, usage: 0x04)))
        #expect(named.key == .character && named.usage == 0x04)
    }
}

/// Frames (§2.2): the length prefix, the limits and the checks.
struct WireFrameTests {
    @Test func prefixRoundTrips() throws {
        let body = Data(#"{"v":1,"id":1,"type":"ping"}"#.utf8)
        let framed = WireFrame.frame(body)
        #expect(framed.count == body.count + 4)
        #expect(Array(framed.prefix(4)) == [UInt8(body.count), 0, 0, 0])
        #expect(try WireFrame.body(ofMessage: framed, limit: WireFrame.clientLimit) == body)
    }

    @Test func aPrefixThatLiesIsABadFrame() {
        var framed = WireFrame.frame(Data("{}".utf8))
        framed.append(0x20)
        #expect(throws: WireFrame.Failure.self) { try WireFrame.body(ofMessage: framed, limit: 100) }
        #expect(throws: WireFrame.Failure.self) { try WireFrame.body(ofMessage: Data([1, 0]), limit: 100) }
        do {
            _ = try WireFrame.body(ofMessage: framed, limit: 100)
        } catch {
            #expect(error.code == .badFrame)
        }
    }

    @Test func overTheLimitIsTooLarge() {
        let framed = WireFrame.frame(Data(repeating: 0x20, count: 101))
        do {
            _ = try WireFrame.body(ofMessage: framed, limit: 100)
            Issue.record("read a frame over its limit")
        } catch {
            #expect(error == .tooLarge(101))
            #expect(error.code == .tooLarge)
        }
    }

    @Test func utf8IsChecked() {
        #expect(WireFrame.isValidUTF8(Data("hi 你好 🎉 é".utf8)))
        #expect(!WireFrame.isValidUTF8(Data([0xC0, 0xAF])))  // overlong "/"
        #expect(!WireFrame.isValidUTF8(Data([0xED, 0xA0, 0x80])))  // a surrogate
        #expect(!WireFrame.isValidUTF8(Data([0xF4, 0x90, 0x80, 0x80])))  // past U+10FFFF
        #expect(!WireFrame.isValidUTF8(Data([0xE4, 0xBD])))  // cut off
        #expect(!WireFrame.isValidUTF8(Data([0x80])))
        #expect(throws: WireFrame.Failure.self) { try WireFrame.check(Data([0x7B, 0xFF, 0x7D])) }
    }

    @Test func oneObjectNestedNoDeeperThan16() throws {
        func nested(_ depth: Int) -> Data {
            Data(("{\"a\":" + String(repeating: "[", count: depth - 1) + String(repeating: "]", count: depth - 1) + "}").utf8)
        }
        try WireFrame.check(nested(16))
        #expect(throws: WireFrame.Failure.self) { try WireFrame.check(nested(17)) }
        // Brackets inside strings don't count.
        try WireFrame.check(Data(#"{"a":"[[[[[[[[[[[[[[[[[[[[\"]]]]"}"#.utf8))
        #expect(throws: WireFrame.Failure.self) { try WireFrame.check(Data("[1]".utf8)) }
        #expect(throws: WireFrame.Failure.self) { try WireFrame.check(Data("{} {}".utf8)) }
        #expect(throws: WireFrame.Failure.self) { try WireFrame.check(Data("{".utf8)) }
        #expect(throws: WireFrame.Failure.self) { try WireFrame.check(Data("12".utf8)) }
    }

    @Test func aReaderSplitsAStream() throws {
        var reader = WireFrame.Reader(limit: 64)
        let a = Data(#"{"id":1}"#.utf8), b = Data(#"{"id":2}"#.utf8)
        let stream = WireFrame.frame(a) + WireFrame.frame(b)
        reader.append(stream.prefix(3))
        #expect(try reader.next() == nil)
        reader.append(stream.dropFirst(3).prefix(10))
        #expect(try reader.next() == a)
        #expect(try reader.next() == nil)
        reader.append(stream.dropFirst(13))
        #expect(try reader.next() == b)
        var small = WireFrame.Reader(limit: 4)
        small.append(WireFrame.frame(a))
        #expect(throws: WireFrame.Failure.self) { try small.next() }
    }
}
