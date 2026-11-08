import Foundation
import Testing

/// The self-test starts a Rime of its own, on a user folder of its own, and never writes the fuzzy pinyin patch: the
/// characters following the system's languages (`RimeFuzzy.follow`, as its fake fields are focused) write nothing while it
/// runs, as the patch is in the user's Rime folder. Read from the sources, as the input method can't be run here.
struct SelfTestRimePatchTests {
    @Test func followingTheSystemsLanguagesWritesNothingInTheSelfTest() throws {
        let body = try #require(InputMenuWritesTests.body(of: "follow", in: try InputMenuWritesTests.source("main.swift")))
        #expect(body.contains("Config.selfTestURL == nil"))
    }
}
