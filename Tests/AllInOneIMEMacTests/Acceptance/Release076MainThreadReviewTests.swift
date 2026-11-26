import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import AppKit
import Foundation
import InputMethodKit
import Testing

/// Independent acceptance tests for the 0.7.6 main-thread and one-time wiring review items.
/// Prefer runtime behavioral tests through existing seams (`FieldReading`, `ClipboardHistoryStore`,
/// `ClipboardRecorder`, `KeyboardLayout.Cache`, `PanelAnchor.Memory`, `FieldAnchor`, `GhostPlacement`,
/// `TypeOut.Typist`, and `RimeService.EnglishLoad` in a compiled child). Where code lives only in the
/// `AllInOneIME` executable target, follow every helper file implementing the path and check generically
/// for blocking calls or inline Accessibility reads on the main thread.
@Suite(.serialized)
struct Release076MainThreadReviewTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - Item 3: One-time global UI wiring

    /// Item 3. Global UI wiring (preview attachment, icon and clipboard-refresh callbacks) belongs to app
    /// startup (`wireUI`), guarded against repeated runs, and never repeats in per-session creation
    /// (`SessionServices.mac` or `InputController.makeSession`).
    @Test func globalUIWiringIsNotRepeatedForEachSession() throws {
        let servicesSource = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/SessionServices+Mac.swift"))
        let controllerSource = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController.swift"))
        let mainSource = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/main.swift"))

        let mac = try SwiftSourceAudit.body(of: "static var mac: SessionServices", in: servicesSource)
        let makeSession = try SwiftSourceAudit.body(of: "private func makeSession()", in: controllerSource)
        let wireUI = try SwiftSourceAudit.body(of: "static func wireUI()", in: servicesSource)

        let globalHooks = [
            "ImagePreview.shared.attach",
            "CandidateView.itemIcon",
            "ItemIcons.shared.onLoaded",
            "ClipboardHistoryShared.keptLater",
            "InstantFiles.shared.onKept",
            "wireUI(",
        ]
        for hook in globalHooks {
            #expect(!mac.contains(hook), "SessionServices.mac repeats global wiring: \(hook)")
            #expect(!makeSession.contains(hook), "InputController.makeSession repeats global wiring: \(hook)")
        }
        #expect(wireUI.contains("guard") && wireUI.contains("uiWirings"), "wireUI must guard against repeating global wiring")
        #expect(mainSource.contains("SessionServices.wireUI()"), "startup must perform one-time UI wiring")
    }

    // MARK: - Item 25: Password field & Accessibility off main

    /// Item 25. First-key context reading must never invoke the Accessibility password-field reader
    /// synchronously on the main thread; it fails closed and marks the answer as following off-main.
    @Test @MainActor func firstKeyDoesNotReadPasswordFieldThroughAccessibility() throws {
        let field = ReviewTextInput(text: "hello world", caret: 5)
        let probe = PasswordReaderProbe()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }

        let reading = FieldReading(
            isTerminal: { _ in false },
            secureInputActive: { false },
            passwordField: {
                probe.record(onMain: Thread.isMainThread)
                if !Thread.isMainThread {
                    _ = gate.wait(timeout: .now() + 2)
                }
                return false
            }
        )

        let start = ProcessInfo.processInfo.systemUptime
        let context = reading.context(in: field) { _ in [.secure, .passwordField] }
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        #expect(elapsed < 0.25, "first-key context blocked main for \(elapsed)s")
        #expect(!probe.calledOnMain, "first key called Accessibility password check on the main thread")
        #expect(probe.calls == 0, "first key synchronously invoked the Accessibility password reader")
        #expect(context.passwordFieldUnknown, "pending password-field answer must fail closed")
        #expect(context.passwordFieldFollows, "first key must defer the password-field check off main")

        // Follow the controller's off-main helper (`readPasswordField`): its main-thread path must not call AX inline.
        let focusedAX = try SwiftSourceAudit.focusedFieldAXMembers(in: Self.source("Sources/AllInOneIME/FocusedField.swift"))
        let overlay = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/AutocompleteOverlay.swift"))
        let readPasswordField = try SwiftSourceAudit.body(of: "func readPasswordField(", in: overlay)
        let readPasswordMain = SwiftSourceAudit.mainThreadCode(in: readPasswordField)
        #expect(SwiftSourceAudit.axCalls(in: readPasswordMain, focusedFieldAX: focusedAX).isEmpty,
                "readPasswordField calls Accessibility on main: \(SwiftSourceAudit.axCalls(in: readPasswordMain, focusedFieldAX: focusedAX))")
        #expect(SwiftSourceAudit.blockingMatches(in: readPasswordField).isEmpty,
                "readPasswordField contains a blocking call: \(SwiftSourceAudit.blockingMatches(in: readPasswordField))")
    }

    /// Item 25. An autocomplete or Code's-words pause read (`FieldReading.contextAfterPause`, triggered by
    /// `readFieldAfterPause`) also runs on the main thread and must never call the Accessibility
    /// password-field check synchronously on main.
    @Test @MainActor func pauseReadDoesNotReadPasswordFieldThroughAccessibility() throws {
        let field = ReviewTextInput(text: "hello world", caret: 5)
        for id in [1, -1] {
            let probe = PasswordReaderProbe()
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }

            let reading = FieldReading(
                isTerminal: { _ in false },
                secureInputActive: { false },
                passwordField: {
                    probe.record(onMain: Thread.isMainThread)
                    if !Thread.isMainThread {
                        _ = gate.wait(timeout: .now() + 2)
                    }
                    return false
                }
            )

            let start = ProcessInfo.processInfo.systemUptime
            let context = reading.contextAfterPause(in: field, id: id)
            let elapsed = ProcessInfo.processInfo.systemUptime - start

            #expect(elapsed < 0.25, "contextAfterPause(id: \(id)) blocked main for \(elapsed)s")
            #expect(!probe.calledOnMain,
                    "contextAfterPause(id: \(id)) called the Accessibility password reader synchronously on the main thread")
            if probe.calls == 0 {
                let claimedKnownSafe = context.read.contains(.passwordField)
                    && !context.passwordFieldUnknown
                    && !context.passwordFieldFollows
                    && context.field?.secure != true
                #expect(!claimedKnownSafe,
                        "contextAfterPause(id: \(id)) marked the field known non-password without reading Accessibility")
            }
        }

        // Follow the executable caller (`readFieldAfterPause`): it runs on DispatchQueue.main.async and must not
        // invoke Accessibility or passwordFieldByAccessibility inline on the main thread.
        let focusedAX = try SwiftSourceAudit.focusedFieldAXMembers(in: Self.source("Sources/AllInOneIME/FocusedField.swift"))
        let overlay = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/AutocompleteOverlay.swift"))
        let readAfterPause = try SwiftSourceAudit.body(of: "func readFieldAfterPause(", in: overlay)
        let readAfterPauseMain = SwiftSourceAudit.mainThreadCode(in: readAfterPause)
        let axCalls = SwiftSourceAudit.axCalls(in: readAfterPauseMain, focusedFieldAX: focusedAX)
        #expect(axCalls.isEmpty, "readFieldAfterPause calls Accessibility on main: \(axCalls)")
        #expect(!readAfterPauseMain.contains("passwordFieldByAccessibility("),
                "readFieldAfterPause must not call passwordFieldByAccessibility synchronously on main")
        #expect(SwiftSourceAudit.blockingMatches(in: readAfterPause).isEmpty,
                "readFieldAfterPause contains a blocking call: \(SwiftSourceAudit.blockingMatches(in: readAfterPause))")
    }

    /// Item 25. Panel placement and ghost placement must never call Accessibility synchronously on the main
    /// thread—neither in the top-level entry points (`anchor`, `placeGhost`) nor in their helper files
    /// (`InputController+PanelAnchor.swift`, `askGhostField`, `showGhost`). Also verifies the pure Mac seams
    /// accept a deferred (`nil`) window/caret/field answer and update once the answer arrives.
    @Test @MainActor func panelAndGhostPlacementDoNotCallAccessibilityInline() throws {
        // Runtime seam check: deferred window and caret answers return immediately and settle later.
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        let field = PanelAnchor.Field(client: ObjectIdentifier(ReviewTextInput()), app: "com.example.App", session: 1)
        var memory = PanelAnchor.Memory()
        memory.enter(field)
        memory.learnWindow { nil } // Pending off-main read.
        #expect(memory.windowAsked && memory.window == nil)

        let client = ReviewTextInput(text: "abc", caret: 3)
        client.lineRect = CGRect(x: 100, y: 682, width: 1, height: 18) // Top-left corner of window, untrusted once window is known.
        var lastByApp: [String: CGRect] = [:]
        memory.learned(window: (frame: window, timedOut: false))
        #expect(memory.window == window)
        let placed = FieldAnchor.place(in: client, app: field.app, selection: nil, memory: &memory,
                                       lastByApp: &lastByApp, screens: [screen], pointer: { .zero },
                                       accessibility: { _ in nil }) // Pending off-main AX caret read.
        #expect(placed.placement.reasks, "untrusted anchor with pending AX read must fall back and schedule re-ask")

        let ghostSize = CGSize(width: 120, height: 18)
        let caret = CGRect(x: 200, y: 300, width: 0, height: 18)
        let pendingGhost = GhostPlacement.frame(size: ghostSize, caret: caret, visible: screen, field: nil, chrome: 30, minimumText: 20)
        let clippedGhost = GhostPlacement.frame(size: ghostSize, caret: caret, visible: screen,
                                                field: CGRect(x: 180, y: 280, width: 90, height: 40), chrome: 30, minimumText: 20)
        #expect(pendingGhost != nil && clippedGhost != nil && (clippedGhost?.width ?? 0) < (pendingGhost?.width ?? 0))

        // Helper-following generic source checks across every file implementing panel and ghost placement.
        let focusedAX = try SwiftSourceAudit.focusedFieldAXMembers(in: Self.source("Sources/AllInOneIME/FocusedField.swift"))
        #expect(focusedAX.contains("caret") && focusedAX.contains("windowFrame") && focusedAX.contains("frame") && focusedAX.contains("isSecure"),
                "FocusedField AX classifier missed known AX readers: \(focusedAX)")

        let controllerSource = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController.swift"))
        let anchorBody = try SwiftSourceAudit.body(of: "func anchor(", in: controllerSource)
        let panelAnchorHelper = SwiftSourceAudit.stripCommentsAndStrings(
            try Self.source("Sources/AllInOneIME/InputController+PanelAnchor.swift")
        )
        let overlaySource = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/AutocompleteOverlay.swift"))
        let showGhost = try SwiftSourceAudit.body(of: "func showGhost(", in: overlaySource)
        let placeGhost = try SwiftSourceAudit.body(of: "func placeGhost(", in: overlaySource)
        let askGhostField = try SwiftSourceAudit.body(of: "func askGhostField(", in: overlaySource)

        let checkedPaths: [(label: String, body: String)] = [
            ("InputController.anchor", anchorBody),
            ("InputController+PanelAnchor.swift", panelAnchorHelper),
            ("AutocompleteOverlay.showGhost", showGhost),
            ("AutocompleteOverlay.placeGhost", placeGhost),
            ("AutocompleteOverlay.askGhostField", askGhostField),
        ]
        for (label, body) in checkedPaths {
            let mainCode = SwiftSourceAudit.mainThreadCode(in: body)
            let axCalls = SwiftSourceAudit.axCalls(in: mainCode, focusedFieldAX: focusedAX)
            #expect(axCalls.isEmpty, "\(label) calls Accessibility synchronously on main: \(axCalls)")
            let blocking = SwiftSourceAudit.blockingMatches(in: body)
            #expect(blocking.isEmpty, "\(label) contains a blocking call: \(blocking)")
        }
    }

    // MARK: - Item 27: iCloud key migration and config I/O off main

    /// Item 27. Keychain migration, config reads/writes, and sync runs stay off the main thread across both
    /// `ICloudSyncController.swift` and `ICloudSyncController+Keys.swift`.
    @Test func iCloudKeyMigrationAndConfigIOStayOffMain() throws {
        let controller = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/ICloudSyncController.swift"))
        let keysHelper = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/ICloudSyncController+Keys.swift"))

        // Neither file may ever block on a wait, sleep, or synchronous queue hop.
        #expect(SwiftSourceAudit.blockingMatches(in: controller).isEmpty,
                "ICloudSyncController.swift has blocking call(s): \(SwiftSourceAudit.blockingMatches(in: controller))")
        #expect(SwiftSourceAudit.blockingMatches(in: keysHelper).isEmpty,
                "ICloudSyncController+Keys.swift has blocking call(s): \(SwiftSourceAudit.blockingMatches(in: keysHelper))")

        let start = try SwiftSourceAudit.body(of: "func start()", in: controller)
        let run = try SwiftSourceAudit.body(of: "func run()", in: controller)
        let runIfOn = try SwiftSourceAudit.body(of: "private func runIfOn()", in: controller)
        let settings = try SwiftSourceAudit.body(of: "private var settings:", in: controller)
        let config = try SwiftSourceAudit.body(of: "private var config:", in: controller)
        let keySyncOnQueue = try SwiftSourceAudit.body(of: "func keySyncOnQueue(", in: keysHelper)

        // Follow `run()` excluding its `engine.writeConfig = { ... }` callback (which runs on the sync queue).
        let (runWithoutWriteCallback, writeConfigClosure) = SwiftSourceAudit.stripAssignedClosure("engine.writeConfig", in: run)

        let mainThreadPaths: [(label: String, body: String)] = [
            ("ICloudSyncController.start", start),
            ("ICloudSyncController.run", runWithoutWriteCallback),
            ("ICloudSyncController.runIfOn", runIfOn),
            ("ICloudSyncController+Keys.keySyncOnQueue", keySyncOnQueue),
        ]
        let forbiddenOnMain = ["applyKeySync(", "keys.turn(", "keys.listCopyBack(", "Config.load(", "ICloudSync.writeConfig(", "engine.run("]
        for (label, body) in mainThreadPaths {
            let mainCode = SwiftSourceAudit.mainThreadCode(in: body)
            for forbidden in forbiddenOnMain {
                #expect(!mainCode.contains(forbidden), "\(label) runs \(forbidden) synchronously on main")
            }
        }

        // `keySyncOnQueue` must dispatch `applyKeySync` onto the background sync queue (not inline or on main).
        #expect(keySyncOnQueue.contains("queue.async"), "keySyncOnQueue must dispatch key migration onto the background sync queue")
        #expect(keySyncOnQueue.contains("applyKeySync("), "keySyncOnQueue must perform applyKeySync on the background queue")

        // Follow `settings` -> `config`: polling must read cached `LiveConfig.current`, not `Config.load(`.
        #expect(!settings.contains("Config.load("), "settings reparses the config on main")
        #expect(!config.contains("Config.load("), "config reparses the config on main")
        #expect(config.contains("LiveConfig.current"), "config must use cached LiveConfig.current for the live config file")

        // `engine.writeConfig` must write off main (only notifications hop asynchronously to main).
        let writeCallback = try #require(writeConfigClosure, "run() must configure engine.writeConfig")
        #expect(SwiftSourceAudit.blockingMatches(in: writeCallback).isEmpty,
                "writeConfig has blocking call(s): \(SwiftSourceAudit.blockingMatches(in: writeCallback))")
        let writeMainBlocks = SwiftSourceAudit.nestedMainCallbacks(in: writeCallback)
        #expect(!writeMainBlocks.contains("ICloudSync.writeConfig(") && !writeMainBlocks.contains("Config.load("),
                "writeConfig must not run config file I/O on the main queue")
    }

    // MARK: - Item 28: Clipboard history disk I/O & image preparation off main

    /// Item 28. Every clipboard history mutation (`record`, `trim`, `add`, `discard`, `clear`) must enqueue
    /// disk work and return promptly even while the background `writes` queue is busy reading the history file.
    @Test @MainActor func clipboardHistoryMutationsNeverWaitForDisk() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-mut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("history.json")
        let existing = Data(#"{"items":[{"text":"older","copiedAt":1800000000},{"text":"oldest","copiedAt":1799999999}]}"#.utf8)
        try existing.write(to: url)

        let entered = Locked(initialState: (started: false, continuation: CheckedContinuation<Void, Never>?.none))
        let gate = DispatchSemaphore(value: 0)
        var released = false
        let releaseGate = {
            if !released {
                released = true
                gate.signal()
            }
        }
        let store = ClipboardHistoryStore(url: url, readFile: { file in
            let waiter = entered.withLock { state -> CheckedContinuation<Void, Never>? in
                state.started = true
                defer { state.continuation = nil }
                return state.continuation
            }
            waiter?.resume()
            _ = gate.wait(timeout: .now() + 3) // Background `writes` queue only; bounded if a mutation regresses.
            return try? Data(contentsOf: file)
        })
        defer {
            releaseGate()
            store.waitForWrites()
            try? FileManager.default.removeItem(at: folder)
        }

        // Wait until the serial `writes` queue is actively blocked inside `readFile`.
        await withCheckedContinuation { continuation in
            let alreadyStarted = entered.withLock { state -> Bool in
                if state.started { return true }
                state.continuation = continuation
                return false
            }
            if alreadyStarted { continuation.resume() }
        }

        let img1 = try Self.largePNG(width: 4, height: 4, fill: 0x40)
        let img2 = try Self.largePNG(width: 4, height: 4, fill: 0x90)
        guard case let .ready(ready1) = store.prepare(img1),
              case let .ready(ready2) = store.prepare(img2) else {
            Issue.record("could not prepare small test images")
            return
        }

        let start = ProcessInfo.processInfo.systemUptime
        _ = store.record("fresh", at: Date(timeIntervalSince1970: 1_800_000_010), limit: 20, savingLater: true)
        store.trim(to: 1)
        _ = store.add(ready1, at: Date(timeIntervalSince1970: 1_800_000_011), limit: 20)
        store.discard(ready2)
        store.clear()
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        #expect(elapsed < 0.25, "clipboard mutations blocked main for \(elapsed)s while disk queue was busy")
        releaseGate()
        await store.waitForLoad()
        store.waitForWrites()
        #expect(store.items.isEmpty)

        // Generic source check across all mutation methods (excluding the explicit test-only `waitForWrites`).
        let source = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIMEMac/ClipboardHistoryStore.swift"))
        for declaration in ["public func record(", "public func add(", "public func discard(", "public func trim(",
                            "public func clear()", "private func keep(", "private func removeUnlisted()"] {
            let operation = try SwiftSourceAudit.body(of: declaration, in: source)
            let blocking = SwiftSourceAudit.blockingMatches(in: operation)
            #expect(blocking.isEmpty, "\(declaration) contains a blocking call: \(blocking)")
        }
    }

    /// Item 28. Reading `NSPasteboard` stays on the main thread (it is a single shared AppKit object; off-main reads
    /// raced main-thread uses and crashed in `-[NSPasteboard _updateTypeCacheIfNeeded]`). What must stay off main is
    /// image preparation (decoding, thumbnailing, PNG encoding, file writes) through `ClipboardRecorder.imageWork`.
    @Test @MainActor func clipboardPollingDoesNotPrepareImagesInline() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ClipboardHistoryStore(url: folder.appendingPathComponent("history.json"))
        defer {
            store.waitForWrites()
            try? FileManager.default.removeItem(at: folder)
        }
        await store.waitForLoad()
        let largeImage = try Self.largePNG(width: 4000, height: 4000)
        let source = ReviewImageSource(changeCount: 0, types: [], payload: nil)
        let recorder = ClipboardRecorder(source: source, store: store, secureInput: { false }, frontmostApp: { nil })
        #expect(recorder.poll(limit: 20) == .notText)

        let defaultWork = recorder.imageWork
        let gate = DispatchSemaphore(value: 0)
        var released = false
        defer { if !released { gate.signal() } }
        let probe = Locked(initialState: ImageWorkProbe())
        recorder.imageWork = { prepare, done in
            probe.withLock { $0.scheduled += 1 }
            defaultWork({
                let onMain = Thread.isMainThread
                probe.withLock { $0.preparedOnMain = onMain }
                if !onMain {
                    _ = gate.wait(timeout: .now() + 5) // Background worker only; held until poll returns.
                }
                return prepare()
            }, { prepared in
                let onMain = Thread.isMainThread
                done(prepared)
                let waiter = probe.withLock { state -> CheckedContinuation<Void, Never>? in
                    state.doneOnMain = onMain
                    state.finished = true
                    defer { state.continuation = nil }
                    return state.continuation
                }
                waiter?.resume()
            })
        }

        source.types = ["public.png"]
        source.payload = largeImage
        source.changeCount = 1
        let start = ProcessInfo.processInfo.systemUptime
        let outcome = recorder.poll(limit: 20)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        #expect(elapsed < 0.25, "poll blocked main for \(elapsed) seconds on a large clipboard image")
        #expect(outcome == .imageQueued, "poll must defer image preparation instead of finishing inline")
        #expect(store.items.isEmpty, "the image must not be added synchronously before preparation completes")
        try #require(probe.withLock { $0.scheduled } == 1, "poll must schedule image preparation through imageWork")

        released = true
        gate.signal()
        await withCheckedContinuation { continuation in
            let alreadyDone = probe.withLock { state -> Bool in
                if state.finished { return true }
                state.continuation = continuation
                return false
            }
            if alreadyDone { continuation.resume() }
        }

        let result = probe.withLock { $0 }
        #expect(result.preparedOnMain == false, "image preparation must run off the main thread")
        #expect(result.doneOnMain == true, "recording the prepared image must return to the main thread")
        let kept = try #require(store.items.first?.image, "the prepared image must reach the store once work completes")
        #expect(store.items.count == 1)
        #expect(kept.width == 4000 && kept.height == 4000)
        #expect(kept.thumbnail != nil)
        #expect(store.imageData(kept.id) == largeImage.data)
        #expect(recorder.clipboardIsNewest)
    }

    private static func largePNG(width: Int, height: Int, fill: Int32 = 0x80) throws -> ClipboardImage {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        if let bytes = bitmap.bitmapData { memset(bytes, fill, bitmap.bytesPerRow * height) }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        return ClipboardImage(data: data, width: width, height: height)
    }

    /// Item 28. `imageWork` is the existing seam. Keep image preparation pending, then assert the ⌃V lookup returns
    /// within 60 ms on main. The old semaphore path waits 150 ms even though the panel could show immediately.
    @Test @MainActor func quickClipboardPanelDoesNotWaitForImage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-quick-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardHistoryStore(url: folder.appendingPathComponent("history.json"))
        await store.waitForLoad()
        let recorder = ClipboardRecorder(source: ReviewImageSource(), store: store, secureInput: { false }, frontmostApp: { nil })
        recorder.imageWork = { _, _ in } // Pending image work; no worker or pasteboard is touched.
        let start = ProcessInfo.processInfo.systemUptime
        _ = recorder.poll(limit: 20, quick: true)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(elapsed < 0.06, "quick ⌃V blocked main for \(elapsed) seconds while the image was pending")
    }

    // MARK: - Item 29: English dictionary loader never waited for

    /// Item 29. Runtime check of `RimeService.EnglishLoad` with a gated loader (compiled against the built
    /// `AllInOneIMERime` module via `SourceCompiler`): `dictionary` returns `nil` promptly on main while
    /// loading, the loader runs off main, and the dictionary appears once loading finishes. Also checks
    /// `Rime.swift` generically for any `.wait(`, sleep, or `.sync` on the `englishDictionary` / `EnglishLoad` path.
    @Test func unfinishedEnglishDictionaryNeverWaitsForLoader() throws {
        let run = try EnglishLoadChild.run()
        #expect(run.status == 0, "EnglishLoad runtime probe failed (exit \(run.status)):\n\(run.output)")
        #expect(run.output.contains("STARTED true"), "gated loader never began running:\n\(run.output)")
        #expect(run.output.contains("BEFORE_NIL true"), "dictionary getter waited or returned early before loader finished:\n\(run.output)")
        #expect(run.output.contains("LOADER_ON_MAIN false"), "English dictionary loader ran on the main thread:\n\(run.output)")
        #expect(run.output.contains("COMPLETED true"), "English dictionary loader did not complete after gate opened:\n\(run.output)")
        #expect(run.output.contains("AFTER_COUNT 2") && run.output.contains("AFTER_HAS_HELLO true"),
                "dictionary was not published after loading completed:\n\(run.output)")
        if let line = run.output.split(separator: "\n").first(where: { $0.hasPrefix("BEFORE_ELAPSED ") }),
           let seconds = Double(line.dropFirst("BEFORE_ELAPSED ".count)) {
            #expect(seconds < 0.25, "dictionary getter blocked main for \(seconds)s while loader was held")
        } else {
            Issue.record("missing BEFORE_ELAPSED measurement:\n\(run.output)")
        }

        // Generic source check on `RimeService.englishDictionary` and `EnglishLoad` (catches any `.wait()`, not just `group.wait()`).
        let rime = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Core/Sources/AllInOneIMERime/Rime.swift"))
        let serviceGetter = try SwiftSourceAudit.body(of: "public var englishDictionary: EnglishDictionary?", in: rime)
        let loadClass = try SwiftSourceAudit.body(of: "final class EnglishLoad:", in: rime)
        let loadGetter = try SwiftSourceAudit.body(of: "var dictionary: EnglishDictionary?", in: loadClass)
        let loadInitMain = SwiftSourceAudit.mainThreadCode(in: try SwiftSourceAudit.body(of: "init(_ folder: URL", in: loadClass))

        for (label, code) in [("RimeService.englishDictionary", serviceGetter),
                              ("EnglishLoad.dictionary", loadGetter),
                              ("EnglishLoad.init", loadInitMain)] {
            let blocking = SwiftSourceAudit.blockingMatches(in: code)
            #expect(blocking.isEmpty, "\(label) contains a blocking call: \(blocking)")
        }
    }

    // MARK: - Item 30: Keyboard layout lookup cached across keys

    /// Item 30. Runtime check through `KeyboardLayout.Cache`: repeated lookups of an installed or missing
    /// layout make at most one underlying TIS lookup until invalidated (`forget`), after which exactly one
    /// more lookup is performed. Also verifies `makeSession` and `typeOut` route through the cache.
    @Test @MainActor func appliedKeyboardLayoutIsReusedAcrossKeys() throws {
        let cache = KeyboardLayout.Cache.shared
        let previous = cache.lookUp
        defer {
            cache.lookUp = previous
            cache.forget()
        }

        let lookups = Locked(initialState: 0)
        let current = KeyboardLayout.current()
        cache.lookUp = { id in
            lookups.withLock { $0 += 1 }
            return id.hasSuffix(".Installed") ? current : nil
        }

        for _ in 0..<5 { _ = KeyboardLayout.cached(id: "com.example.keylayout.Installed") }
        #expect(lookups.withLock { $0 } == 1, "repeated keys must reuse the cached layout")

        for _ in 0..<5 { #expect(KeyboardLayout.cached(id: "com.example.keylayout.Missing") == nil) }
        #expect(lookups.withLock { $0 } == 2, "missing layouts must also be cached until input sources change")

        cache.forget()
        for _ in 0..<5 { _ = KeyboardLayout.cached(id: "com.example.keylayout.Installed") }
        #expect(lookups.withLock { $0 } == 3, "invalidation must permit exactly one fresh lookup")

        // Follow callers in the executable target (`makeSession` and `typeOut`) and notification wiring in `KeyboardLayout.swift`.
        let controller = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController.swift"))
        let typeOut = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController+TypeOut.swift"))
        let layoutSource = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIMEMac/KeyboardLayout.swift"))

        let makeSession = try SwiftSourceAudit.body(of: "private func makeSession()", in: controller)
        let typeOutFunc = try SwiftSourceAudit.body(of: "func typeOut(", in: typeOut)
        for (label, code) in [("InputController.makeSession", makeSession), ("InputController.typeOut", typeOutFunc)] {
            #expect(!code.contains("KeyboardLayout(id:") && !code.contains("KeyboardLayout.init(id:")
                    && !code.contains("TISCreateInputSourceList"),
                    "\(label) constructs KeyboardLayout(id:) directly instead of using KeyboardLayout.cached(id:)")
            #expect(code.contains("KeyboardLayout.cached(id:"), "\(label) must use KeyboardLayout.cached(id:)")
        }
        let watch = try SwiftSourceAudit.body(of: "private func watch()", in: layoutSource)
        #expect(watch.contains("kTISNotifySelectedKeyboardInputSourceChanged")
                && watch.contains("kTISNotifyEnabledKeyboardInputSourcesChanged")
                && watch.contains("forget()"),
                "KeyboardLayout.Cache must invalidate on system keyboard input source change notifications")
    }

    // MARK: - Item 31: stopTyping never sleeps on main

    /// Item 31. Runtime test through `TypeOut.Typist.stopping` with a lagging fake field and fake retry loop
    /// (zero real sleeps), plus generic source checks following `stopTyping` into `InputController+TypeOut.swift`
    /// and `InputController+Leaving.swift`.
    @Test func stopTypingNeverSleepsOnMain() throws {
        // Build a deterministic plan containing a slip.
        let plan = TypeOut.plan(for: "hello world", rate: 20, mistakes: true, random: { 0.0 })
        let hasSlip = plan.contains(where: \.isSlip)
        try #require(hasSlip, "deterministic plan must contain a slip")

        let field = DelayedTypeOutField()
        var typist = TypeOut.Typist(plan, start: 0, length: 0, proven: true)
        var guardSteps = 0
        while !typist.typing.inSlip, guardSteps < 50 {
            _ = typist.step(in: field)
            guardSteps += 1
        }
        try #require(typist.typing.inSlip, "typist should be mid-slip before stopping")

        // Simulate a lagging field (like Chromium) that takes 2 polls to report what was typed, and 1 more
        // poll to report the typo replacement.
        field.lagReadsRemaining = 2
        var deferredChecks = 0
        let start = ProcessInfo.processInfo.systemUptime
        var settledRest: String?
        while settledRest == nil, deferredChecks < 20 {
            if let rest = typist.stopping(insertingRest: true, in: field) {
                settledRest = rest
            } else {
                deferredChecks += 1
                // Once the first lag finishes and stopping issues its replacement, add 1 poll of lag for the fix check.
                if field.replaceCount == 1, !field.addedPostFixLag {
                    field.addedPostFixLag = true
                    field.lagReadsRemaining = 1
                }
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        let rest = try #require(settledRest, "stopping must settle once the field catches up")
        #expect(deferredChecks >= 2, "stopping must return nil to yield instead of sleeping while the field lags")
        #expect(elapsed < 0.1, "stepwise stopping took \(elapsed)s without any real timer")
        field.type(rest)
        #expect(field.actualText == "hello world", "field text after settling stop: \(field.actualText)")

        // Immediate stop (`waiting: false`) settles on the very first call even while lagging.
        let immediateField = DelayedTypeOutField()
        var immediateTypist = TypeOut.Typist(plan, start: 0, length: 0, proven: true)
        while !immediateTypist.typing.inSlip { _ = immediateTypist.step(in: immediateField) }
        immediateField.lagReadsRemaining = 10
        #expect(immediateTypist.stopping(insertingRest: true, in: immediateField, waiting: false) != nil,
                "stopping(waiting: false) must settle immediately without deferring")

        // Follow `stopTyping` into every file that implements the path.
        let controller = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController.swift"))
        let typeOutHelper = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController+TypeOut.swift"))
        let leavingHelper = SwiftSourceAudit.stripCommentsAndStrings(try Self.source("Sources/AllInOneIME/InputController+Leaving.swift"))

        let stopTyping = try SwiftSourceAudit.body(of: "func stopTyping(insertingRest:", in: controller)
        let settleStop = try SwiftSourceAudit.body(of: "func settleStop(", in: typeOutHelper)
        let leaveField = try SwiftSourceAudit.body(of: "func leaveField(", in: leavingHelper)
        let cancelComposition = try SwiftSourceAudit.body(of: "override func cancelComposition()", in: leavingHelper)

        for (label, code) in [("InputController.stopTyping", stopTyping),
                              ("InputController+TypeOut.swift", typeOutHelper),
                              ("InputController.leaveField", leaveField),
                              ("InputController.cancelComposition", cancelComposition)] {
            let blocking = SwiftSourceAudit.blockingMatches(in: code)
            #expect(blocking.isEmpty, "\(label) contains a blocking call: \(blocking)")
        }
        #expect(!stopTyping.contains("typist.stop("), "stopTyping must not call the synchronous typist.stop loop")
        #expect(stopTyping.contains("typist.stopping("), "stopTyping must use non-blocking typist.stopping")
        #expect(settleStop.contains("Task") && settleStop.contains("await "),
                "settleStop must defer retries asynchronously rather than sleeping synchronously")
    }
}

// MARK: - Test doubles & helpers

private final class PasswordReaderProbe: @unchecked Sendable {
    private let state = Locked(initialState: (calls: 0, calledOnMain: false))
    var calls: Int { state.withLock(\.calls) }
    var calledOnMain: Bool { state.withLock(\.calledOnMain) }

    func record(onMain: Bool) {
        state.withLock {
            $0.calls += 1
            if onMain { $0.calledOnMain = true }
        }
    }
}

private struct ImageWorkProbe {
    var scheduled = 0
    var preparedOnMain: Bool?
    var doneOnMain: Bool?
    var finished = false
    var continuation: CheckedContinuation<Void, Never>?
}

private final class ReviewImageSource: ClipboardSource {
    var changeCount: Int
    var access: ClipboardAccess { .allowed }
    var types: [String]
    var payload: ClipboardImage?

    init(changeCount: Int = 1, types: [String] = ["public.png"],
         payload: ClipboardImage? = ClipboardImage(data: Data([1]), width: 1, height: 1)) {
        self.changeCount = changeCount
        self.types = types
        self.payload = payload
    }

    func text() -> String? { nil }
    func image() -> ClipboardImage? { payload }
}

private final class ReviewTextInput: NSObject, IMKTextInput {
    var text: String
    var selection: NSRange
    var lineRect: NSRect = .zero

    init(text: String = "", caret: Int = 0) {
        self.text = text
        self.selection = NSRange(location: caret, length: 0)
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {}
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {}
    func selectedRange() -> NSRange { selection }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        let ns = text as NSString
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= ns.length else { return nil }
        return NSAttributedString(string: ns.substring(with: range))
    }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        attributedSubstring(from: range)?.string
    }
    func length() -> Int { (text as NSString).length }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = self.lineRect
        return [:]
    }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "com.example.ReviewField" }
    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "review-text-input" }
}

private final class DelayedTypeOutField: TypeOut.Field {
    private(set) var actualText = ""
    private var visibleText = ""
    var lagReadsRemaining = 0
    var replaceCount = 0
    var addedPostFixLag = false

    private var shown: String {
        if lagReadsRemaining > 0 {
            lagReadsRemaining -= 1
            return visibleText
        }
        visibleText = actualText
        return actualText
    }

    var caret: Int? { (shown as NSString).length }
    var length: Int? { (visibleText as NSString).length }

    func read(_ range: NSRange) -> String? {
        let ns = visibleText as NSString
        guard range.location >= 0, NSMaxRange(range) <= ns.length else { return nil }
        return ns.substring(with: range)
    }

    func type(_ text: String) {
        if lagReadsRemaining == 0 { visibleText = actualText }
        actualText += text
        if lagReadsRemaining == 0 { visibleText = actualText }
    }

    func replace(_ range: NSRange, with text: String) {
        replaceCount += 1
        let before = actualText
        actualText = (actualText as NSString).replacingCharacters(in: range, with: text)
        visibleText = lagReadsRemaining > 0 ? before : actualText
    }
}

/// Compiles a tiny runtime probe against the built `AllInOneIMERime` module to exercise `RimeService.EnglishLoad`
/// directly with a gated loader on a real process's main thread.
private enum EnglishLoadChild {
    struct Failure: Error, CustomStringConvertible { var description: String }

    static let compiled: Result<URL, Error> = Result { try compile() }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("english-load-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let mainFile = scratch.appendingPathComponent("main.swift")
        try harnessSource.write(to: mainFile, atomically: true, encoding: .utf8)
        let executable = scratch.appendingPathComponent("english-load-probe")
        let swift = try SourceCompiler.compile(
            repository: Release076MainThreadReviewTests.root,
            sources: [mainFile.path],
            executable: executable,
            timeout: 60
        )
        guard swift.status == 0 else { throw Failure(description: "compiling EnglishLoad probe:\n\(swift.output)") }
        return executable
    }

    static func run() throws -> (status: Int32, output: String) {
        let executable = try compiled.get()
        let out = Pipe()
        let process = Process()
        process.executableURL = executable
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let collected = Locked(initialState: Data())
        let readDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            collected.withLock { $0 = data }
            readDone.signal()
        }
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        _ = readDone.wait(timeout: .now() + 1)
        let text = String(decoding: collected.withLock { $0 }, as: UTF8.self)
        return (process.terminationStatus, text)
    }

    static let harnessSource = #"""
import AllInOneIMECore
@testable import AllInOneIMERime
import Foundation

let entered = DispatchSemaphore(value: 0)
let gate = DispatchSemaphore(value: 0)
let loaderOnMain = Locked(initialState: false)
let load = RimeService.EnglishLoad(URL(fileURLWithPath: "/tmp")) { _ in
    loaderOnMain.withLock { $0 = Thread.isMainThread }
    entered.signal()
    _ = gate.wait(timeout: .now() + 5)
    return EnglishDictionary(["hello", "world"])
}
let started = entered.wait(timeout: .now() + 3) == .success
let start = ProcessInfo.processInfo.systemUptime
let before = load.dictionary
let elapsed = ProcessInfo.processInfo.systemUptime - start
gate.signal()
let deadline = ProcessInfo.processInfo.systemUptime + 3
var after = load.dictionary
while after == nil && ProcessInfo.processInfo.systemUptime < deadline {
    Thread.sleep(forTimeInterval: 0.005)
    after = load.dictionary
}
let completed = after != nil
print("STARTED \(started)")
print("BEFORE_NIL \(before == nil)")
print("BEFORE_ELAPSED \(elapsed)")
print("LOADER_ON_MAIN \(loaderOnMain.withLock { $0 })")
print("COMPLETED \(completed)")
print("AFTER_COUNT \(after?.count ?? -1)")
print("AFTER_HAS_HELLO \(after?.contains("hello") == true)")
"""#
}

// MARK: - Swift-aware source audit helpers

private enum SwiftSourceAudit {
    /// Removes Swift comments (`//`, nested `/* ... */`) and string literal text (preserving `\(... )` code
    /// and balanced braces) so regex and body extraction operate only on live code.
    static func stripCommentsAndStrings(_ source: String) -> String {
        let chars = Array(source)
        let n = chars.count
        var out: [Character] = []
        out.reserveCapacity(n)
        var i = 0

        struct StringFrame {
            var hashes: Int
            var multiline: Bool
            var parenDepth: Int
        }
        var interpolationStack: [StringFrame] = []

        func matches(_ offset: Int, _ count: Int, _ ch: Character) -> Bool {
            guard offset + count <= n else { return false }
            for k in 0..<count where chars[offset + k] != ch { return false }
            return true
        }

        func consumeString(hashes: Int, multiline: Bool) {
            let quoteCount = multiline ? 3 : 1
            out.append("\"")
            out.append("\"")
            while i < n {
                if chars[i] == "\\" && matches(i + 1, hashes, "#") {
                    let after = i + 1 + hashes
                    if after < n && chars[after] == "(" {
                        // Enter string interpolation: preserve code inside `\(...)`.
                        i = after + 1
                        out.append(" ")
                        interpolationStack.append(StringFrame(hashes: hashes, multiline: multiline, parenDepth: 1))
                        return
                    }
                    i = min(after + 1, n)
                    continue
                }
                if matches(i, quoteCount, "\"") && matches(i + quoteCount, hashes, "#") {
                    i += quoteCount + hashes
                    return
                }
                if chars[i] == "\n" { out.append("\n") }
                i += 1
            }
        }

        while i < n {
            let c = chars[i]
            // Line comment
            if c == "/", i + 1 < n, chars[i + 1] == "/" {
                i += 2
                while i < n && chars[i] != "\n" { i += 1 }
                continue
            }
            // Nested block comment
            if c == "/", i + 1 < n, chars[i + 1] == "*" {
                var depth = 1
                i += 2
                while i < n && depth > 0 {
                    if chars[i] == "/", i + 1 < n, chars[i + 1] == "*" { depth += 1; i += 2 }
                    else if chars[i] == "*", i + 1 < n, chars[i + 1] == "/" { depth -= 1; i += 2 }
                    else { if chars[i] == "\n" { out.append("\n") }; i += 1 }
                }
                out.append(" ")
                continue
            }
            // Inside `\(... )` interpolation
            if !interpolationStack.isEmpty {
                if c == "(" {
                    interpolationStack[interpolationStack.count - 1].parenDepth += 1
                    out.append(c); i += 1; continue
                }
                if c == ")" {
                    interpolationStack[interpolationStack.count - 1].parenDepth -= 1
                    if interpolationStack[interpolationStack.count - 1].parenDepth == 0 {
                        let frame = interpolationStack.removeLast()
                        out.append(" "); i += 1
                        consumeString(hashes: frame.hashes, multiline: frame.multiline)
                        continue
                    }
                    out.append(c); i += 1; continue
                }
            }
            // String literal (raw or regular, single-line or multiline)
            if c == "#" || c == "\"" {
                var h = 0
                while i + h < n && chars[i + h] == "#" { h += 1 }
                if i + h < n && chars[i + h] == "\"" {
                    let multiline = matches(i + h, 3, "\"")
                    i += h + (multiline ? 3 : 1)
                    consumeString(hashes: h, multiline: multiline)
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    static func body(of declaration: String, in stripped: String) throws -> String {
        let start = try #require(stripped.range(of: declaration)?.upperBound, "missing \(declaration)")
        let opening = try #require(stripped[start...].firstIndex(of: "{"), "missing body for \(declaration)")
        guard let end = matchingBrace(from: opening, in: stripped) else {
            Issue.record("unclosed body for \(declaration)")
            return ""
        }
        return String(stripped[opening...end])
    }

    private static func matchingDelimiter(open: Character, close: Character, from opening: String.Index, in text: String) -> String.Index? {
        var depth = 0
        for index in text[opening...].indices {
            switch text[index] {
            case open: depth += 1
            case close:
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }

    private static func matchingBrace(from opening: String.Index, in text: String) -> String.Index? {
        matchingDelimiter(open: "{", close: "}", from: opening, in: text)
    }

    /// Skips whitespace and an optional balanced `(...)` argument list to find a trailing `{ ... }` closure.
    private static func trailingClosureRange(after index: String.Index, in text: String) -> ClosedRange<String.Index>? {
        var cursor = index
        while cursor < text.endIndex && text[cursor].isWhitespace { cursor = text.index(after: cursor) }
        if cursor < text.endIndex && text[cursor] == "(" {
            guard let closeParen = matchingDelimiter(open: "(", close: ")", from: cursor, in: text) else { return nil }
            cursor = text.index(after: closeParen)
            while cursor < text.endIndex && text[cursor].isWhitespace { cursor = text.index(after: cursor) }
        }
        guard cursor < text.endIndex && text[cursor] == "{",
              let closeBrace = matchingBrace(from: cursor, in: text) else { return nil }
        return cursor...closeBrace
    }

    /// Extracts the bodies of any `DispatchQueue.main.async`, `DispatchQueue.main.asyncAfter`, or `MainActor.run`
    /// closures inside `stripped` (handling nested parentheses such as `deadline: .now() + 0.1`).
    static func nestedMainCallbacks(in stripped: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:DispatchQueue\.main\.async(?:After)?|MainActor\.run)\b"#) else {
            return ""
        }
        var extracted = ""
        let fullRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
        for match in regex.matches(in: stripped, range: fullRange) {
            if let r = Range(match.range, in: stripped),
               let closureRange = trailingClosureRange(after: r.upperBound, in: stripped) {
                extracted += "\n" + mainThreadCode(in: String(stripped[closureRange]))
            }
        }
        return extracted
    }

    /// Returns the code that executes on the calling (main) thread: strips closures dispatched asynchronously
    /// onto background queues (`DispatchQueue.global(...).async`, `<non-main-queue>.async`, `Task.detached`),
    /// while pulling any nested `DispatchQueue.main.async` / `MainActor.run` blocks back in so they are still audited.
    static func mainThreadCode(in stripped: String) -> String {
        let offMainRegex = try? NSRegularExpression(
            pattern: #"(?:DispatchQueue\.global\s*\([^)]*\)\s*\.async|\b(?!main\b)[A-Za-z_]\w*\s*\.async|\bTask\.detached)\b"#
        )
        guard let offMainRegex else { return stripped }

        var result = ""
        var cursor = stripped.startIndex
        while cursor < stripped.endIndex {
            let searchRange = NSRange(cursor..<stripped.endIndex, in: stripped)
            guard let match = offMainRegex.firstMatch(in: stripped, range: searchRange),
                  let matchRange = Range(match.range, in: stripped) else {
                result += stripped[cursor...]
                break
            }
            guard let closureRange = trailingClosureRange(after: matchRange.upperBound, in: stripped) else {
                result += stripped[cursor..<matchRange.upperBound]
                cursor = matchRange.upperBound
                continue
            }
            result += stripped[cursor..<closureRange.lowerBound]
            result += "{ }"
            let inner = String(stripped[stripped.index(after: closureRange.lowerBound)..<closureRange.upperBound])
            result += nestedMainCallbacks(in: inner)
            cursor = stripped.index(after: closureRange.upperBound)
        }
        return result
    }

    /// Separates `<property> = { ... }` from a function body so a stored callback executed on a background queue
    /// can be audited independently from the caller's synchronous main-thread body.
    static func stripAssignedClosure(_ property: String, in stripped: String) -> (outer: String, closure: String?) {
        let pattern = NSRegularExpression.escapedPattern(for: property) + #"\s*=\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)),
              let matchRange = Range(match.range, in: stripped),
              let openBrace = stripped[matchRange].lastIndex(of: "{"),
              let closeBrace = matchingBrace(from: openBrace, in: stripped) else {
            return (stripped, nil)
        }
        let closure = String(stripped[openBrace...closeBrace])
        let outer = String(stripped[..<openBrace]) + "{ }" + String(stripped[stripped.index(after: closeBrace)...])
        return (outer, closure)
    }

    /// Generic blocking-call detector: catches any `.wait(`, `Thread.sleep`, `usleep(`, `nanosleep(`,
    /// `Darwin.sleep(`, bare synchronous `sleep(` (excluding `await sleep(` and `Task.sleep`),
    /// `DispatchQueue.main.sync`, any `.sync(` / `.sync {`, and `waitUntilExit(`.
    static func blockingMatches(in stripped: String) -> [String] {
        let patterns = [
            #"\.wait\s*\("#,
            #"\bThread\.sleep\b"#,
            #"\busleep\s*\("#,
            #"\bnanosleep\s*\("#,
            #"\bDarwin\.sleep\s*\("#,
            #"\bDispatchQueue\.main\.sync\b"#,
            #"\.sync\s*(?:\(|\{)"#,
            #"\bwaitUntilExit\s*\("#,
        ]
        var hits: [String] = []
        let fullRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: stripped, range: fullRange) {
                if let range = Range(match.range, in: stripped) { hits.append(String(stripped[range])) }
            }
        }
        // Catch bare synchronous `sleep(...)` while permitting Swift concurrency `await sleep(...)` and `Task.sleep(...)`.
        if let bareSleep = try? NSRegularExpression(pattern: #"(?:^|[^.\w])sleep\s*\("#) {
            for match in bareSleep.matches(in: stripped, range: fullRange) {
                guard let range = Range(match.range, in: stripped) else { continue }
                let prefix = stripped[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.hasSuffix("await") && !prefix.hasSuffix("func") {
                    hits.append(String(stripped[range]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return hits
    }

    /// Classifies every `FocusedField` static member that calls Accessibility (`AXUIElement*`,
    /// `AXIsProcessTrusted`, or transitively another AX member) by inspecting `FocusedField.swift`.
    static func focusedFieldAXMembers(in rawFocusedFieldSource: String) throws -> Set<String> {
        let stripped = stripCommentsAndStrings(rawFocusedFieldSource)
        let declRegex = try NSRegularExpression(pattern: #"\bstatic\s+(?:func|var)\s+([A-Za-z_]\w*)"#)
        let fullRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
        var bodies: [String: [String]] = [:]
        for match in declRegex.matches(in: stripped, range: fullRange) {
            guard let nameRange = Range(match.range(at: 1), in: stripped),
                  let declRange = Range(match.range, in: stripped),
                  let open = stripped[declRange.upperBound...].firstIndex(of: "{"),
                  let close = matchingBrace(from: open, in: stripped) else { continue }
            let name = String(stripped[nameRange])
            bodies[name, default: []].append(String(stripped[open...close]))
        }
        var axMembers: Set<String> = []
        for (name, memberBodies) in bodies {
            let joined = memberBodies.joined(separator: "\n")
            if joined.contains("AXUIElement") || joined.contains("AXIsProcessTrusted") || !blockingMatches(in: joined).isEmpty {
                axMembers.insert(name)
            }
        }
        // Transitive closure (e.g. `frame(top:)` and `isSecure()` call `element()`).
        var changed = true
        while changed {
            changed = false
            for (name, memberBodies) in bodies where !axMembers.contains(name) {
                let joined = memberBodies.joined(separator: "\n")
                for ax in axMembers {
                    if let call = try? NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: ax) + #"\s*\("#),
                       call.firstMatch(in: joined, range: NSRange(joined.startIndex..<joined.endIndex, in: joined)) != nil {
                        axMembers.insert(name)
                        changed = true
                        break
                    }
                }
            }
        }
        return axMembers
    }

    /// Finds any direct Accessibility API call or call to an AX-using `FocusedField.<member>` in `mainCode`.
    static func axCalls(in mainCode: String, focusedFieldAX: Set<String>) -> [String] {
        var hits: [String] = []
        let fullRange = NSRange(mainCode.startIndex..<mainCode.endIndex, in: mainCode)
        if let direct = try? NSRegularExpression(pattern: #"\b(?:AXUIElement\w*|AXIsProcessTrusted)\b"#) {
            for match in direct.matches(in: mainCode, range: fullRange) {
                if let r = Range(match.range, in: mainCode) { hits.append(String(mainCode[r])) }
            }
        }
        if let ff = try? NSRegularExpression(pattern: #"\bFocusedField\.([A-Za-z_]\w*)"#) {
            for match in ff.matches(in: mainCode, range: fullRange) {
                if let memberRange = Range(match.range(at: 1), in: mainCode) {
                    let member = String(mainCode[memberRange])
                    if focusedFieldAX.contains(member) { hits.append("FocusedField.\(member)") }
                }
            }
        }
        return hits
    }
}
