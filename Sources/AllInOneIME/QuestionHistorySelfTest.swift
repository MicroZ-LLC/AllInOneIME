import AllInOneIMECore
import AppKit

extension SelfTest {
    /// `@question`'s recent questions: one asked (live) is kept, in the self-test's own file (`QuestionHistoryStore.url`,
    /// set by `run`); "@question " lists it, a digit shows its saved answer at once (nothing asked), R asks again, a
    /// question during secure input isn't kept, Clear empties the list, and with the setting off there's none.
    static func testRecentQuestions(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        print("— @question: recent questions (live Bedrock)")
        let settingsBefore = settings
        defer {
            controller.commitComposition(client)
            settings = settingsBefore
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
        }
        settings.rememberQuestions = true
        controller.applySettings()
        controller.composer.setInputMode(.chinese)
        QuestionHistoryStore.clear()
        func question() {
            _ = press(controller, client, "@", code: 0x13, flags: .shift)
            type("q", controller, client)
            _ = enter(controller, client)  // picks @question
        }

        question()
        check(controller.panelModel().rows.isEmpty, "none kept yet: no list under @question")
        type("yijiayidengyuji", controller, client)  // 一加一等于几: what is one plus one
        _ = enter(controller, client)
        guard finishConversion(controller, "@question to keep") else { return }
        let answer = controller.composer.choices.last?.text ?? ""
        _ = enter(controller, client)
        check(client.inserted.last == answer, "⏎ inserts the answer")
        let kept = QuestionHistoryStore.history.entries
        let permissions = (try? FileManager.default.attributesOfItem(atPath: QuestionHistoryStore.url.path))?[.posixPermissions] as? Int
        check(kept.count == 1 && kept.first?.question == "一加一等于几" && kept.first?.answer == answer && permissions == 0o600,
              "the question and its answer are kept, in a file only the user reads (\(kept.map(\.question)), \(permissions.map { String($0, radix: 8) } ?? "-"))")

        // "@question " lists it; 1 shows its answer at once: nothing is asked.
        question()
        let list = controller.panelModel()
        check(list.rows.map(\.text) == ["一加一等于几"] && list.rows.first?.label == "1" && list.footer.contains("数字"),
              "@question with nothing after it lists the recent questions (\(list.rows.map(\.text)) | \(list.footer))")
        snapshot("question-recent", in: snapshotDirectory)
        type("1", controller, client)
        let saved = controller.panelModel()
        check(controller.composer.showsSavedAnswer && controller.composer.phase == .choosing
              && controller.composer.choices.last?.text == answer && saved.footer.contains("R 重新问") && saved.detail?.hasPrefix("保存于") == true,
              "1 shows the saved answer at once, no request (\(saved.footer) | \(saved.detail ?? "-"))")
        snapshot("question-saved", in: snapshotDirectory)
        _ = escape(controller, client)
        check(client.marked == "question › " && controller.composer.questionMatches.count == 1, "Esc goes back to the list ('\(client.marked)')")
        // Typing filters it: a word that isn't in it lists nothing, and ⏎ would ask that.
        type("zaijian", controller, client)
        _ = space(controller, client)
        check(controller.panelModel().rows.isEmpty && client.marked.count > "question › ".count,
              "a question not asked before lists nothing ('\(client.marked)')")
        controller.commitComposition(client)
        client.inserted.removeAll()

        // R on the saved answer asks again, for a fresh answer that takes its place.
        question()
        type("1", controller, client)
        let before = QuestionHistoryStore.history.entries.first?.date
        _ = press(controller, client, "r", code: 0x0F)
        check(controller.composer.isLevelTwo && !controller.composer.showsSavedAnswer, "R asks the question again")
        if finishConversion(controller, "@question asked again") {
            let again = QuestionHistoryStore.history.entries
            check(again.count == 1 && again.first?.question == "一加一等于几" && again.first?.date != before,
                  "the fresh answer takes the old one's place (\(again.count))")
        }
        controller.commitComposition(client)

        // Secure input: nothing is asked, nothing kept.
        let secureInput = controller.secureInputActive
        controller.secureInputActive = { true }
        question()
        type("mimashishenme", controller, client)
        _ = enter(controller, client)
        _ = pump(timeout: 1) { false }
        check(QuestionHistoryStore.history.entries.count == 1, "a question during secure input isn't kept")
        controller.secureInputActive = secureInput
        controller.commitComposition(client)

        // Clear (Settings → General): the list is gone, and the file.
        QuestionHistoryStore.clear()
        question()
        check(controller.panelModel().rows.isEmpty && !FileManager.default.fileExists(atPath: QuestionHistoryStore.url.path),
              "cleared: no list, no file")
        controller.commitComposition(client)

        // With the setting off: no list even with questions kept.
        QuestionHistoryStore.record(QuestionHistory.Entry(question: "一加一等于几", answer: "二", date: Date()))
        settings.rememberQuestions = false
        controller.applySettings()
        question()
        check(controller.panelModel().rows.isEmpty && controller.composer.questionMatches.isEmpty, "with the setting off there's no list")
        controller.commitComposition(client)
        QuestionHistoryStore.clear()
    }
}
