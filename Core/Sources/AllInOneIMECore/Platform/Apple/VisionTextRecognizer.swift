#if canImport(Vision)
import CoreML
import Foundation
import Vision

/// Vision's text recognition (`VNRecognizeTextRequest`), accurate and with language correction. On the device: the image
/// goes nowhere. The first request loads its models (seconds); `prepare` does that ahead of time.
///
/// Vision picks where its models run (the Neural Engine on Apple silicon), and there a read may fail
/// (`CRImageReaderError`), in a long-running process again and again. A read the default fails is read again on the GPU,
/// then on the CPU (`Device`); once one of them has read, the process goes straight to it from then on.
public struct VisionTextRecognizer: TextRecognizer {
    /// Where Vision runs its models for a read.
    enum Device: String, Sendable {
        /// Vision's own pick.
        case automatic = "default"
        case gpu = "GPU"
        case cpu = "CPU"
    }

    /// Reads an image in languages on a device, blocking (Vision's `read`; a test's fake).
    typealias Reader = @Sendable (_ image: Data, _ languages: [String], _ device: Device) throws -> [RecognizedLine]

    /// What a process has learnt of the devices (`memory`).
    struct Memory {
        /// The device that read once the default had failed: reads go straight to it. Nil: the default.
        var device: Device?
        /// The languages the first fallback was warmed up in (`prepare`).
        var warmed: Set<[String]> = []
    }

    private let reader: Reader
    /// The devices a read the default fails falls back on, in order.
    private let fallbacks: [Device]
    private let memory: Locked<Memory>

    public init() {
        self.init(reader: Self.read, fallbacks: Self.fallbackDevices, memory: Self.processMemory)
    }

    /// A recognizer reading with `reader`, falling back on `fallbacks`, remembering in `memory` (shared by the copies).
    init(reader: @escaping Reader, fallbacks: [Device] = [.gpu, .cpu], memory: Locked<Memory> = Locked(initialState: Memory())) {
        self.reader = reader
        self.fallbacks = fallbacks
        self.memory = memory
    }

    /// The process's: every `VisionTextRecognizer()` shares it.
    static let processMemory = Locked(initialState: Memory())

    static let log = CoreLog(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")

    public func prepare(languages: [String]) async {
        // A blank image read once in the same languages, on the device reads go to: Vision's models for them are loaded
        // for the next request (the CJK ones and the Latin ones are apart). Nothing is found in it. At utility priority,
        // as all of it: typing goes first.
        guard let png = Self.blankPNG else { return }
        let device = try? await Self.blocking(qos: .utility) { try readOnAny(png, languages: languages, purpose: "warm-up").device }
        // The default read: the first fallback too, once a process for these languages, its models compiled (once a Mac,
        // ~14 s, then kept on disk) and loaded, so that a read the default fails is read on it in a fraction of a second,
        // well within `ScreenText.timeout`. (A fallback read: it was on the way.)
        guard device == .automatic, let next = fallbacks.first,
              memory.withLock({ $0.warmed.insert(languages).inserted }) else { return }
        do {
            _ = try await Self.blocking(qos: .utility) { try reader(png, languages, next) }
            Self.log.notice("text recognition: warmed up on \(next.rawValue)")
        } catch {
            Self.log.notice("text recognition: not warmed up on \(next.rawValue) (\(Self.kind(error)))")
        }
    }

    public func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
        try await Self.blocking(qos: .userInitiated) { try readOnAny(image, languages: languages, purpose: "screenshot").lines }
    }

    /// `image`'s lines and the device that read them: the default (again once: right after its models were first
    /// compiled, a request may fail once), else each fallback in turn; once the default has failed and a fallback has
    /// read, that one first, the default no more. When none reads, the first one's error. Blocking. The log has the
    /// device that read, and the kind of each failure: never the text.
    func readOnAny(_ image: Data, languages: [String], purpose: String) throws -> (lines: [RecognizedLine], device: Device) {
        let remembered = memory.withLock { $0.device }
        let order = remembered.map { first in [first] + fallbacks.filter { $0 != first } } ?? [.automatic, .automatic] + fallbacks
        var firstError: Error?
        for device in order {
            do {
                let lines = try reader(image, languages, device)
                if device != .automatic { memory.withLock { $0.device = device } }
                Self.log.notice("\(purpose): read on \(device.rawValue)")
                return (lines, device)
            } catch {
                Self.log.notice("\(purpose): not read on \(device.rawValue) (\(Self.kind(error)))")
                if firstError == nil { firstError = error }
            }
        }
        throw firstError ?? ScreenText.Problem.unsupported
    }

    /// `work` on a queue of its own at `qos`, not the async pool: Vision's requests block.
    static func blocking<T: Sendable>(qos: DispatchQoS.QoSClass, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: qos).async { continuation.resume(with: Result(catching: work)) }
        }
    }

    /// An error's kind for the log: its type and code (Vision's errors are NSErrors), never its text.
    static func kind(_ error: Error) -> String {
        "\(String(describing: type(of: error))) \((error as NSError).code)"
    }

    static func read(_ image: Data, languages: [String], on device: Device) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Only the languages Vision reads (it has no Hindi, say), by its own codes; none of them: its default.
        let wanted = visionCodes(languages, supported: (try? request.supportedRecognitionLanguages()) ?? [])
        if !wanted.isEmpty { request.recognitionLanguages = wanted }
        if device != .automatic, #available(macOS 14, iOS 17, tvOS 17, *) { try place(request, on: device) }
        let handler = VNImageRequestHandler(data: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            // Vision's boxes have their origin at the bottom left.
            let box = observation.boundingBox
            return RecognizedLine(text: best.string, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
                                  confidence: Double(best.confidence))
        }
    }

    /// Every stage of `request` on `device` (one that can't run there: on the CPU, not left to Vision's pick).
    @available(macOS 14, iOS 17, tvOS 17, *)
    static func place(_ request: VNRequest, on device: Device) throws {
        for (stage, supported) in try request.supportedComputeStageDevices {
            let choice = supported.first { kind(of: $0) == device } ?? supported.first { kind(of: $0) == .cpu }
            if let choice { request.setComputeDevice(choice, for: stage) }
        }
    }

    @available(macOS 14, iOS 17, tvOS 17, *)
    static func kind(of device: MLComputeDevice) -> Device? {
        switch device {
        case .gpu: return .gpu
        case .cpu: return .cpu
        default: return nil
        }
    }

    /// The fallbacks this device has: its GPU, then its CPU (none before the systems that let a request pick).
    static var fallbackDevices: [Device] {
        guard #available(macOS 14, iOS 17, tvOS 17, *) else { return [] }
        let kinds = MLComputeDevice.allComputeDevices.compactMap(kind(of:))
        return [Device.gpu, .cpu].filter(kinds.contains)
    }

    /// BCP-47 codes (`TextRecognizer.recognize`) as Vision names them, in order, once each: the same code, else one of
    /// the same language ("vi-VN" → Vision's "vi-VT"); those it doesn't read are left out.
    static func visionCodes(_ languages: [String], supported: [String]) -> [String] {
        func base(_ code: String) -> String { String(code.lowercased().prefix { $0 != "-" && $0 != "_" }) }
        var seen = Set<String>()
        return languages.compactMap { code -> String? in
            let lower = code.lowercased()
            // Chinese by its script: zh-Hans and zh-Hant are different models.
            let match = supported.first { $0.lowercased() == lower }
                ?? (base(code) == "zh" ? nil : supported.first { base($0) == base(code) })
            return match.flatMap { seen.insert($0).inserted ? $0 : nil }
        }
    }

    /// A 128×64 white PNG.
    static let blankPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAIAAAABACAIAAABdtOgoAAAAbUlEQVR42u3RMQEAAAyDsPo3zWTsCRLI0muzAAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQAAACAAAAQAgAAAEAIAAABAAAAIAQHUVXqWSTHRRKwAAAABJRU5ErkJggg==")
}
#endif
