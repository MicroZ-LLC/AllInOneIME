import Foundation
import Testing
@testable import AllInOneIMECore

struct TypeOutTests {
    @Test func aPauseBeforeEachCharacterLongerAfterPunctuation() {
        // A fixed "random" in the middle: every pause is the average, but after punctuation and spaces.
        let delays = TypeOut.delays(for: "Hi, you", speed: .normal, random: { 0.5 })
        let base = 1 / TypeOut.Speed.normal.charactersPerSecond
        #expect(delays.count == 7)
        #expect(abs(delays[0] - base) < 1e-9 && abs(delays[1] - base) < 1e-9)
        #expect(abs(delays[3] - base * 3) < 1e-9)  // after ","
        #expect(abs(delays[4] - base * 1.5) < 1e-9)  // after " "
        // Chinese punctuation too; one Character per emoji or combined letter.
        #expect(TypeOut.delays(for: "好。👍🏽é", speed: .fast, random: { 0.5 }).count == 4)
        // The pace varies within 60–140 % of the average.
        let varied = TypeOut.delays(for: "abcdefgh", speed: .slow).map { $0 * TypeOut.Speed.slow.charactersPerSecond }
        #expect(varied.allSatisfy { $0 >= 0.6 && $0 <= 1.4 + 1e-9 })
        #expect(TypeOut.Speed.slow.charactersPerSecond < TypeOut.Speed.normal.charactersPerSecond
                && TypeOut.Speed.normal.charactersPerSecond < TypeOut.Speed.fast.charactersPerSecond)
    }

    @Test func randomSpeedVariesInBursts() {
        // Bursts of 3–8 characters, each at its own pace between slow and fast (plus the usual 60–140 %).
        let text = String(repeating: "a", count: 400)
        let delays = TypeOut.delays(for: text, speed: .random)
        let slowest = 1 / TypeOut.Speed.slow.charactersPerSecond * 1.4, fastest = 1 / TypeOut.Speed.fast.charactersPerSecond * 0.6
        #expect(delays.count == 400 && delays.allSatisfy { $0 >= fastest - 1e-9 && $0 <= slowest + 1e-9 })
        // It does change pace: both quick and slow characters in a long text.
        #expect(delays.contains { $0 < 1 / 20.0 } && delays.contains { $0 > 1 / 12.0 })
        // A fixed "random": every burst at the same pace, so the same as the middle speed.
        #expect(TypeOut.delays(for: "abcdef", speed: .random, random: { 0.5 }).allSatisfy { abs($0 - 1 / 20.0) < 1e-9 })
    }

    @Test func offByDefaultInTheConfig() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(!config.typeOut && config.typeOutSpeed == .normal)
        let set = try JSONDecoder().decode(Config.self, from: Data(#"{"typeOut": true, "typeOutSpeed": "fast"}"#.utf8))
        #expect(set.typeOut && set.typeOutSpeed == .fast)
    }
}
