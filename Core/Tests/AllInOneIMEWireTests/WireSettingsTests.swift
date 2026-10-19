import AllInOneIMECore
@testable import AllInOneIMEWire
import Foundation
import Testing

/// The settings over the wire (§12): who may have them, their messages' JSON, an action that takes a while, and the
/// notice every settings client gets. The settings are the test's own (`useTestSettings`: a config in a folder of its
/// own, keys in memory).
struct WireSettingsTests {
    func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try WireJSON.encode(value), as: UTF8.self) }

    /// An engine with the test's settings, and a client connected as `peer` that said hello with `capabilities`.
    func engine(_ config: String = #"{"provider": "anthropic"}"#, peer: WirePeer = WirePeer.trustedClient,
                capabilities: [String] = [Hello.settings]) -> (TestEngine, ConnectionID, Welcome?) {
        let engine = TestEngine()
        #expect(engine.server.useTestSettings(config: config))
        let id = engine.server.connect(peer)!
        let answers = engine.send(ClientFrame(id: 1, .hello(Hello(client: "settings/test", capabilities: capabilities))), on: id)
        guard case let .welcome(_, welcome)? = answers.first?.message else { return (engine, id, nil) }
        return (engine, id, welcome)
    }

    // MARK: Who has them

    @Test func onlyATrustedClientThatAsks() {
        let (_, _, welcome) = engine()
        #expect(welcome?.capabilities == [Hello.settings])
        // Low integrity, or an AppContainer: not the settings (§8), though it asked.
        for peer in [WirePeer(integrity: .low), WirePeer(integrity: .medium, appContainer: true)] {
            let (engine, id, welcome) = self.engine(peer: peer)
            #expect(welcome?.capabilities == [])
            let answer = engine.send(ClientFrame(id: 2, .settingsGet), on: id)
            #expect(answer.map(\.message) == [.error(re: 2, code: .notAllowed, message: "the settings are for a trusted client only")])
        }
        // A peer the transport said nothing about: untrusted.
        let (unchecked, uncheckedID, uncheckedWelcome) = engine(peer: WirePeer())
        #expect(!WirePeer().trusted && uncheckedWelcome?.capabilities == [])
        #expect(unchecked.send(ClientFrame(id: 2, .settingsGet), on: uncheckedID).map(\.message)
                == [.error(re: 2, code: .notAllowed, message: "the settings are for a trusted client only")])
        // An engine without settings: none; asked for anyway, not allowed.
        let bare = TestEngine()
        let id = bare.server.connect(WirePeer.trustedClient)!
        let welcomed = bare.send(ClientFrame(id: 1, .hello(Hello(client: "settings/test", capabilities: [Hello.settings]))), on: id)
        guard case let .welcome(_, welcome)? = welcomed.first?.message else { Issue.record("no welcome"); return }
        #expect(welcome.capabilities == [])
        #expect(bare.send(ClientFrame(id: 2, .settingsGet), on: id).map(\.message)
                == [.error(re: 2, code: .notAllowed, message: "the settings are for a trusted client only")])
    }

    // MARK: Their JSON

    @Test func theClientsFramesReadAsTheSpecWritesThem() throws {
        func read(_ text: String) throws -> ClientMessage { try WireJSON.decode(ClientFrame.self, from: Data(text.utf8)).message }
        #expect(try read(#"{"v":1,"id":2,"type":"settingsGet"}"#) == .settingsGet)
        #expect(try read(#"{"v":1,"id":3,"type":"settingsSet","field":"maxTokens","value":1500}"#)
                == .settingsSet(field: "maxTokens", value: .number(1500)))
        // Null is a value; no value is no change.
        #expect(try read(#"{"v":1,"id":3,"type":"settingsSet","field":"uiLanguage","value":null}"#)
                == .settingsSet(field: "uiLanguage", value: .null))
        #expect(throws: DecodingError.self) { try read(#"{"v":1,"id":3,"type":"settingsSet","field":"maxTokens"}"#) }
        // Made on a revision, or as an edit of the list shown (§12.4).
        #expect(try read(#"{"v":1,"id":3,"type":"settingsSet","field":"maxTokens","value":1500,"revision":7}"#)
                == .settingsSet(field: "maxTokens", value: .number(1500), revision: 7))
        #expect(try read(#"{"v":1,"id":3,"type":"settingsSet","field":"redaction.customWords","value":["Acme","Mine"],"shown":["Acme"]}"#)
                == .settingsSet(field: "redaction.customWords", value: .array([.string("Acme"), .string("Mine")]),
                                shown: .array([.string("Acme")])))
        let edit = ClientFrame(id: 3, .settingsSet(field: "inputLanguages", value: .array([.string("zh")]), revision: 2,
                                                   shown: .array([.string("en")])))
        #expect(try json(edit) == #"{"field":"inputLanguages","id":3,"revision":2,"shown":["en"],"type":"settingsSet","v":1,"value":["zh"]}"#)
        #expect(try WireJSON.decode(ClientFrame.self, from: WireJSON.encode(edit)) == edit)
        #expect(try read(#"{"v":1,"id":4,"type":"settingsAction","field":"openai.key","action":"setKey","key":"sk-test-1"}"#)
                == .settingsAction(SettingsAction(field: "openai.key", name: "setKey", key: "sk-test-1")))
        #expect(try read(#"{"v":1,"id":5,"type":"settingsAction","field":"commands.custom","action":"delete","item":"polite"}"#)
                == .settingsAction(SettingsAction(field: "commands.custom", name: "delete", item: "polite")))
        // Each is a request (§3).
        #expect(ClientMessage.settingsGet.isRequest && ClientMessage.settingsSet(field: "x", value: .null).isRequest)
        // Written back as read.
        let set = ClientFrame(id: 3, .settingsSet(field: "uiLanguage", value: .null))
        #expect(try json(set) == #"{"field":"uiLanguage","id":3,"type":"settingsSet","v":1,"value":null}"#)
        #expect(try WireJSON.decode(ClientFrame.self, from: WireJSON.encode(set)) == set)
    }

    @Test func theEnginesFrames() throws {
        let problem = SettingsProblem(.badValue, field: "maxTokens", message: "Between 200 and 4000")
        let refused = EngineFrame(id: 5, .settings(re: 4, SettingsAnswer(revision: 2, problem: problem)))
        #expect(try json(refused)
                == #"{"id":5,"problem":{"code":"badValue","field":"maxTokens","message":"Between 200 and 4000"},"re":4,"revision":2,"type":"settings","v":1}"#)
        #expect(try WireJSON.decode(EngineFrame.self, from: WireJSON.encode(refused)) == refused)
        #expect(try json(EngineFrame(id: 6, .settingsChanged(revision: 3))) == #"{"id":6,"revision":3,"type":"settingsChanged","v":1}"#)
        let document = SettingsDocument(language: "en", platform: .windows, sections: [
            SettingsDocument.Section(id: "general", title: "General", fields: [
                SettingsDocument.Field(id: "typeOut", kind: .toggle, label: "Type results out", value: .bool(false)),
            ]),
        ])
        let answer = EngineFrame(id: 2, .settings(re: 2, SettingsAnswer(revision: 1, document: document, message: "✓ 1.2 s: Hi")))
        #expect(try json(answer) == #"{"document":{"language":"en","platform":"windows","sections":[{"fields":[{"id":"typeOut","kind":"toggle","label":"Type results out","value":false}],"id":"general","title":"General"}]},"id":2,"message":"✓ 1.2 s: Hi","re":2,"revision":1,"type":"settings","v":1}"#)
        #expect(try WireJSON.decode(EngineFrame.self, from: WireJSON.encode(answer)) == answer)
    }

    // MARK: Over a connection

    /// A key is never sent back: not in the answer, not in the document, not in the notice.
    @Test func aKeyIsNeverSentBack() throws {
        let (engine, id, _) = engine()
        let key = "sk-test-never-back-0123-z9y8"
        let sent = try WireJSON.encode(ClientFrame(id: 2, .settingsAction(SettingsAction(field: "anthropic.key", name: "setKey", key: key))))
        let answers = engine.send(sent, on: id)
        #expect(answers.count == 2)  // the answer, the notice
        for answer in answers { #expect(!String(decoding: answer, as: UTF8.self).contains("never-back")) }
        guard case let .settings(_, settings) = try WireJSON.decode(EngineFrame.self, from: answers[0]).message else {
            Issue.record("no settings answer")
            return
        }
        #expect(settings.problem == nil && settings.document?.field("anthropic.key")?.isSet == true)
        #expect(settings.document?.field("anthropic.key")?.status?.hasSuffix("z9y8") == true)
    }

    /// Every client that has the settings hears of a change, the one that made it too (after its answer).
    @Test func everySettingsClientIsTold() throws {
        let (engine, first, _) = engine()
        let second = engine.server.connect(WirePeer.trustedClient)!
        _ = engine.send(ClientFrame(id: 1, .hello(Hello(client: "settings/other", capabilities: [Hello.settings]))), on: second)
        let typing = engine.server.connect(WirePeer.trustedClient)!
        _ = engine.send(ClientFrame(id: 1, .hello(Hello(client: "tip/test"))), on: typing)
        let answers = engine.send(ClientFrame(id: 2, .settingsSet(field: "typeOut", value: .bool(true))), on: first)
        guard case let .settings(re, answer) = answers.first?.message else { Issue.record("no answer"); return }
        #expect(re == 2 && answer.problem == nil && answer.document?.field("typeOutRate") != nil)
        #expect(answers.dropFirst().map(\.message) == [.settingsChanged(revision: answer.revision)])
        let told = engine.takePushes(for: second).map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
        #expect(told == [.settingsChanged(revision: answer.revision)])
        #expect(engine.takePushes(for: typing).isEmpty)
    }

    /// Settings windows and the engine's own check of the file at once, on real queues as the engine runs them: every
    /// change is answered, the revision counts each once, and each window is told of the changes in order (never an
    /// older revision after a newer one), the last one too.
    @Test func manyWindowsAtOnce() throws {
        let server = WireServer(environment: WireEnvironment(host: TestHost()))
        #expect(server.useTestSettings(config: #"{"provider": "anthropic"}"#))
        let service = try #require(server.settings)
        let pushes = Locked<[ConnectionID: [EngineMessage]]>(initialState: [:])
        server.push = { id, data in
            let message = try! WireJSON.decode(EngineFrame.self, from: data).message
            pushes.withLock { $0[id, default: []].append(message) }
        }
        let windows = 8, changes = 4
        let ids = Locked<[ConnectionID]>(initialState: [])
        let answers = Locked<[EngineMessage]>(initialState: [])
        DispatchQueue.concurrentPerform(iterations: windows) { window in
            guard let id = server.connect(.trustedClient) else { return }
            ids.withLock { $0.append(id) }
            func send(_ frame: ClientFrame) -> [EngineMessage] {
                server.receive(try! WireJSON.encode(frame), on: id).map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
            }
            _ = send(ClientFrame(id: 1, .hello(Hello(client: "settings/\(window)", capabilities: [Hello.settings]))))
            for change in 0..<changes {
                // A value of its own each: 200, 300 … 3300.
                let tokens = 200 + 100 * Double(window * changes + change)
                let answer = send(ClientFrame(id: UInt32(2 + 2 * change), .settingsSet(field: "maxTokens", value: .number(tokens))))
                answers.withLock { $0 += answer }
                _ = send(ClientFrame(id: UInt32(3 + 2 * change), .settingsGet))
                service.checkForChanges()
            }
        }
        let connected = ids.withLock { $0 }
        #expect(connected.count == windows)
        if let any = connected.first { server.perform("idle", on: any) }
        let settings = answers.withLock { $0 }.compactMap { message -> SettingsAnswer? in
            if case let .settings(_, answer) = message { return answer } else { return nil }
        }
        #expect(settings.count == windows * changes && settings.allSatisfy { $0.problem == nil })
        #expect(service.revision == 1 + UInt64(windows * changes))
        for id in connected {
            let told = pushes.withLock { $0[id] ?? [] }.compactMap { message -> UInt64? in
                if case let .settingsChanged(revision) = message { return revision } else { return nil }
            }
            #expect(told == told.sorted() && Set(told).count == told.count && told.last == service.revision, "\(told)")
        }
    }

    /// The file changed by something else (allinoneime-cli, an editor): the engine's check finds it, and the clients
    /// are told.
    @Test func aChangeInTheFile() throws {
        let (engine, id, _) = engine()
        let service = try #require(engine.server.settings)
        guard case let .settings(_, before) = engine.send(ClientFrame(id: 2, .settingsGet), on: id).first?.message else {
            Issue.record("no answer")
            return
        }
        let url = URL(fileURLWithPath: try #require(before.document?.field("configFile")?.value.flatMap {
            if case let .string(path) = $0 { return path } else { return nil }
        }))
        try Data(#"{"provider": "anthropic", "maxTokens": 2000}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        service.checkForChanges()
        engine.runUntilIdle()
        let told = engine.takePushes(for: id).map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
        #expect(told == [.settingsChanged(revision: before.revision + 1)])
    }

    /// An action that takes a while (a test) is answered when it is done, through a push with its `re`; meanwhile the
    /// connection goes on. (The Notion link's Test with no link and no page kept: it fails at once, with no network.)
    @Test func anActionThatTakesAWhile() async throws {
        let (engine, id, _) = engine(#"{"notes": {"destination": "notion"}}"#)
        let answers = engine.send(ClientFrame(id: 2, .settingsAction(SettingsAction(field: "notes.notion", name: "test"))), on: id)
        #expect(answers.isEmpty)
        #expect(engine.send(ClientFrame(id: 3, .ping), on: id).map(\.message) == [.pong(re: 3)])
        var pushed: [EngineMessage] = []
        func answered() -> (UInt32, SettingsAnswer)? {
            for message in pushed { if case let .settings(re, answer) = message { return (re, answer) } }
            return nil
        }
        for _ in 0..<200 where answered() == nil {
            try await Task.sleep(for: .milliseconds(10))
            engine.runUntilIdle()
            pushed += engine.takePushes(for: id).map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
        }
        // The outcome shown is a change too: the notice, then the answer.
        guard let (re, answer) = answered() else { Issue.record("no answer: \(pushed)"); return }
        #expect(pushed.first == .settingsChanged(revision: answer.revision))
        #expect(re == 2 && answer.problem?.code == .failed && answer.problem?.message.hasPrefix("✗ ") == true)
        #expect(answer.document?.field("notes.notion")?.status == answer.problem?.message)
    }
}
