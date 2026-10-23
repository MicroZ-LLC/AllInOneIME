import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Stands in for the on-device model: answers every request with `answer`, at once; records the requests.
final class SuggestionsGhostModel: AppleModelBackend, @unchecked Sendable {
    let availability = AppleModelAvailability.available
    let contextSize = 4096
    let supportedLanguages: Set<String> = ["en", "zh"]
    private let lock = NSLock()
    private var asked: [AppleModelRequest] = []
    private let answer: String

    init(answer: String) { self.answer = answer }

    var requests: [AppleModelRequest] { lock.withLock { asked } }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        lock.withLock { asked.append(request) }
        let text = answer
        return AsyncThrowingStream { continuation in
            continuation.yield(AppleModelSnapshot(text: text))
            continuation.finish()
        }
    }
}

/// Suggestions v1, spec 0: at the caret one kind shows at a time; rows (lists, queries, coding) win over ghost text and
/// own Tab while shown. Spec 2: no AI continuation while coding mode is on. The AI continuation is Autocomplete's (its
/// gray text after the caret, `SessionOutput.ghost`), on the on-device model here (spec 6.3). The rig:
/// SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsGhostTextAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) rethrows { try withInterfaceLanguage("en", body) }

    final class Uptime: @unchecked Sendable {
        private let value = Locked<TimeInterval>(initialState: 1000)
        var now: TimeInterval { value.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { value.withLock { $0 += seconds } }
    }

    /// A field with autocomplete on (the on-device model answering `answer`).
    func field(_ world: SuggestionsWorld, model: SuggestionsGhostModel, uptime: Uptime) -> SuggestionsField {
        world.config.autocomplete = true
        return world.field { services in
            services.converter = Converter(loadConfig: { world.config }, appleModel: model)
            services.uptime = { uptime.now }
            services.autocomplete = AutocompleteStore()
        }
    }

    /// The pause after typing runs out (on autocomplete's own clock): what autocomplete asks is answered.
    func pauseEnds(_ field: SuggestionsField, _ uptime: Uptime) {
        uptime.advance(0.4)
        field.host.fireTimers()
        field.settle(timeout: 5) { field.host.ghost != nil }
    }

    /// Ghost text up, then a token a source applies to: the rows take its place, and Tab inserts the row.
    @Test func rowsTakeTheGhostTextsPlace() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.aws()
            let (model, uptime) = (SuggestionsGhostModel(answer: "2 is the prod account."), Uptime())
            let field = field(world, model: model, uptime: uptime)
            field.type("Account 12345678901")
            pauseEnds(field, uptime)
            #expect(field.host.ghost != nil, "autocomplete works here: \(String(describing: field.host.ghost))")
            field.type("2")
            #expect(field.settle { field.shown(["123456789012"]) == ["123456789012"] }, "\(field.rows.map(\.text))")
            #expect(field.host.ghost == nil, "rows win: \(String(describing: field.host.ghost))")
            uptime.advance(1)
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "Account 123456789012 (prod)", "Tab is the rows': \(field.document)")
        }
    }

    /// While rows show, no ghost text comes up after a pause.
    @Test func noGhostTextWhileRowsShow() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let (model, uptime) = (SuggestionsGhostModel(answer: "001 is the crash."), Uptime())
            let field = field(world, model: model, uptime: uptime)
            field.type("See #7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            pauseEnds(field, uptime)
            #expect(field.host.ghost == nil, "\(String(describing: field.host.ghost))")
            uptime.advance(1)
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "See #7001", "\(field.document)")
        }
    }

    /// Coding mode on: no AI continuation (no request, no ghost text).
    @Test func noAIContinuationInCodingMode() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            let (model, uptime) = (SuggestionsGhostModel(answer: "ld, how are you?"), Uptime())
            let field = field(world, model: model, uptime: uptime)
            field.type("Hello wor")
            pauseEnds(field, uptime)
            #expect(field.host.ghost == nil && model.requests.isEmpty, "\(model.requests.count) requests")

            world.codingMode = false
            let prose = self.field(world, model: model, uptime: uptime)
            prose.type("Hello wor")
            pauseEnds(prose, uptime)
            #expect(prose.host.ghost != nil, "off: autocomplete as before")
        }
    }
}
