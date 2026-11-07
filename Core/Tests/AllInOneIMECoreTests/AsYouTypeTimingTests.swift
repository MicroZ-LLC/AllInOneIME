import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// How the lists that fill as you type behave on a key, timed (printed for the record): a script extension's `list` (the
/// repository's example, Examples/extensions/clock.sh) and a send command's recipients. Each key leaves rows up: the
/// panel never goes blank while the new text's answer is on its way.
@Suite(.serialized)
struct AsYouTypeTimingTests {
    static let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Examples/extensions")

    func ms(_ seconds: TimeInterval) -> String { String(format: "%.0f ms", seconds * 1000) }

    @Test func aListNeverGoesBlankAsItsTextIsTyped() async throws {
        let folder = ScriptFolder()
        folder.add("clock.sh", try String(contentsOf: Self.examples.appendingPathComponent("clock.sh"), encoding: .utf8))
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        let index = folder.load()
        services.loadExtensions = { _, _ in index }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        host.type("@clock")
        let picked = Date()
        host.press(FakeHost.tab)
        #expect(host.settle(timeout: 10) { host.composer.currentList?.items.isEmpty == false })
        print("list: first rows after the command was picked: \(ms(Date().timeIntervalSince(picked)))")
        var blank: [String] = []
        for key in ["l", "o", "n"] {
            let typed = Date()
            host.type(key)
            let empty = host.panel?.rows.isEmpty ?? true
            // Answered for the text now: its first row can be picked.
            let answered = host.settle(timeout: 10) { host.composer.listItem != nil }
            let took = Date().timeIntervalSince(typed)
            blank.append("\(key): rows of the new text after \(ms(took)), blank \(empty ? ms(took) : "0 ms")\(answered ? "" : " (no answer)")")
            #expect(!empty, "rows up on the key")
        }
        print("list as you type (clock.sh, queryDelay 100 ms): " + blank.joined(separator: "; "))
    }

    @Test func recipientsAreListedOnTheKey() async {
        let book = (0..<3000).map { Contact(name: "Person \($0)", otherNames: ["P\($0)"], handles: ["+1 555 \(1000 + $0)", "p\($0)@example.com"]) }
        + [Contact(name: "张三", handles: ["+86 138 0000 0000"])]
        var services = SessionServices(loadSettings: { .default })
        services.levelOne = { .engine(FakeEngine()) }
        services.programInstalled = { _ in true }
        services.loadContacts = { book }
        services.cachedContacts = { book }
        let host = FakeHost(services: services)
        host.focus()
        host.composer.setInputMode(.english)
        host.type("@imessage")
        host.press(FakeHost.tab)
        var lines: [String] = []
        for key in ["p", "e", "r", "s"] {
            let typed = Date()
            host.type(key)
            let on = !(host.panel?.rows.isEmpty ?? true)
            let shown = host.settle(timeout: 5) { !(host.panel?.rows.isEmpty ?? true) }
            lines.append("\(key): \(on ? "on the key" : "after \(ms(Date().timeIntervalSince(typed)))")\(shown ? "" : " (none)") (\(ms(Date().timeIntervalSince(typed))))")
            #expect(on)
        }
        print("recipients (3,001 contacts): " + lines.joined(separator: "; "))
    }
}
