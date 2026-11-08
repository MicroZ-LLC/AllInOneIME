#if canImport(Vision)
import CoreGraphics
import Foundation
import Testing
import Vision
@testable import AllInOneIMECore

/// `VisionTextRecognizer` falling back from Vision's default device (where a read may fail, in a long-running process
/// again and again) to the GPU, then the CPU, and going straight to the one that read from then on: with a fake reader
/// in place of Vision, and a memory of its own in place of the process's.
struct VisionFallbackTests {
    typealias Device = VisionTextRecognizer.Device

    struct ReadFailed: Error, Equatable {
        var device: Device
    }

    /// Fails on the devices in `failing` and reads one line on the others; keeps the devices it was asked for.
    final class FakeVision: @unchecked Sendable {
        static let line = "fallback-probe-line"
        let failing: Locked<Set<Device>>
        private let asked = Locked<[Device]>(initialState: [])

        init(failing: Set<Device>) { self.failing = Locked(initialState: failing) }

        func read(_ image: Data, _ languages: [String], _ device: Device) throws -> [RecognizedLine] {
            asked.withLock { $0.append(device) }
            if failing.withLock({ $0.contains(device) }) { throw ReadFailed(device: device) }
            return [RecognizedLine(text: Self.line, box: CGRect(x: 0.05, y: 0.1, width: 0.5, height: 0.05), confidence: 0.9)]
        }

        /// The devices asked for since the last call.
        func calls() -> [Device] { asked.withLock { calls in defer { calls = [] }; return calls } }
    }

    let image = Data([0x89, 0x50, 0x4E, 0x47])
    let languages = ["zh-Hans", "en-US", "ja-JP"]

    func recognizer(_ vision: FakeVision, _ memory: Locked<VisionTextRecognizer.Memory>) -> VisionTextRecognizer {
        VisionTextRecognizer(reader: { try vision.read($0, $1, $2) }, fallbacks: [.gpu, .cpu], memory: memory)
    }

    func fresh() -> Locked<VisionTextRecognizer.Memory> { Locked(initialState: VisionTextRecognizer.Memory()) }

    @Test func theDefaultReadingIsAllThereIs() async throws {
        let vision = FakeVision(failing: []), memory = fresh()
        let lines = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(lines.map(\.text) == [FakeVision.line])
        #expect(vision.calls() == [.automatic])
        #expect(memory.withLock { $0.device } == nil)
    }

    @Test func theDefaultFailingIsReadOnTheGPU() async throws {
        let vision = FakeVision(failing: [.automatic]), memory = fresh()
        let lines = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(lines.map(\.text) == [FakeVision.line])
        // The default again once (a request right after its models were compiled may fail once), then the GPU.
        #expect(vision.calls() == [.automatic, .automatic, .gpu])
        #expect(memory.withLock { $0.device } == .gpu)
    }

    @Test func theDefaultAndTheGPUFailingIsReadOnTheCPU() async throws {
        let vision = FakeVision(failing: [.automatic, .gpu]), memory = fresh()
        let lines = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(lines.map(\.text) == [FakeVision.line])
        #expect(vision.calls() == [.automatic, .automatic, .gpu, .cpu])
        #expect(memory.withLock { $0.device } == .cpu)
    }

    @Test func everyDeviceFailingFailsAndSaysTheScreenshotWasNotRead() async throws {
        let vision = FakeVision(failing: [.automatic, .gpu, .cpu]), memory = fresh()
        let recognizer = recognizer(vision, memory)
        // The default's error, the first.
        await #expect(throws: ReadFailed(device: .automatic)) {
            try await recognizer.recognize(image: image, languages: languages)
        }
        #expect(vision.calls() == [.automatic, .automatic, .gpu, .cpu])
        // None read: nothing learnt (an image no device reads says nothing of the default).
        #expect(memory.withLock { $0.device } == nil)

        // As a screenshot pasted into a draft: the failure is said, never the error's own text.
        do {
            _ = try await ScreenText.recognize(image, with: recognizer, languages: languages)
            Issue.record("read")
        } catch {
            for (language, expected) in [("en", "The screenshot couldn't be read, so it isn't attached"), ("zh-Hans", "截图识别失败，没有附上")] {
                let messages = Composer.ReplyMessages.make(language: language)
                #expect(messages.describe(failure: error) == expected)
                #expect(messages.unreadable == expected)
            }
        }
        // `ScreenText.Problem`s keep their own words.
        let messages = Composer.ReplyMessages.english
        #expect(messages.describe(failure: ScreenText.Problem.timedOut) == messages.timedOut)
        #expect(messages.describe(failure: ScreenText.Problem.noText) == messages.noText)
        #expect(messages.describe(failure: NSError(domain: "CRImageReaderErrorDomain", code: 1)) == messages.unreadable)
    }

    @Test func afterTheDefaultFailedTheNextReadGoesStraightToTheDeviceThatRead() async throws {
        let vision = FakeVision(failing: [.automatic]), memory = fresh()
        _ = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(vision.calls() == [.automatic, .automatic, .gpu])

        // The next read, by another recognizer of the process (`Platform.current.text` makes one each time).
        _ = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(vision.calls() == [.gpu])
        // Even with the default working again: it isn't tried.
        vision.failing.withLock { $0 = [] }
        _ = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(vision.calls() == [.gpu])

        // The GPU failing then: the CPU, and the CPU from then on; never the default.
        vision.failing.withLock { $0 = [.automatic, .gpu] }
        _ = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(vision.calls() == [.gpu, .cpu])
        _ = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        #expect(vision.calls() == [.cpu])
        #expect(memory.withLock { $0.device } == .cpu)
    }

    @Test func manyReadsAtOnceAgreeOnTheDevice() async throws {
        let vision = FakeVision(failing: [.automatic]), memory = fresh()
        let recognizer = recognizer(vision, memory)
        try await withThrowingTaskGroup(of: [RecognizedLine].self) { group in
            for _ in 0..<16 { group.addTask { try await recognizer.recognize(image: image, languages: languages) } }
            for try await lines in group { #expect(lines.map(\.text) == [FakeVision.line]) }
        }
        #expect(memory.withLock { $0.device } == .gpu)
        _ = vision.calls()
        _ = try await recognizer.recognize(image: image, languages: languages)
        #expect(vision.calls() == [.gpu])
    }

    @Test func preparingWarmsUpTheFirstFallbackOnceForTheLanguages() async throws {
        let vision = FakeVision(failing: []), memory = fresh()
        let recognizer = recognizer(vision, memory)
        await recognizer.prepare(languages: languages)
        #expect(vision.calls() == [.automatic, .gpu])
        // Once for these languages; other ones are other models.
        await recognizer.prepare(languages: languages)
        #expect(vision.calls() == [.automatic])
        await recognizer.prepare(languages: ["en-US"])
        #expect(vision.calls() == [.automatic, .gpu])
        // Warmed up isn't failed: reads stay on the default.
        #expect(memory.withLock { $0.device } == nil)
        _ = try await recognizer.recognize(image: image, languages: languages)
        #expect(vision.calls() == [.automatic])
    }

    @Test func preparingWithTheDefaultFailingGoesToTheFallback() async throws {
        let vision = FakeVision(failing: [.automatic]), memory = fresh()
        let recognizer = recognizer(vision, memory)
        await recognizer.prepare(languages: languages)
        // The GPU read the blank image: warmed up on the way, not twice.
        #expect(vision.calls() == [.automatic, .automatic, .gpu])
        #expect(memory.withLock { $0.device } == .gpu)
        _ = try await recognizer.recognize(image: image, languages: languages)
        #expect(vision.calls() == [.gpu])
    }

    @Test func theLogSaysTheDeviceAndTheErrorKindNeverTheText() async throws {
        let heard = Locked<[String]>(initialState: [])
        let stop = CoreLog.listen { message in heard.withLock { $0.append(message) } }
        defer { stop() }
        let vision = FakeVision(failing: [.automatic]), memory = fresh()
        _ = try await recognizer(vision, memory).recognize(image: image, languages: languages)
        let logged = heard.withLock { $0 }
        #expect(logged.contains("screenshot: read on GPU"), "\(logged)")
        #expect(logged.contains { $0.hasPrefix("screenshot: not read on default (ReadFailed ") }, "\(logged)")
        #expect(!logged.contains { $0.contains(FakeVision.line) }, "\(logged)")
    }

    /// Vision's own: a fallback puts every stage of the request on its device (one that can't run there on the CPU),
    /// without reading anything.
    @Test func aFallbackPutsTheRequestOnItsDevice() throws {
        #expect(VisionTextRecognizer.fallbackDevices.last == .cpu)
        for device in VisionTextRecognizer.fallbackDevices {
            let request = VNRecognizeTextRequest()
            try VisionTextRecognizer.place(request, on: device)
            let stages = try request.supportedComputeStageDevices
            #expect(!stages.isEmpty)
            for (stage, supported) in stages {
                let expected: Device = supported.contains { VisionTextRecognizer.kind(of: $0) == device } ? device : .cpu
                #expect(request.computeDevice(for: stage).flatMap(VisionTextRecognizer.kind(of:)) == expected, "\(stage)")
            }
        }
    }
}
#endif
