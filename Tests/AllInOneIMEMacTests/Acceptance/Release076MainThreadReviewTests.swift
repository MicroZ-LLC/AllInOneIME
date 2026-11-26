import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import Testing

/// Reproductions for the review's main-thread and one-time wiring findings. The executable target cannot be imported
/// by this test target, so checks of its private entry points read those entry points from source. When an entry point
/// gains a test seam, replace its source check with a call through that seam; keep the same behavioral assertion.
@Suite(.serialized)
struct Release076MainThreadReviewTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Source seam: the named declaration's body, including nested closures. The implementer may move the work to a
    /// helper; the assertion is about what the caller synchronously invokes, not where the helper is declared.
    static func body(_ declaration: String, in source: String) throws -> String {
        let start = try #require(source.range(of: declaration)?.upperBound, "missing \(declaration)")
        let opening = try #require(source[start...].firstIndex(of: "{"), "missing body for \(declaration)")
        var depth = 0
        for index in source[opening...].indices {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[opening...index]) }
            default: break
            }
        }
        Issue.record("unclosed body for \(declaration)")
        return ""
    }

    /// Item 3. Required runtime seam for a later behavioral probe: expose a counter for global UI wiring, resettable
    /// in tests, incremented once after attaching the preview and installing both icon callbacks at app startup.
    /// Two or more calls to `SessionServices.mac` must leave that counter at one.
    @Test func globalUIWiringIsNotRepeatedForEachSession() throws {
        let mac = try Self.body("static var mac: SessionServices", in: Self.source("Sources/AllInOneIME/SessionServices+Mac.swift"))
        #expect(!mac.contains("ImagePreview.shared.attach"), "preview attachment repeats for every session")
        #expect(!mac.contains("CandidateView.itemIcon ="), "icon callback repeats for every session")
        #expect(!mac.contains("ItemIcons.shared.onLoaded ="), "loaded callback repeats for every session")
    }

    /// Item 25. `passwordField` is an injected Accessibility read. An unknown answer must remain unknown until the
    /// existing off-main password-field event arrives; the first key's synchronous context read must not invoke it.
    @Test @MainActor func firstKeyDoesNotReadPasswordFieldThroughAccessibility() {
        var calls = 0
        let reading = FieldReading(isTerminal: { _ in false }, secureInputActive: { false }, passwordField: {
            calls += 1
            return false
        })
        let context = reading.context(in: nil) { _ in [.secure, .passwordField] }
        #expect(calls == 0, "first key synchronously called the Accessibility password check")
        #expect(context.passwordFieldUnknown, "the pending answer must fail closed")
    }

    /// Item 25. Required runtime seam: inject slow `windowFrame` and `caretByAccessibility` readers into panel
    /// placement, and a slow focused-frame reader into ghost placement. Both calls must return before either reader
    /// completes, then reposition through the existing anchor token when the answer arrives.
    @Test func panelAndGhostPlacementDoNotCallAccessibilityInline() throws {
        let controller = try Self.body("func anchor(", in: Self.source("Sources/AllInOneIME/InputController.swift"))
        let overlay = try Self.body("func placeGhost(", in: Self.source("Sources/AllInOneIME/AutocompleteOverlay.swift"))
        #expect(!controller.contains("FocusedField.windowFrame("), "panel placement reads the window frame inline")
        #expect(!controller.contains("caretByAccessibility("), "panel placement reads the caret inline")
        #expect(!overlay.contains("FocusedField."), "ghost placement reads Accessibility inline")
    }

    /// Item 27. Required runtime seam: injectable config reader, key stores, and config writer for the sync
    /// controller. Hold each operation on a worker, call `start`/`run` on main, and assert those calls return promptly;
    /// assert the writer itself ran off main. This source contract covers the private executable entry points today.
    @Test func iCloudKeyMigrationAndConfigIOStayOffMain() throws {
        let source = try Self.source("Sources/AllInOneIME/ICloudSyncController.swift")
        let start = try Self.body("func start()", in: source)
        let run = try Self.body("func run()", in: source)
        let settings = try Self.body("private var settings:", in: source)
        #expect(!start.contains("applyKeySync("), "launch does keychain and config I/O on main")
        #expect(!run.contains("applyKeySync("), "a sync run does keychain and config I/O on main")
        #expect(!settings.contains("Config.load("), "polling reparses the config on main")
        #expect(!source.contains("DispatchQueue.main.sync"), "sync queue blocks on a synchronous main-queue hop")
    }

    /// Item 28. The existing launch-file read test covers only loading. A copy's save, trim, and clear must enqueue
    /// disk work; `waitForWrites` is the explicit test-only drain and is intentionally outside these checks.
    @Test func clipboardHistoryMutationsNeverWaitForDisk() throws {
        let source = try Self.source("Sources/AllInOneIMEMac/ClipboardHistoryStore.swift")
        for declaration in ["public func clear()", "private func keep(", "private func removeUnlisted()"] {
            let operation = try Self.body(declaration, in: source)
            #expect(!operation.contains("writes.sync"), "\(declaration) synchronously waits for history disk work")
        }
    }

    /// Item 28. Reading `NSPasteboard` stays on the main thread (it is a single shared AppKit object; off-main reads
    /// raced main-thread uses and crashed in `-[NSPasteboard _updateTypeCacheIfNeeded]`). What must stay off main is
    /// image preparation (decoding, thumbnailing, PNG encoding, file writes) through `ClipboardRecorder.imageWork`.
    /// Wrapping the recorder's default `imageWork` verifies that `poll` schedules preparation instead of running it
    /// inline, returns promptly even for a 4000x4000 PNG, runs the preparation closure off main, and delivers the item
    /// to the store once preparation completes.
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

    private static func largePNG(width: Int, height: Int) throws -> ClipboardImage {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        if let bytes = bitmap.bitmapData { memset(bytes, 0x80, bitmap.bytesPerRow * height) }
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

    /// Item 29. Required runtime seam: inject a dictionary loader held on a gate into `EnglishLoad`, then request
    /// `dictionary` before release. It must return nil promptly and publish/refresh when loading completes.
    @Test func unfinishedEnglishDictionaryNeverWaitsForLoader() throws {
        let source = try Self.source("Core/Sources/AllInOneIMERime/Rime.swift")
        let getter = try Self.body("var dictionary: EnglishDictionary?", in: source)
        #expect(!getter.contains("group.wait()"), "dictionary getter blocks until utility-QoS parsing completes")
    }

    /// Item 30. Required runtime seam: inject a TIS lookup counter into `KeyboardLayout(id:)`. For an installed
    /// non-current layout, several keys in one session must make at most one lookup; a layout-change notification
    /// invalidates that cache and permits exactly one more lookup on the next key.
    @Test func appliedKeyboardLayoutIsReusedAcrossKeys() throws {
        let session = try Self.body("private func makeSession()", in: Self.source("Sources/AllInOneIME/InputController.swift"))
        #expect(!session.contains("appliedLayout.flatMap(KeyboardLayout.init(id:))"),
                "each key constructs a layout and can repeat TISCreateInputSourceList")
    }

    /// Item 31. Required runtime seam: inject `TypeOut.Typist.stop`'s wait callback into the controller. With a
    /// delayed field, `stopTyping` on main must return before a second callback and finish settling asynchronously.
    @Test func stopTypingNeverSleepsOnMain() throws {
        let stop = try Self.body("func stopTyping(insertingRest:", in: Self.source("Sources/AllInOneIME/InputController.swift"))
        #expect(!stop.contains("usleep("), "stopTyping sleeps while handling a key on main")
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
