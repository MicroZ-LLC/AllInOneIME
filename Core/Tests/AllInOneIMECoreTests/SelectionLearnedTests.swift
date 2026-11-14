import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// "Use the selected text" learned per app (0.7.5), as the apps that can't take a typo back are: an app whose field didn't
/// take a result in place of the selection is kept on this device (`LearnedStore.selectionOff`), and "@" no longer reads
/// its selection; `useSelection` off in the config still turns it off everywhere.
extension InputSessionTests {
    @Test func theAppsWhoseSelectionIsntUsedAreKeptOnThisDevice() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selection-off-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("learned.json")
        func store() -> LearnedStore {
            LearnedStore(file: file, autocomplete: AutocompleteStore(), temperature: TemperatureSupport(file: nil))
        }
        let learned = store()
        #expect(!learned.turnSelectionOff(in: ""), "never an app without an id")
        #expect(learned.turnSelectionOff(in: "com.Example.Editor") && !learned.turnSelectionOff(in: "com.example.editor"))
        #expect(learned.selectionOff(in: "COM.EXAMPLE.EDITOR") && !learned.selectionOff(in: "com.example.other"))
        #expect(learned.selectionOffApps == ["com.Example.Editor"], "as it was told")
        #expect(learned.items(appName: { _ in nil }).isEmpty, "a row of its own in Learned…, not among the items")
        #expect(LearnedStore.selectionOffText("com.example.editor", name: { _ in "Editor" }).contains("Editor"))
        learned.flush()
        let again = store()
        #expect(again.selectionOff(in: "com.example.editor"), "kept in the store's file")
        again.forgetSelectionOff(in: "com.example.editor")
        #expect(!again.selectionOff(in: "com.example.editor") && again.selectionOffApps.isEmpty, "Forget: used again")
        again.turnSelectionOff(in: "com.example.editor")
        again.forgetAll()
        #expect(again.selectionOffApps.isEmpty, "Forget All forgets them too")
    }

    @Test func aFieldThatDidntTakeTheResultIsToldApart() {
        let selection = Composer.Selection(text: "world", range: 6..<11)
        func read(_ document: String) -> (Range<Int>) -> String? {
            { range in
                let text = document as NSString
                guard range.upperBound <= text.length else { return nil }
                return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
            }
        }
        #expect(SessionText.selectionNotReplaced(selection, by: "there", read: read("hello there")) == false, "taken")
        #expect(SessionText.selectionNotReplaced(selection, by: "there", read: read("hello worldthere")) == true,
                "the selection still there, the result after it")
        #expect(SessionText.selectionNotReplaced(selection, by: "there", read: read("hello world")) == true, "nothing went in")
        #expect(SessionText.selectionNotReplaced(selection, by: "there", read: { _ in nil }) == nil, "the field doesn't say")
        #expect(SessionText.selectionNotReplaced(Composer.Selection(text: "world"), by: "there", read: read("hello world")) == nil,
                "no range (read with Accessibility): not told")
        #expect(SessionText.selectionNotReplaced(selection, by: "world, again", read: read("hello world")) == nil,
                "a result that starts with the selection goes in after it")
        #expect(SessionText.selectionNotReplaced(selection, by: "world", read: read("hello world")) == nil,
                "the same text: nothing to tell apart")
    }

    @Test func anAppThatLearnedItHasNoSelectionRead() async {
        await inEnglish {
            let learned = LearnedStore(file: nil, autocomplete: AutocompleteStore(), temperature: TemperatureSupport(file: nil))
            let host = host { $0.learned = learned }
            func at() -> FieldContext.Parts { host.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure)) }
            #expect(at().contains(.selection), "\(at())")
            learned.turnSelectionOff(in: host.app ?? "")
            #expect(at() == [.secure], "learned: \"@\" doesn't read its selection (\(at()))")
            host.document = "hello world"
            host.selection = 6..<11
            pick("i", in: host)
            #expect(host.composer.selection == nil && !host.composer.draftInPanel, "the command is written in the field, as before")
            // Another app's selection is used as before.
            let other = self.host { $0.learned = learned }
            other.app = "com.example.other"
            other.focus()
            #expect(other.session.fieldWants(for: FakeHost.at, given: FieldContext(read: .secure)).contains(.selection))
        }
    }
}
