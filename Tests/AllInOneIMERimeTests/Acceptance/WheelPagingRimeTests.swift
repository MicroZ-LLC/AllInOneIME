import AllInOneIMECore
import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMERime

// Owner decisions 2026-11-14 (0.7.5), part 4.1, with the real librime and rime-ice (`make deps`), written from the spec
// by a separate agent; the implementer doesn't edit it (AGENTS.md rule 11). Pinyin candidates on more than one page,
// through a field's session (`FakeHost`, the shell's `SessionEvent.scroll(steps)`): wheel down (steps > 0) shows the next
// page, wheel up (steps < 0) the previous, exactly as Page Down / Page Up (the = / - keys) would; on the first page wheel
// up does nothing, on the last wheel down does nothing; one page per wheel event whatever its step count; nothing is
// committed and the pinyin stays as typed. Both candidate layouts (row and column). Skipped without rime-ice's data,
// unless `make test` requires it (ALLINONEIME_REQUIRE_RIME_DATA).
//
// Wheel paging in the other lists, and pinyin and Hindi candidates on one page: OwnerDecisions075WheelTests (Core).

enum WheelPagingRime {
    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent("build/rime_ice.table.bin").path)
    }

    static let equal = KeyEvent(keyCode: 0x18, characters: "=")
    static let minus = KeyEvent(keyCode: 0x1B, characters: "-")

    /// A field's session whose level one is librime, Chinese first, the candidates laid out as `layout`, `typed` typed.
    static func typing(_ typed: String, layout: CandidateArrangement) throws -> FakeHost {
        var config = Config.default
        config.uiLanguage = "en"
        config.candidateLayout = layout
        config.inputLanguages = [.chinese, .english]
        config.defaultInput = .chinese
        let fixed = config
        let rime = try RimeFixture.session()
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(rime) }
        let host = FakeHost(services: services)
        host.focus()
        for character in typed { host.press(key(character)) }
        let state = host.composer.engineState
        try #require(state.isComposing && state.candidates.count > 1 && state.pageNumber == 0 && !state.isLastPage,
                     "\(typed): \(state)")
        return host
    }

    /// Which page shows, the candidate highlighted, the candidates on it.
    struct Page: Equatable, CustomStringConvertible {
        var number: Int
        var highlighted: Int
        var candidates: [String]

        var description: String { "page \(number) ⟨\(highlighted)⟩ \(candidates)" }
    }

    static func page(_ host: FakeHost) -> Page {
        let state = host.composer.engineState
        return Page(number: state.pageNumber, highlighted: state.highlighted, candidates: state.candidates.map(\.text))
    }

    /// Nothing went in, the pinyin is as typed, and the panel shows the page the engine is on.
    static func asTyped(_ host: FakeHost, _ typed: String, _ what: String) {
        let state = host.composer.engineState
        #expect(host.document.isEmpty && state.isComposing && host.composer.engine?.rawInput == typed,
                "\(typed) \(what): nothing put in (\(host.document)), the pinyin as typed (\(host.composer.engine?.rawInput ?? "-"))")
        #expect(host.panel?.rows.map(\.text) == state.candidates.map(\.text) && host.panel?.highlighted == state.highlighted,
                "\(typed) \(what): the panel shows the page (\(String(describing: host.panel?.rows.map(\.text))))")
    }
}

extension RimeEngineTests {
    /// In the serialized suite of the process's librime (`RimeEngineTests`), named so for `--filter WheelPagingRime`.
    @Suite(.enabled(if: WheelPagingRime.dataAvailable || RimeFixture.dataRequired, "needs rime-ice's data (make deps)"))
    struct WheelPagingRimeTests {
        /// Wheel down is =, wheel up is -: the same page, the same candidate highlighted; nothing before the first page; one
        /// page per event.
        @Test(arguments: [CandidateArrangement.horizontal, .vertical])
        func wheelTurnsPinyinCandidatePages(layout: CandidateArrangement) throws {
            for typed in ["nihao", "shi"] {
                // What the page keys do, on a composition of its own.
                let keys = try WheelPagingRime.typing(typed, layout: layout)
                let first = WheelPagingRime.page(keys)
                keys.press(WheelPagingRime.equal)
                let next = WheelPagingRime.page(keys)
                try #require(next.number == 1 && next.candidates != first.candidates, "\(typed): = turns the page (\(next))")

                let wheel = try WheelPagingRime.typing(typed, layout: layout)
                #expect(WheelPagingRime.page(wheel) == first, "\(typed): \(WheelPagingRime.page(wheel))")
                wheel.send(.scroll(1))
                #expect(WheelPagingRime.page(wheel) == next, "\(typed) \(layout): wheel down is = (\(WheelPagingRime.page(wheel)) / \(next))")
                WheelPagingRime.asTyped(wheel, typed, "wheel down")

                wheel.send(.scroll(-1))
                #expect(WheelPagingRime.page(wheel) == first, "\(typed) \(layout): wheel up is - (\(WheelPagingRime.page(wheel)))")
                WheelPagingRime.asTyped(wheel, typed, "wheel up")
                wheel.send(.scroll(-1))
                #expect(WheelPagingRime.page(wheel) == first, "\(typed) \(layout): the first page, wheel up: nothing (\(WheelPagingRime.page(wheel)))")
                WheelPagingRime.asTyped(wheel, typed, "wheel up on the first page")

                // A fast spin's event of 3 steps: one page, not three.
                wheel.send(.scroll(3))
                #expect(WheelPagingRime.page(wheel) == next, "\(typed) \(layout): one page per event (\(WheelPagingRime.page(wheel)))")
                wheel.send(.scroll(-3))
                #expect(WheelPagingRime.page(wheel) == first, "\(typed) \(layout): one page back per event (\(WheelPagingRime.page(wheel)))")
                WheelPagingRime.asTyped(wheel, typed, "a fast spin")

                // Page by page with the wheel, as with =.
                let twice = try WheelPagingRime.typing(typed, layout: layout)
                twice.send(.scroll(1))
                twice.send(.scroll(1))
                keys.press(WheelPagingRime.equal)
                #expect(WheelPagingRime.page(twice) == WheelPagingRime.page(keys) && WheelPagingRime.page(twice).number == 2,
                        "\(typed) \(layout): two events, two pages (\(WheelPagingRime.page(twice)) / \(WheelPagingRime.page(keys)))")
            }
        }

        /// On the last page wheel down does nothing, as = does nothing there; wheel up turns back from it.
        @Test(arguments: [CandidateArrangement.horizontal, .vertical])
        func wheelDownOnTheLastPageDoesNothing(layout: CandidateArrangement) throws {
            let typed = "kao"
            let host = try WheelPagingRime.typing(typed, layout: layout)
            var turns = 0
            while !host.composer.engineState.isLastPage, turns < 500 {
                host.press(WheelPagingRime.equal)
                turns += 1
            }
            let last = WheelPagingRime.page(host)
            try #require(host.composer.engineState.isLastPage && last.number > 0, "\(typed): \(last) after \(turns) pages")
            host.send(.scroll(1))
            #expect(WheelPagingRime.page(host) == last, "\(layout): the last page, wheel down: nothing (\(WheelPagingRime.page(host)))")
            WheelPagingRime.asTyped(host, typed, "wheel down on the last page")
            host.send(.scroll(-1))
            #expect(WheelPagingRime.page(host).number == last.number - 1,
                    "\(layout): wheel up from the last page: the one before (\(WheelPagingRime.page(host)))")
            WheelPagingRime.asTyped(host, typed, "wheel up from the last page")
        }
    }
}
