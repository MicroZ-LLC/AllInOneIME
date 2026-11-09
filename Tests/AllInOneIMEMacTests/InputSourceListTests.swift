import Foundation
import Testing
@testable import AllInOneIMECore

struct InputSourceListTests {
    let ours = "com.aipinyin.inputmethod.AIPinyin"

    /// The list as macOS had it on a Mac where AllInOneIME was enabled but missing from it.
    let system: [[String: Any]] = [
        ["InputSourceKind": "Keyboard Layout", "KeyboardLayout ID": 0, "KeyboardLayout Name": "U.S."],
        ["Bundle ID": "com.apple.CharacterPaletteIM", "InputSourceKind": "Non Keyboard Input Method"],
        ["Bundle ID": "com.apple.inputmethod.SCIM", "Input Mode": "com.apple.inputmethod.SCIM.ITABC",
         "InputSourceKind": "Input Mode"],
        ["Bundle ID": "com.apple.PressAndHold", "InputSourceKind": "Non Keyboard Input Method"],
    ]

    func bundleIDs(_ list: [[String: Any]]) -> [String] { list.map { $0["Bundle ID"] as? String ?? "-" } }

    @Test func addsOurEntryAtTheEndAndKeepsTheRest() throws {
        let added = try #require(InputSourceList.adding(ours, to: system))
        #expect(added.count == system.count + 1)
        // The existing entries are unchanged, including the keyboard layout (which has no Bundle ID).
        #expect(NSArray(array: Array(added.dropLast())).isEqual(to: system))
        #expect(NSDictionary(dictionary: try #require(added.last))
            .isEqual(to: ["Bundle ID": ours, "InputSourceKind": "Keyboard Input Method"]))
        #expect(InputSourceList.contains(added, bundleID: ours))
        #expect(!InputSourceList.contains(system, bundleID: ours))
    }

    @Test func addingTwiceWritesNothing() throws {
        let added = try #require(InputSourceList.adding(ours, to: system))
        #expect(InputSourceList.adding(ours, to: added) == nil)
    }

    @Test func noListIsLeftAlone() {
        // Creating the list with only our entry would drop the keyboard layout.
        #expect(InputSourceList.adding(ours, to: nil) == nil)
        #expect(InputSourceList.removing(ours, from: nil) == nil)
    }

    @Test func otherBuildsHaveTheirOwnEntries() throws {
        let beta = ours + "Beta"
        let withBeta = try #require(InputSourceList.adding(beta, to: system))
        #expect(!InputSourceList.contains(withBeta, bundleID: ours))
        let both = try #require(InputSourceList.adding(ours, to: withBeta))
        #expect(bundleIDs(both).suffix(2) == [beta, ours])
    }

    @Test func removingTakesOnlyOurEntries() throws {
        let beta = ours + "Beta"
        let list = system + [InputSourceList.entry(bundleID: ours), InputSourceList.entry(bundleID: beta),
                             InputSourceList.entry(bundleID: ours)]
        let removed = try #require(InputSourceList.removing(ours, from: list))
        #expect(bundleIDs(removed) == bundleIDs(system) + [beta])
        #expect(NSArray(array: Array(removed.prefix(system.count))).isEqual(to: system))
        #expect(InputSourceList.removing(ours, from: system) == nil)
    }

    /// Every entry of an input source, in each of the keys that name the user's input sources (enabled, selected, the
    /// recent ones, the one saved as current), goes at once; the other entries and keys stay as they are. The copy reads back
    /// as it was.
    @Test func everyEntryOfAnInputSourceGoesAtOnceAndACopyReadsBack() throws {
        let beta = ours + "Beta"
        let layout: [String: Any] = ["InputSourceKind": "Keyboard Layout", "KeyboardLayout ID": 0, "KeyboardLayout Name": "U.S."]
        let values: [String: Any] = [
            InputSourceList.key: system + [InputSourceList.entry(bundleID: ours), InputSourceList.entry(bundleID: beta)],
            "AppleSelectedInputSources": [InputSourceList.entry(bundleID: ours)],
            "AppleInputSourceHistory": [InputSourceList.entry(bundleID: ours), layout],
            "AppleSavedCurrentInputSource": InputSourceList.entry(bundleID: ours),
            "AppleCurrentKeyboardLayoutInputSourceID": "com.apple.keylayout.US",
        ]
        let (before, after) = InputSourceList.removingEntries(of: ours, from: values)
        #expect(Set(before.keys) == Set(InputSourceList.entryKeys))
        #expect(bundleIDs(try #require(after[InputSourceList.key] as? [[String: Any]])) == bundleIDs(system) + [beta])
        #expect((after["AppleSelectedInputSources"] as? [[String: Any]])?.isEmpty == true)
        #expect(NSArray(array: try #require(after["AppleInputSourceHistory"] as? [[String: Any]])).isEqual(to: [layout]))
        // The saved current one was its entry alone: the key goes.
        #expect(after["AppleSavedCurrentInputSource"] == nil && before["AppleSavedCurrentInputSource"] != nil)
        // Nothing of another input source, and no other key.
        #expect(InputSourceList.removingEntries(of: "com.example.none", from: values).before.isEmpty)
        #expect(InputSourceList.removingEntries(of: beta, from: values).before.keys.sorted() == [InputSourceList.key])
        #expect(InputSourceList.removingEntries(of: ours, from: [:]).before.isEmpty)

        let copy = InputSourceEntries(before)
        #expect(NSDictionary(dictionary: copy.values).isEqual(to: before) && !copy.isEmpty)
        let decoded = try JSONDecoder().decode(InputSourceEntries.self, from: JSONEncoder().encode(copy))
        #expect(decoded == copy && InputSourceEntries([:]).isEmpty)
    }
}
