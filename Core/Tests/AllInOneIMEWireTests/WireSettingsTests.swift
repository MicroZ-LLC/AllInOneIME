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

    /// The engine's log has the field and the action, never a key, a value or a link sent (§12.8).
    @Test func noKeyInTheWiresLog() throws {
        let lines = Locked<[String]>(initialState: [])
        let engine = TestEngine(log: { line in lines.withLock { $0.append(line) } })
        #expect(engine.server.useTestSettings(config: #"{"provider": "anthropic", "notes": {"destination": "notion"}, "redaction": {"enabled": true}}"#))
        let id = try #require(engine.server.connect(.trustedClient))
        _ = engine.send(ClientFrame(id: 1, .hello(Hello(client: "settings/test", capabilities: [Hello.settings]))), on: id)
        let sent = ["sk-test-wire-log-0000-u7i8", "Wire-Log-Secret-Word", "wire-log-secret-page"]
        _ = engine.send(ClientFrame(id: 2, .settingsAction(SettingsAction(field: "anthropic.key", name: "setKey", key: sent[0]))), on: id)
        _ = engine.send(ClientFrame(id: 3, .settingsSet(field: "redaction.customWords", value: .array([.string(sent[1])]))), on: id)
        let link = AIConfig.JSONValue.string("https://www.notion.so/\(sent[2])-0123456789abcdef0123456789abcdef")
        _ = engine.send(ClientFrame(id: 4, .settingsAction(SettingsAction(field: "notes.notion", name: "test", value: link))), on: id)
        let log = lines.withLock { $0 }
        #expect(log.contains { $0.hasSuffix("settingsAction setKey on anthropic.key") } && log.contains { $0.hasSuffix("settingsSet redaction.customWords") })
        for text in sent { #expect(!log.contains { $0.contains(text) }, "\(text) logged") }
    }

    /// The settings as the engine makes them (no secret store of their own, keys looked up as `APIKeys.source` does,
    /// in the platform's store: in memory here, with no login environment), over the wire: a key saved shows its last 4,
    /// removed it is gone, and it never comes back.
    @Test func theEnginesConfiguration() throws {
        var platform = Platform.current
        platform.secrets = .inMemory()
        platform.processes = NoProcessLauncher()
        try Platform.$override.withValue(platform) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wire-engine-settings-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appendingPathComponent("config.json")
            try Data(#"{"provider": "anthropic", "uiLanguage": "en"}"#.utf8).write(to: url)
            let engine = TestEngine()
            engine.server.settings = SettingsService(store: SettingsStore(configURL: url), platform: .windows,
                                                     library: PluginLibrary(directory: folder.appendingPathComponent("plugins")))
            let id = try #require(engine.server.connect(.trustedClient))
            _ = engine.send(ClientFrame(id: 1, .hello(Hello(client: "settings/test", capabilities: [Hello.settings]))), on: id)
            func key(after frame: ClientFrame) throws -> SettingsDocument.Field? {
                let answers = engine.send(try WireJSON.encode(frame), on: id)
                #expect(!answers.contains { String(decoding: $0, as: UTF8.self).contains("engine-config") })
                guard case let .settings(_, answer)? = try answers.first.map({ try WireJSON.decode(EngineFrame.self, from: $0).message }) else { return nil }
                return answer.document?.field("anthropic.key")
            }
            let saved = try key(after: ClientFrame(id: 2, .settingsAction(SettingsAction(field: "anthropic.key", name: "setKey",
                                                                                         key: "sk-test-engine-config-a1b2"))))
            #expect(saved?.isSet == true && saved?.status == "✓ Saved · ends in a1b2" && saved?.actions == ["setKey", "removeKey"])
            #expect(APIKeys.keyEnding(account: "anthropic") == "a1b2")
            let removed = try key(after: ClientFrame(id: 3, .settingsAction(SettingsAction(field: "anthropic.key", name: "removeKey"))))
            #expect(removed?.isSet == false && !APIKeys.hasKeychainKey(account: "anthropic"))
        }
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

    /// An answer the frame limit (1 MiB) can't hold (a document with a huge word list) is an error with its `re`, not
    /// left out: the client isn't left waiting, and the connection goes on.
    @Test func anAnswerOverTheLimit() throws {
        let words = (0..<20_000).map { "\"a-very-long-word-to-hide-from-the-model-number-\($0)\"" }.joined(separator: ",")
        let (engine, id, _) = engine(#"{"redaction": {"enabled": true, "customWords": ["# + words + #"]}}"#)
        let answer = engine.send(ClientFrame(id: 2, .settingsGet), on: id)
        guard case let .error(re, code, message, _)? = answer.first?.message, answer.count == 1 else {
            Issue.record("not an error: \(answer.map(\.message.type))")
            return
        }
        #expect(re == 2 && code == .internal && message.hasPrefix("the answer is over the frame limit"))
        #expect(engine.send(ClientFrame(id: 3, .ping), on: id).map(\.message) == [.pong(re: 3)])
    }

    /// Settings windows and the engine's own check of the file at once, on real queues as the engine runs them: every
    /// change is answered, the revision counts each once, and each window is told of the changes in order (never an
    /// older revision after a newer one), the last one too.
    @Test func manyWindowsAtOnce() throws {
        let server = WireServer(environment: WireEnvironment(host: TestHost()))
        // 4000: none of the values the windows set, so that each is a change.
        #expect(server.useTestSettings(config: #"{"provider": "anthropic", "maxTokens": 4000}"#))
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
                // A value of its own each: 200 … 900, 1100 … 3400. Not 1000: a file's 1000 (the default before 0.6.7)
                // reads as today's default, so the engine's check would find it changed.
                let n = window * changes + change
                let tokens = 200 + 100 * Double(n < 8 ? n : n + 1)
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
        try Data(#"{"provider": "anthropic", "maxTokens": 3000}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        service.checkForChanges()
        engine.runUntilIdle()
        let told = engine.takePushes(for: id).map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
        #expect(told == [.settingsChanged(revision: before.revision + 1)])
    }

    /// The frames pushed to `id` until `done` says so (a test's task runs on its own), at most 2 s.
    func pushes(_ engine: TestEngine, for id: ConnectionID, until done: ([EngineMessage]) -> Bool) async throws -> [EngineMessage] {
        var pushed: [EngineMessage] = []
        for _ in 0..<200 where !done(pushed) {
            try await Task.sleep(for: .milliseconds(10))
            engine.runUntilIdle()
            pushed += engine.takePushes(for: id).map { try! WireJSON.decode(EngineFrame.self, from: $0).message }
        }
        return pushed
    }

    static func answer(to re: UInt32, in messages: [EngineMessage]) -> SettingsAnswer? {
        for message in messages { if case .settings(re, let answer) = message { return answer } }
        return nil
    }

    static func notices(_ messages: [EngineMessage]) -> [UInt64] {
        messages.compactMap { if case let .settingsChanged(revision) = $0 { revision } else { nil } }
    }

    /// An action that takes a while (a test) is answered when it is done, through a push with its `re`; meanwhile the
    /// connection goes on. It is a change when it starts (shown `running`) and when it is done (what it found): a
    /// notice each, then the answer. (The Notion link's Test with no link and no page kept: it fails at once, with no
    /// network.)
    @Test func anActionThatTakesAWhile() async throws {
        let (engine, id, _) = engine(#"{"notes": {"destination": "notion"}}"#)
        let answers = engine.send(ClientFrame(id: 2, .settingsAction(SettingsAction(field: "notes.notion", name: "test"))), on: id)
        #expect(answers.isEmpty)
        #expect(engine.send(ClientFrame(id: 3, .ping), on: id).map(\.message) == [.pong(re: 3)])
        let pushed = try await pushes(engine, for: id) { Self.answer(to: 2, in: $0) != nil }
        guard let answer = Self.answer(to: 2, in: pushed) else { Issue.record("no answer: \(pushed)"); return }
        #expect(Self.notices(pushed) == [2, 3] && answer.revision == 3 && pushed.last.map { if case .settings = $0 { true } else { false } } == true)
        #expect(answer.problem?.code == .failed && answer.problem?.message.hasPrefix("✗ ") == true)
        let field = answer.document?.field("notes.notion")
        #expect(field?.status == answer.problem?.message && field?.running == nil && field?.actions == ["test"])
    }

    /// A test that doesn't come back (Bedrock's credentials never found): shown `running`, with `cancel`; cancelled, its
    /// request is answered `cancelled`, and nothing it would have found is shown. Stopping one that isn't running (done
    /// meanwhile) does nothing. (No request ever leaves: the credentials never come.)
    @Test func cancellingATest() async throws {
        let (engine, id, _) = engine(#"{"provider": "bedrock"}"#)
        let service = try #require(engine.server.settings)
        service.loadCredentials = { _ in
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
        #expect(engine.send(ClientFrame(id: 2, .settingsAction(SettingsAction(field: "provider.test", name: "test"))), on: id).isEmpty)
        let started = try await pushes(engine, for: id) { !Self.notices($0).isEmpty }
        #expect(Self.notices(started) == [2])
        guard case let .settings(_, running)? = engine.send(ClientFrame(id: 3, .settingsGet), on: id).first?.message else {
            Issue.record("no answer")
            return
        }
        let test = running.document?.field("provider.test")
        #expect(test?.running == true && test?.actions == ["test", "cancel"] && test?.status == nil)
        let cancel = engine.send(ClientFrame(id: 4, .settingsAction(SettingsAction(field: "provider.test", name: "cancel"))), on: id)
        guard case let .settings(4, stopped)? = cancel.first?.message else { Issue.record("no answer: \(cancel)"); return }
        #expect(stopped.problem == nil && stopped.revision == 3 && stopped.document?.field("provider.test")?.running == nil)
        // Answered at once (perhaps with the cancel's own answer), though the test's task may still be on its way out.
        let ended = cancel.map(\.message) + (try await pushes(engine, for: id) { Self.answer(to: 2, in: cancel.map(\.message) + $0) != nil })
        let answer = try #require(Self.answer(to: 2, in: ended))
        #expect(answer.problem?.code == .cancelled && answer.revision == 3)
        #expect(answer.document?.field("provider.test")?.status == nil)
        // Nothing running: nothing to stop, nothing changes.
        guard case let .settings(5, idle)? = engine.send(ClientFrame(id: 5, .settingsAction(SettingsAction(field: "provider.test", name: "cancel"))), on: id).first?.message else {
            Issue.record("no answer")
            return
        }
        #expect(idle.problem == nil && idle.revision == 3)
        // The same test again while one runs: the new one replaces it, and the first is answered cancelled.
        #expect(engine.send(ClientFrame(id: 7, .settingsAction(SettingsAction(field: "provider.test", name: "test"))), on: id).isEmpty)
        _ = try await pushes(engine, for: id) { Self.notices($0).contains(4) }
        let again = engine.send(ClientFrame(id: 8, .settingsAction(SettingsAction(field: "provider.test", name: "test"))), on: id).map(\.message)
        let replaced = again + (try await pushes(engine, for: id) { Self.answer(to: 7, in: again + $0) != nil })
        #expect(Self.answer(to: 7, in: replaced)?.problem?.code == .cancelled)
        let last = engine.send(ClientFrame(id: 9, .settingsAction(SettingsAction(field: "provider.test", name: "cancel"))), on: id).map(\.message)
        let stoppedToo = last + (try await pushes(engine, for: id) { Self.answer(to: 8, in: last + $0) != nil })
        #expect(Self.answer(to: 8, in: stoppedToo)?.problem?.code == .cancelled)
        // A field without an action that takes a while has no cancel.
        guard case let .settings(6, refused)? = engine.send(ClientFrame(id: 6, .settingsAction(SettingsAction(field: "maxTokens", name: "cancel"))), on: id).first?.message else {
            Issue.record("no answer")
            return
        }
        #expect(refused.problem?.code == .notChangeable)
    }

    /// The settings' work isn't on the connection's queue: the watchdog (`longestBusy`) never counts it, however long
    /// the secret store takes.
    @Test func theSettingsAreOffTheConnectionsQueue() throws {
        let server = WireServer(environment: WireEnvironment(host: TestHost()))
        #expect(server.useTestSettings(config: #"{"provider": "anthropic"}"#))
        let id = try #require(server.connect(.trustedClient))
        _ = server.receive(try WireJSON.encode(ClientFrame(id: 1, .hello(Hello(client: "settings/test", capabilities: [Hello.settings])))), on: id)
        let busy = Locked<[Double]>(initialState: [])
        server.settings?.keySource = { (_: Provider) -> APIKeys.Source in
            // The secret store taking its time.
            Thread.sleep(forTimeInterval: 0.05)
            busy.withLock { $0.append(server.longestBusy) }
            return .none
        }
        let answers = server.receive(try WireJSON.encode(ClientFrame(id: 2, .settingsGet)), on: id)
        let seen = busy.withLock { $0 }
        #expect(answers.count == 1 && !seen.isEmpty && seen.allSatisfy { $0 == 0 }, "\(seen)")
    }
}
