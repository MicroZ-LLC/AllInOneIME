import Foundation
import Testing
@testable import AllInOneIMECore

/// Fuzzy pinyin's rules read from rime-ice's own schema (Scripts/build-rime-data.sh), as the input method patches it;
/// the rules themselves are tested in the core (FuzzyPinyinTests).
struct FuzzyPinyinSchemaTests {
    static let schema = RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml")
    /// Run before Scripts/build-rime-data.sh, the test is skipped, and says so; with ALLINONEIME_REQUIRE_RIME_DATA=1 a
    /// missing schema fails it.
    static var runs: Bool { RimeFixture.dataRequired || FileManager.default.fileExists(atPath: schema.path) }

    @Test(.enabled(if: runs, "no rime-ice schema in ThirdParty/rime-data or $ALLINONEIME_THIRDPARTY/rime-data (Scripts/build-rime-data.sh)"))
    func theRealSchemaHasRules() throws {
        guard let text = try? String(contentsOf: Self.schema, encoding: .utf8) else {
            Issue.record("no rime-ice schema at \(Self.schema.path) (Scripts/build-rime-data.sh)")
            return
        }
        let rules = FuzzyPinyin.algebra(ofSchema: text)
        #expect(rules.contains("abbrev/^([a-z]).+$/$1/") && !rules.contains { $0.contains("#") || $0.hasPrefix("derive/^([zcs])h/$1/") })
    }
}
