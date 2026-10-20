import Foundation
import Testing
@testable import AllInOneIMECore

/// The platform's small-value store and clock (`Platform.defaults`, `Platform.clock`).
struct PlatformSeamTests {
    @Test func memoryStoreKeepsTypedValues() {
        let store = MemoryKeyValueStore()
        #expect(store.data(forKey: "a") == nil && store.string(forKey: "a") == nil && !store.bool(forKey: "a"))
        store.set("x", forKey: "a")
        store.set(true, forKey: "b")
        store.set(Data([1, 2]), forKey: "c")
        #expect(store.string(forKey: "a") == "x" && store.bool(forKey: "b") && store.data(forKey: "c") == Data([1, 2]))
        store.removeValue(forKey: "a")
        #expect(store.string(forKey: "a") == nil)
    }

    /// Each value set, and what string, Boolean and data reading it as each type gives.
    static let readings: [(set: @Sendable (any KeyValueStore) -> Void, string: String?, bool: Bool, data: Data?)] = [
        ({ $0.set(true, forKey: "k") }, "1", true, nil),
        ({ $0.set(false, forKey: "k") }, "0", false, nil),
        ({ $0.set("true", forKey: "k") }, "true", true, nil),
        ({ $0.set("TRUE", forKey: "k") }, "TRUE", true, nil),
        ({ $0.set("yEs", forKey: "k") }, "yEs", true, nil),
        ({ $0.set("1", forKey: "k") }, "1", true, nil),
        ({ $0.set("2", forKey: "k") }, "2", false, nil),
        ({ $0.set(" yes", forKey: "k") }, " yes", false, nil),
        ({ $0.set("y", forKey: "k") }, "y", false, nil),
        ({ $0.set("no", forKey: "k") }, "no", false, nil),
        ({ $0.set("", forKey: "k") }, "", false, nil),
        ({ $0.set(Data("hi".utf8), forKey: "k") }, nil, false, Data("hi".utf8)),
    ]

    /// A value read as another type reads as UserDefaults reads it, so what a shell keeps in its own store and the tests'
    /// memory agree.
    @Test func memoryStoreReadsOtherTypesAsUserDefaultsDoes() {
        for (index, reading) in Self.readings.enumerated() {
            let store = MemoryKeyValueStore()
            reading.set(store)
            #expect(store.string(forKey: "k") == reading.string && store.bool(forKey: "k") == reading.bool
                    && store.data(forKey: "k") == reading.data, "reading \(index)")
        }
    }

    #if canImport(Darwin)
    @Test func userDefaultsReadsTheSame() throws {
        let suite = "AllInOneIMECoreTests.PlatformSeam.\(UUID().uuidString)"
        let store = try #require(UserDefaultsStore(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        for (index, reading) in Self.readings.enumerated() {
            store.removeValue(forKey: "k")
            reading.set(store)
            #expect(store.string(forKey: "k") == reading.string && store.bool(forKey: "k") == reading.bool
                    && store.data(forKey: "k") == reading.data, "reading \(index)")
        }
    }
    #endif

    @Test func aClockATestMoves() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = FixedWallClock(start)
        #expect(clock.now == start)
        clock.advance(by: 90)
        #expect(clock.now == start.addingTimeInterval(90))
        let platform = Platform(defaults: MemoryKeyValueStore(), clock: clock)
        Platform.$override.withValue(platform) {
            #expect(Platform.current.clock.now == start.addingTimeInterval(90))
            // What the core dates goes by it.
            #expect(NoteDraft(text: "x").created == start.addingTimeInterval(90))
        }
    }

    /// AWS checks a request's signature against the real time, and credentials expire by it: a shell's or a test's clock
    /// changes neither.
    @Test func signingAndCredentialsGoByTheRealTime() throws {
        let fixed = Platform(defaults: MemoryKeyValueStore(), clock: FixedWallClock(Date(timeIntervalSince1970: 1_000_000)))
        try Platform.$override.withValue(fixed) {
            let today = SigV4Signer.amzDate(Date()).prefix(8)  // yyyyMMdd
            var request = URLRequest(url: try #require(URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/x")))
            SigV4Signer(credentials: AWSCredentials(accessKeyId: "AKID", secretAccessKey: "secret"), region: "us-east-1",
                        service: "bedrock").sign(&request, body: Data())
            #expect(request.value(forHTTPHeaderField: "X-Amz-Date")?.hasPrefix(today) == true)
            #expect(abs(AWSCredentialContext().now().timeIntervalSinceNow) < 60)
            // Credentials that expire in ten seconds: the settings look again then (by the fixed clock, decades away).
            var status = AWSProfileStatus(profile: "p")
            status.hasCredentials = true
            status.expiration = Date().addingTimeInterval(10)
            #expect((9...11).contains(status.secondsUntilChange()))
        }
    }

    /// A default clock is the one of the platform in use where the value is made: read then, it holds on another queue,
    /// which doesn't see `Platform.$override`.
    @Test func defaultClocksAreReadWhereTheyAreMade() async {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let fixed = Platform(defaults: MemoryKeyValueStore(), clock: FixedWallClock(start))
        let manager = Platform.$override.withValue(fixed) { ExtensionSourceManager(git: SwapRecoveryTests.NoGit()) }
        let elsewhere = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: manager.now()) }
        }
        #expect(elsewhere == start && manager.now() == start)
    }
}

/// What the interface calls the keys and places (`PlatformTerms`, `Platform.terms`): the Mac's symbols, Windows' names.
struct PlatformTermsTests {
    @Test func theMacsSymbols() {
        let mac = PlatformTerms.mac
        #expect([mac.copy, mac.paste, mac.again, mac.pick(2), mac.picks(1), mac.picks(3)] == ["⌘C", "⌃V", "⌘R", "⌘2", "⌘1", "⌘1–⌘3"])
        #expect(mac.voiceKey == "⌥" && mac.actionTap == "⌥" && mac.shortcut(.option, "Space") == "⌥Space")
        #expect([mac.enter, mac.shiftEnter, mac.backspace] == ["⏎", "⇧⏎", "⌫"])
        #expect(mac.isApp("/Applications/Calculator.app") && !mac.isApp("/Users/a/Calculator.app.zip") && !mac.isApp("C:/x/Word.lnk"))
    }

    @Test func windowsNames() {
        let windows = PlatformTerms.windows
        #expect([windows.copy, windows.paste, windows.again, windows.pick(2), windows.picks(1), windows.picks(3)]
                == ["Ctrl+C", "Ctrl+V", "Ctrl+R", "Ctrl+2", "Ctrl+1", "Ctrl+1–3"])
        // The keys follow the roles: the right Ctrl dictates, a tap of Ctrl is the action key.
        #expect(windows.voiceKey == "Ctrl" && windows.actionTap == "Ctrl" && windows.shortcut(.command, "D") == "Win+D")
        // Return, ⇧Return and Delete by the names Windows' keyboards print.
        #expect([windows.enter, windows.shiftEnter, windows.backspace] == ["Enter", "Shift+Enter", "Backspace"])
        #expect(windows.isApp(#"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Word.lnk"#) && windows.isApp("C:/Tools/x.EXE"))
        #expect(!windows.isApp("/Applications/Calculator.app"))
    }

    /// A shortcut recorded on the Mac reads as it is pressed elsewhere: on Windows ⌘ is Ctrl, ⌃ the Windows key. On the Mac
    /// it reads as it was recorded.
    @Test func aRecordedShortcutAsTheSystemNamesIt() {
        let j = KeyShortcut(keyCode: 0x26, modifiers: .command, name: "⌘J")
        let controlReturn = KeyShortcut(keyCode: VirtualKey.returnKey, modifiers: .control, name: "⌃⏎")
        let f5 = KeyShortcut(keyCode: 0x60, modifiers: [.option, .shift], name: "⌥⇧F5")
        let delete = KeyShortcut(keyCode: VirtualKey.delete, modifiers: [.command, .option], name: "⌥⌘⌫")
        #expect([j, controlReturn, f5, delete].map { PlatformTerms.mac.name($0) } == ["⌘J", "⌃⏎", "⌥⇧F5", "⌥⌘⌫"])
        #expect([j, controlReturn, f5, delete].map { PlatformTerms.windows.name($0) }
                == ["Ctrl+J", "Win+Enter", "Alt+Shift+F5", "Ctrl+Alt+Backspace"])
        // Recorded on Windows (kept as ⌘⇧J), and a key the Mac doesn't have: as they were recorded there.
        let pc = KeyShortcut(usage: 0x0D, modifiers: [.command, .shift], name: "Ctrl+Shift+J")
        let f24 = KeyShortcut(usage: 0x73, modifiers: .command, name: "Ctrl+F24")
        #expect([pc, f24].map { PlatformTerms.windows.name($0) } == ["Ctrl+Shift+J", "Ctrl+F24"])
        // As the action key: Space in the interface language.
        let space = KeyShortcut(keyCode: VirtualKey.space, modifiers: .control, name: "⌃空格")
        let (en, zh) = (InterfaceWords(language: "en"), InterfaceWords(language: "zh-Hans"))
        #expect(en.name(.shortcut(space), terms: .windows) == "Win+Space" && zh.name(.shortcut(space), terms: .windows) == "Win+空格")
        #expect(en.name(.shortcut(j), terms: .windows) == "Ctrl+J" && en.name(.shortcut(j), terms: .mac) == "⌘J")
    }

    /// The panel's text takes ⏎, ⇧⏎ and ⌫ from the terms in every language: no catalog key first used in Session/ (the
    /// presenter's, the session's lines) writes them, nor any of its translations; each translation has the keys where
    /// its English does (a German footer on Windows).
    @Test func theCatalogTakesTheKeysFromTheTerms() throws {
        let data = try Data(contentsOf: InterfaceTextTests.root.appendingPathComponent("Resources/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(catalog["strings"] as? [String: [String: Any]])
        var panel = 0
        for (key, entry) in entries where entry["extractionState"] as? String != "stale"
            && (entry["comment"] as? String ?? "").contains("Sources/AllInOneIMECore/Session/") {
            panel += 1
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let values = localizations.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
            #expect(values.count == localizations.count, "\(key)")
            for text in [key] + values {
                #expect(!["⏎", "⌫"].contains { text.contains($0) }, "\(key): \(text)")
            }
        }
        #expect(panel > 30)
        let de = try StringCatalog.table("de", from: data), windows = PlatformTerms.windows
        let footer: UIString = "\(windows.shiftEnter) refine · \(windows.enter) insert · \(windows.backspace) delete · Esc clear · ↑↓ choose"
        #expect(InterfaceText.translate(footer, in: de)
                == "Shift+Enter verfeinern · Enter einfügen · Backspace löschen · Esc leeren · ↑↓ auswählen")
    }

    @Test func theSystemsOwnByDefault() {
        #if os(Windows)
        #expect(Platform.systemTerms == .windows)
        #else
        #expect(Platform.systemTerms == .mac)
        #endif
    }

    /// The action key and the composer's own messages name the keys and places as the terms do.
    @Test func theActionKeyAndTheMessages() {
        let (en, zh) = (InterfaceWords(language: "en"), InterfaceWords(language: "zh-Hans"))
        #expect([en.name(.optionTap, terms: .mac), en.name(.optionSpace, terms: .mac)] == ["Tap ⌥", "⌥Space"])
        #expect([zh.name(.optionTap, terms: .mac), zh.name(.optionSpace, terms: .mac)] == ["单按 ⌥", "⌥空格"])
        #expect([en.name(.optionTap, terms: .windows), en.name(.optionSpace, terms: .windows)] == ["Tap Ctrl", "Ctrl+Space"])
        #expect([zh.name(.optionTap, terms: .windows), zh.name(.optionSpace, terms: .windows)] == ["单按 Ctrl", "Ctrl+空格"])
        #expect(en.name(.enter, terms: .windows) == "Enter" && en.name(.enter, terms: .mac) == "⏎")
        #expect(en.name(.space, terms: .windows) == "Space")
        let mac = Composer.Messages.make(language: "en", terms: .mac), windows = Composer.Messages.make(language: "en", terms: .windows)
        #expect(mac.holdToTalk == "Hold right ⌥ to talk" && windows.holdToTalk == "Hold right Ctrl to talk")
        #expect(mac.openedTerminal == "Opened Claude Code in Terminal" && windows.openedTerminal == "Opened Claude Code in a terminal")
        #expect(windows.ranInTerminal == "Running in a terminal" && windows.openedAgent == "Opened {agent} in a terminal")
        #expect(mac.reply.reading == "Reading the screenshot on this Mac (slower the first time)…")
        #expect(windows.reply.reading == "Reading the screenshot on this PC (slower the first time)…")
        #expect(windows.reply.hint == "Select or copy their message, or take a screenshot and press Ctrl+V; or write what to reply")
        #expect(Composer.Messages.make(language: "zh-Hans", terms: .windows).holdToTalk == "按住右 Ctrl 说话")
        #expect(mac.pickRecipient == "Pick a recipient first: ↑↓ choose, ⏎ / Tab confirm (or type a phone number or email)")
        #expect(windows.pickRecipient == "Pick a recipient first: ↑↓ choose, Enter / Tab confirm (or type a phone number or email)")
        #expect(TranslateMode.Messages.make(language: "en", terms: .mac).failed("offline") == "Not translated: offline (⏎ to retry)")
        #expect(TranslateMode.Messages.make(language: "zh-Hans", terms: .windows).failed("offline") == "没翻译成：offline（Enter 重试）")
        // A command's summary and what the action key does with it.
        #expect(en.summary(.reply, terms: .windows) == "Reply: Ctrl+V their message or a screenshot")
        let terminal = CustomCommand(name: "top", type: .terminal, argv: ["/usr/bin/top"])
        #expect(en.customKind(terminal, terms: .mac) == "Run in Terminal: top" && en.customKind(terminal, terms: .windows) == "Run in a terminal: top")
        var config = Config.default
        config.claudeInBackground = false
        #expect(en.action(.agent, input: .english, config: config, terms: .windows) == "open Claude Code in a terminal")
        #expect(en.action(.agent, input: .english, config: config, terms: .mac) == "open Claude Code in Terminal")
    }
}
