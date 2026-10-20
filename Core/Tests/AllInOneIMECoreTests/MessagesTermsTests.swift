import Foundation
import Testing
@testable import AllInOneIMECore

/// The composer's built-in messages are made with the platform's terms as they are when asked for, not those of the
/// first use: on Windows the keys' names, on the Mac its symbols, in the same process (the tests run both).
struct MessagesTermsTests {
    @Test func replysMessagesNameThePlatformsKeysEachTime() {
        let windows = Platform.$override.withValue(Platform(terms: .windows)) { Composer.ReplyMessages.english.hint }
        let mac = Platform.$override.withValue(Platform(terms: .mac)) { Composer.ReplyMessages.english.hint }
        #expect(windows.contains("Ctrl+V") && !windows.contains("⌃V"), "\(windows)")
        #expect(mac.contains("⌃V") && !mac.contains("Ctrl+V"), "\(mac)")
        let reading = Platform.$override.withValue(Platform(terms: .windows)) { Composer.ReplyMessages.chinese.reading }
        #expect(reading == Composer.ReplyMessages.make(language: "zh-Hans", terms: .windows).reading)
    }
}
