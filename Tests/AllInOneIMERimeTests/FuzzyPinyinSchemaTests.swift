import Foundation
import Testing
@testable import AllInOneIMECore

/// Fuzzy pinyin's rules read from rime-ice's own schema (`make deps`), as the input method patches it; the rules
/// themselves are tested in the core (FuzzyPinyinTests).
struct FuzzyPinyinSchemaTests {
    @Test func theRealSchemaHasRules() throws {
        let url = RimeFixture.sharedData.appendingPathComponent("rime_ice.schema.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }  // before `make deps`
        let rules = FuzzyPinyin.algebra(ofSchema: text)
        #expect(rules.contains("abbrev/^([a-z]).+$/$1/") && !rules.contains { $0.contains("#") || $0.hasPrefix("derive/^([zcs])h/$1/") })
    }
}
