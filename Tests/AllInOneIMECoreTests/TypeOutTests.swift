import Foundation
import Testing
@testable import AllInOneIMECore

struct TypeOutTests {
    @Test func aPauseBeforeEachCharacterLongerAfterPunctuation() {
        // A fixed "random" in the middle: every pause is the average, but after punctuation and spaces.
        let delays = TypeOut.delays(for: "Hi, you", rate: 16, random: { 0.5 })
        let base = 1 / 16.0
        #expect(delays.count == 7)
        #expect(abs(delays[0] - base) < 1e-9 && abs(delays[1] - base) < 1e-9)
        #expect(abs(delays[3] - base * 3) < 1e-9)  // after ","
        #expect(abs(delays[4] - base * 1.5) < 1e-9)  // after " "
        // Chinese punctuation too; one Character per emoji or combined letter.
        #expect(TypeOut.delays(for: "好。👍🏽é", rate: 32, random: { 0.5 }).count == 4)
        // The pace varies within 60–140 % of the average.
        let varied = TypeOut.delays(for: "abcdefgh", rate: 8).map { $0 * 8 }
        #expect(varied.allSatisfy { $0 >= 0.6 && $0 <= 1.4 + 1e-9 })
    }

    @Test func theRateStaysBetweenSixSecondsACharacterAndFortyASecond() {
        #expect(abs(TypeOut.delays(for: "a", rate: 0.01, random: { 0.5 })[0] - 6) < 1e-9)
        #expect(abs(TypeOut.delays(for: "a", rate: 1000, random: { 0.5 })[0] - 1 / 40.0) < 1e-9)
        // The slider: a log scale from 6 s a character to 40 a second, and back.
        #expect(abs(TypeOut.rate(at: 0) - 1 / 6.0) < 1e-9 && abs(TypeOut.rate(at: 1) - 40) < 1e-9)
        for rate in [1 / 6.0, 0.5, 1, 16, 40] {
            #expect(abs(TypeOut.rate(at: TypeOut.position(of: rate)) - rate) < 1e-9)
        }
        #expect(TypeOut.position(of: 0.01) == 0 && TypeOut.position(of: 100) == 1)
    }

    @Test func speedingUpAndSlowingDownInBursts() {
        // Bursts of 3–8 characters, each at its own pace from half to twice the rate (plus the usual 60–140 %).
        let text = String(repeating: "a", count: 400)
        let delays = TypeOut.delays(for: text, rate: 16, varies: true)
        let slowest = 2 / 16.0 * 1.4, fastest = 1 / 32.0 * 0.6
        #expect(delays.count == 400 && delays.allSatisfy { $0 >= fastest - 1e-9 && $0 <= slowest + 1e-9 })
        // It does change pace: both quick and slow characters in a long text.
        #expect(delays.contains { $0 < 1 / 24.0 } && delays.contains { $0 > 1 / 10.0 })
        // A fixed "random": every burst at the rate itself.
        #expect(TypeOut.delays(for: "abcdef", rate: 16, varies: true, random: { 0.5 }).allSatisfy { abs($0 - 1 / 16.0) < 1e-9 })
    }

    @Test func offByDefaultInTheConfig() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(!config.typeOut && config.typeOutRate == 16 && !config.typeOutVaries)
        let set = try JSONDecoder().decode(Config.self, from: Data(#"{"typeOut": true, "typeOutRate": 0.5, "typeOutVaries": true}"#.utf8))
        #expect(set.typeOut && set.typeOutRate == 0.5 && set.typeOutVaries)
        // Round trip.
        let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(set))
        #expect(again.typeOutRate == 0.5 && again.typeOutVaries)
    }

    @Test func theOldSpeedSettingCarriesOver() throws {
        func decode(_ speed: String) throws -> Config {
            try JSONDecoder().decode(Config.self, from: Data(#"{"typeOutSpeed": "\#(speed)"}"#.utf8))
        }
        let random = try decode("random"), slow = try decode("slow"), fast = try decode("fast")
        #expect(random.typeOutRate == 16 && random.typeOutVaries)
        #expect(slow.typeOutRate == 8 && !slow.typeOutVaries)
        #expect(fast.typeOutRate == 32 && !fast.typeOutVaries)
    }
}
