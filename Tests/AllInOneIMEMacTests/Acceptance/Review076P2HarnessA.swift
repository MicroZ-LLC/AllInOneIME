extension Review076P2Harness {
    static let swiftA = #"""

    // MARK: - Review076 P2 child (in place of main.swift's dispatch)

    struct P2AppleModel: AppleModelBackend {
        var availability: AppleModelAvailability { .appleIntelligenceNotEnabled }
        var contextSize: Int { 4096 }
        var supportedLanguages: Set<String> { ["en", "zh"] }
        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    /// Terminal answers the window-id query, then the contents query times out. No Apple event or app is launched.
    final class P2TerminalProcess: ProcessLauncher, @unchecked Sendable {
        final class Launched: LaunchedProcess, @unchecked Sendable {
            var processIdentifier: Int32 { 0 }
            var isRunning: Bool { false }
            var treeIsRunning: Bool { false }
            var terminationStatus: Int32 { 0 }
            func waitUntilExit() {}
            func terminate() -> Bool { false }
            func kill() -> Bool { false }
        }

        private let lock = NSLock()
        private var calls = 0
        var canLaunch: Bool { true }
        var environment: [String: String] { [:] }
        var loginEnvironment: [String: String] { [:] }
        func isRunnable(_ program: URL) -> Bool { true }
        func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess {
            let call = lock.withLock { calls += 1; return calls }
            if call > 1 { throw ProcessOutput.TimedOut(program: "osascript", seconds: 0.1) }
            if case let .pipe(pipe) = spec.standardOutput {
                try pipe.fileHandleForWriting.write(contentsOf: Data("101\n".utf8))
                try pipe.fileHandleForWriting.close()
            }
            if case let .pipe(pipe) = spec.standardError { try pipe.fileHandleForWriting.close() }
            let launched = Launched()
            spec.onExit?(launched)
            return launched
        }
    }

    /// The child's keychain: in memory, the reads of a key itself counted (`read`: what may make macOS ask for the login
    /// password), and every look at an account in `held` waiting until `release`.
    final class P2Keys: @unchecked Sendable {
        private let lock = NSLock()
        private var reads: [String] = []
        private var held: Set<String> = []
        private let gate = DispatchSemaphore(value: 0)
        let items = APIKeys.Keychain.inMemory()

        var store: APIKeys.Keychain {
            var store = items
            let items = items
            store.read = { [self] account in
                lock.withLock { reads.append(account) }
                wait(account)
                return items.read(account)
            }
            store.attributes = { [self] account in
                wait(account)
                return items.attributes(account)
            }
            return store
        }

        var keyReads: [String] { lock.withLock { reads } }
        func forgetReads() { lock.withLock { reads = [] } }
        func hold(_ account: String) { lock.withLock { _ = held.insert(account) } }
        func release() {
            lock.withLock { held = [] }
            for _ in 0..<64 { gate.signal() }
        }
        private func wait(_ account: String) {
            if lock.withLock({ held.contains(account) }) { gate.wait() }
        }
        /// A key as another launch saved it for `host`: in the keychain, never read in this process.
        func keep(_ provider: Provider, host: String) {
            _ = items.write(provider.rawValue, "sk-test-\(provider.rawValue)-EXAMPLE", "AllInOneIME: \(provider.rawValue)", host, "MPLE", Date())
        }
    }

    /// A text field that tells its text and caret `lag` seconds late (Chromium's), each change in the order made: what it
    /// holds (`document`) at once, what it tells (`told`) later; its marked text as it is set.
    final class P2Field: NSObject, IMKTextInput {
        var document = ""
        private(set) var told = ""
        var lag: TimeInterval = 0
        var app = "com.example.review076"
        /// The marked text in the field now, and each one set, in order.
        private(set) var marked = ""
        private(set) var marks: [String] = []

        func insertText(_ string: Any!, replacementRange: NSRange) {
            let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
            marked = ""
            let whole = document as NSString
            if replacementRange.location != NSNotFound, NSMaxRange(replacementRange) <= whole.length {
                document = whole.replacingCharacters(in: replacementRange, with: text)
            } else {
                document += text
            }
            let now = document
            if lag == 0 { told = now } else { DispatchQueue.main.asyncAfter(deadline: .now() + lag) { self.told = now } }
        }
        func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
            marked = (string as? NSAttributedString)?.string ?? string as? String ?? ""
            marks.append(marked)
        }
        func selectedRange() -> NSRange { NSRange(location: (told as NSString).length, length: 0) }
        func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func attributedSubstring(from range: NSRange) -> NSAttributedString! {
            let whole = told as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= whole.length else { return nil }
            return NSAttributedString(string: whole.substring(with: range))
        }
        func length() -> Int { (told as NSString).length }
        func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                            inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
        func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
            lineRect?.pointee = NSRect(x: 420, y: 560, width: 1, height: 18)
            return [:]
        }
        func validAttributesForMarkedText() -> [Any]! { [] }
        func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
        func selectMode(_ modeIdentifier: String!) {}
        func supportsUnicode() -> Bool { true }
        func bundleIdentifier() -> String! { app }
        func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
        func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
        func uniqueClientIdentifierString() -> String! { "review076-\(app)" }
        func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
        func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
            NSRect(x: 420, y: 560, width: 1, height: 18)
        }
    }

    @MainActor
    enum P2 {
        static let intended = "Thanks for the quick reply, I will look into it tomorrow morning and get back to you."
        static var controller: AllInOneIMEInputController!
        static let keys = P2Keys()
        static var home: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? "", isDirectory: true) }

        static func say(_ key: String, _ value: Any) {
            print("KV\t\(key)\t" + Data("\(value)".utf8).base64EncodedString())
            fflush(stdout)
        }

        /// The run loop run for `seconds` at most, until `done`.
        @discardableResult
        static func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if done() { return true }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.002))
            }
            return done()
        }

        static var revision = 0
        /// `config` as the input method's config file (`Config.selfTestURL`), its date another each time.
        static func write(_ config: Config, to url: URL) {
            revision += 1
            Config.selfTestURL = url
            try? config.write(to: url)
            try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(revision))],
                                                   ofItemAtPath: url.path)
        }

        /// A controller of English only (no pinyin engine), typing out with typos (one wherever one may be).
        static func make() {
            guard let made = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
                print("FAIL no input controller")
                exit(3)
            }
            controller = made
            var config = Config.default
            config.setOrder([Language.english])
            config.typeOutMistakes = true
            config.autocomplete = false
            controller.services.loadSettings = { config }
            controller.services.secureInputActive = { false }
            controller.applySettings()
            LearnedShared.store = LearnedStore(file: nil, autocomplete: AutocompleteStore(), temperature: TemperatureSupport(file: nil))
        }

        static func press(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], into field: P2Field) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: code)!
            if !controller.handle(event, client: field) { field.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }

        /// `intended` typed out into `field`, until a typo is in it that the field doesn't tell yet: whether one came. A
        /// step every 100 ms, the field 60 ms late (as ControllerOffMainTests has it).
        static func typeOutToATypo(_ field: P2Field) -> Bool {
            controller.typeOutRandom = { 0.001 }
            controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 100_000_000) }
            field.lag = 0.06
            controller.apply([.typeOut(intended)], client: field)
            return pump(10) { !intended.hasPrefix(field.document) && field.told != field.document }
        }

        // MARK: Item 13

        /// A type-out with a typo in a field that tells its text late; a click outside (`pointerDown`: the rest to go in)
        /// while the field doesn't tell the typo yet, so the stop settles later; the field tells it, and is left
        /// (`deactivateServer`) before the stop has settled.
        static func leave() {
            make()
            let field = P2Field()
            let caught = typeOutToATypo(field)
            // The settling waits long enough for the field to be left first.
            controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 3_000_000_000) }
            controller.pointerDown()
            let settling = controller.stopsInsertingRest == true && controller.isTypingOut
            let told = pump(1) { field.told == field.document }
            field.lag = 0
            let before = field.document
            controller.deactivateServer(field)
            pump(0.3)
            say("caught", caught && settling && told)
            say("before", before)
            say("typed", field.document)
            say("typingOut", controller.isTypingOut)
        }

        // MARK: Item 15

        /// The keys typed while a stop settles, in a Chromium app: "@" (which composes: the input method takes it and puts
        /// nothing in, so a space is marked for it and taken out once the key is done) and a letter.
        static let heldKeys: [(String, UInt16, NSEvent.ModifierFlags)] = [("@", 19, .shift), ("a", 0, [])]

        /// The keys as typed with nothing typed out: what each marks, and that it is taken out before the next.
        static func heldControl() {
            make()
            controller.chromiumApp = { _ in true }
            let field = P2Field()
            var markedAtKey: [String] = []
            for (key, code, flags) in heldKeys {
                markedAtKey.append(field.marked)
                press(key, code: code, flags: flags, into: field)
                pump(0.05)
            }
            say("marks", field.marks.map { "[\($0)]" }.joined())
            say("markedBeforeEachKey", markedAtKey.map { "[\($0)]" }.joined())
            say("markedAfter", "[\(field.marked)]")
            say("input", controller.preedit)
        }

        /// The same keys typed while a type-out's stop settles (held: `keysWhileStopping`), then the stop settled at once,
        /// as a key that can't wait settles it (`stopTyping(insertingRest: true, waiting: false)`, what ⏎ does before it
        /// is handled itself): what is marked in the field when that returns, which is what the next key finds.
        static func heldKeysReplayed() {
            make()
            controller.chromiumApp = { _ in true }
            let field = P2Field()
            let caught = typeOutToATypo(field)
            for (key, code, flags) in heldKeys.prefix(1) {
                press(key, code: code, flags: flags, into: field)
                pump(0.01)
            }
            let held = controller.keysWhileStopping.count
            controller.stopTyping(insertingRest: true, waiting: false)
            say("caught", caught && held == 1)
            say("markedAfterReplay", "[\(field.marked)]")
            say("hasMarkedText", controller.hasMarkedText)
            say("marks", field.marks.map { "[\($0)]" }.joined())
            pump(0.3)
            say("markedLater", "[\(field.marked)]")
            say("input", controller.preedit)
            say("typingOut", controller.isTypingOut)
        }

    """#
}
