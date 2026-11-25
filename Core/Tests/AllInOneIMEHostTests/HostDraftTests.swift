import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// 0.7.5's claim on the board's "[P2] command drafts, pasted clipboard content and live dictation sent to the host as
/// marked text", checked on every profile: what is being written (a command's draft, a long clipboard pasted into it,
/// dictation still being heard) is never put in the field, marked or not, while it is written. The session has no way
/// to mark text (`SessionOutput` has no such output: `InputSession+Preedit.swift`), so the check is that nothing at all
/// goes into the field until the draft is done (every insertion is recorded, `HostRun`'s field watched after every key),
/// that nothing is marked there, and that the draft is in the panel's input line instead. The Mac's controller marks
/// only a row being put in or a space, during a key in a Chromium app (`markRow`); the Mac's replayer checks its side
/// (HostScenarios/HostDraftReplayTests).
struct HostDraftTests {
    /// A run of `source` on `profile` with every change to the field recorded (`FakeHost.inserted`).
    static func run(_ source: String, on profile: HostProfile, before: (HostRun) -> Void = { _ in }) throws
        -> (run: HostRun, failures: [HostFailure], insertions: [FakeHost.Insertion]) {
        let scenario = try HostCaseParser.parse(source, fallbackName: "draft")
        return UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            let run = HostRun(scenario, profile: profile)
            let insertions = Locked<[FakeHost.Insertion]>(initialState: [])
            let watched = run.host.inserted
            run.host.inserted = { change in
                insertions.withLock { $0.append(change) }
                watched?(change)
            }
            run.strict = true
            before(run)
            let failures = run.run()
            return (run, failures, insertions.withLock { $0 })
        }
    }

    /// `text` typed a key at a time, the field and the panel checked after each: the field as it was, nothing marked.
    static func typedAndChecked(_ text: String, field: String) -> String {
        text.map { character -> String in
            let key = character == "\"" ? "\\\"" : String(character)
            return "TYPE \"\(key)\"\nEXPECT doc \"\(field)\"\nEXPECT marked none"
        }.joined(separator: "\n")
    }

    @Test(arguments: HostProfile.allCases)
    func aCommandDraftIsNeverInTheField(_ profile: HostProfile) throws {
        for language in ["english", "chinese"] {
            let (run, failures, insertions) = try Self.run("""
                LANG \(language)
                TEXT "Hi |"
                \(Self.typedAndChecked("@question what is the plan for today", field: "Hi |"))
                EXPECT preedit "question › what is the plan for today"
                EXPECT panel shown
                KEY escape
                EXPECT doc "Hi |"
                EXPECT marked none
                """, on: profile)
            #expect(failures.isEmpty, "\(language): \(failures)")
            #expect(insertions.isEmpty, "\(language): \(insertions)")
            #expect(run.host.document == "Hi ")
        }
    }

    /// ⌘V in a command's draft pastes the clipboard into the draft (`Composer.pastesIntoCommand`): 2000 characters, lines
    /// and Chinese among them, in the panel's input line, none of it in the field.
    @Test(arguments: HostProfile.allCases)
    func aLongPasteIntoADraftIsNeverInTheField(_ profile: HostProfile) throws {
        let line = "第一行 the first line of a long note, 0123456789.\n"
        let pasted = String(String(repeating: line, count: 60).prefix(2000))
        #expect(pasted.count == 2000)
        let (run, failures, insertions) = try Self.run("""
            LANG english
            TEXT "Hi |"
            TYPE "@improve "
            KEY cmd+v
            EXPECT doc "Hi |"
            EXPECT marked none
            EXPECT panel shown
            """, on: profile) { $0.host.clipboard = .text(pasted) }
        #expect(failures.isEmpty, "\(failures)")
        #expect(insertions.isEmpty, "\(insertions.map { $0.text.prefix(40) })")
        let input = run.host.panel?.input.map { $0.prompt + $0.text } ?? ""
        #expect(input.hasPrefix("improve › 第一行 the first line") && input.count > 1000, "the paste is the draft's: \(input.prefix(60))…")
        // Esc: the draft goes, and with it the paste; the field as it was.
        run.press(.key(.escape, modifiers: []))
        #expect(run.host.document == "Hi " && run.host.marked.isEmpty)
    }

    /// Dictation (`Features.voiceInput`, off for now in a release; on here as its tests have it): what is heard so far
    /// shows in the panel while the voice key is held; the field gets the transcript once, when it is done.
    @Test(arguments: HostProfile.allCases)
    func dictationInProgressIsNeverInTheField(_ profile: HostProfile) async throws {
        try await Features.$voiceInputInTests.withValue(true) {
            let (run, _, _) = try Self.run("LANG chinese\nTEXT \"Hi |\"\nWAIT 10ms", on: profile)
            let host = run.host
            var insertions: [FakeHost.Insertion] = []
            let watched = host.inserted
            host.inserted = { change in
                insertions.append(change)
                watched?(change)
            }
            host.session.services.voiceSupported = { true }
            host.session.services.isVoiceKeyHeld = { true }
            host.focus()  // the settings applied again: dictation on (`Composer.voiceEnabled`)
            host.modifiers(ModifierChange(key: .modifier(.option, .right), modifiers: [.option, .rightOption], timestamp: run.now))
            host.fireTimers()
            guard case let .startVoice(id, _)? = host.platformActions.last else {
                Issue.record("[\(profile.rawValue)] no dictation: \(host.platformActions)")
                return
            }
            for heard in ["今天", "今天下午", "今天下午三点开会"] {
                host.send(.voice(.text(heard, id: id)))
                #expect(host.document == "Hi " && host.marked.isEmpty && insertions.isEmpty, "[\(profile.rawValue)] \(heard): \(host.document)")
                let shown = (host.panel?.input.map { $0.prompt + $0.text } ?? "") + (host.panel.map { "\($0)" } ?? "")
                #expect(shown.contains(heard), "[\(profile.rawValue)] what is heard shows in the panel: \(shown.prefix(200))")
            }
            host.modifiers(ModifierChange(key: .modifier(.option, .right), modifiers: [], timestamp: run.now + 1))
            host.send(.voice(.finished("今天下午三点开会。", id: id)))
            #expect(host.document == "Hi 今天下午三点开会。" && host.marked.isEmpty, "[\(profile.rawValue)] \(host.document)")
            #expect(insertions.map(\.text) == ["今天下午三点开会。"], "the transcript once, when it is done: \(insertions)")
        }
    }
}
