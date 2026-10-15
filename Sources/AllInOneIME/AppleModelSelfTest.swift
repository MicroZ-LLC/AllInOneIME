import AllInOneIMECore
import AppKit

extension SelfTest {
    /// Apple Intelligence on this Mac (`Provider.apple`), only where the model is available: @improve on English and on
    /// pinyin through the controller with the on-device model, Test Connection with it chosen, and its settings page
    /// rendered (`apple-settings*.png`). Elsewhere it says why it was skipped. Nothing is written to the config file.
    static func testAppleModel(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        let availability = AppleModel.system.availability
        print("— Apple Intelligence on this Mac (\(availability.rawValue))")
        check(Provider.offered.contains(.apple) == availability.isOffered,
              "the provider list has it on macOS 26 and later (\(Provider.offered.map(\.rawValue)))")
        let pickedBefore = UIText.choice
        UIText.choice = .english
        let refusedEnglish = UIText.describe(ProviderError.refused(.apple))
        UIText.choice = .chinese
        let refusedChinese = UIText.describe(ProviderError.refused(.apple))
        UIText.choice = pickedBefore
        check(refusedEnglish == "Apple Intelligence declined this request" && refusedChinese == "Apple Intelligence 拒绝了这个请求",
              "a refusal reads naturally (\(refusedEnglish) / \(refusedChinese))")
        guard availability == .available else {
            print("  skipped: the on-device model isn't available here")
            return
        }
        let (converterBefore, settingsBefore) = (controller.converter, settings)
        defer {
            (controller.converter, settings) = (converterBefore, settingsBefore)
            controller.applySettings()
        }
        var apple = settings
        apple.provider = .apple
        apple.setOrder([OutputLanguage.english, .chinese])
        apple.rewriteStyles = ["简洁"]
        settings = apple
        let fixed = apple
        controller.converter = Converter(loadConfig: { fixed })
        controller.applySettings()

        // English typed in English mode: three English versions and the concise rewrite, in English.
        tapShift(controller, client)
        let sentence = "i think we should moved the meeting to next week"
        check(improve(controller, client), "@improve drafted")
        type(sentence, controller, client)
        check(act(controller, client), "the action key sends it to the on-device model")
        if finishConversion(controller, "Apple Intelligence @improve (English)") {
            let choices = controller.composer.choices
            let versions = choices.filter { $0.kind == .version }
            check(versions.count == 3 && versions.allSatisfy { !$0.text.containsHan && $0.text.wordingKey != sentence.wordingKey },
                  "3 polished English versions in the line-tagged format")
            check(choices.contains { $0.kind == .rewrite("简洁") && !$0.text.containsHan }, "the concise rewrite, in English")
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)
        tapShift(controller, client)

        // Pinyin: a Chinese sentence is polished in Chinese.
        check(improve(controller, client), "@improve drafted (pinyin)")
        type("mingtiankaihuiwokenengyaochidao", controller, client)
        _ = enter(controller, client)
        if finishConversion(controller, "Apple Intelligence @improve (Chinese)") {
            let versions = controller.composer.choices.filter { $0.kind == .version }
            // A version that only re-punctuates the sentence isn't shown: the small model writes one now and then.
            check((2...3).contains(versions.count) && versions.allSatisfy(\.text.containsHan),
                  "Chinese versions (\(versions.count) shown)")
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)

        // The settings window with it chosen: Test Connection asks the on-device model; the page as the README shows it.
        defer { UIText.choice = pickedBefore }
        for chinese in [true, false] {
            UIText.choice = chinese ? .chinese : .english
            let preview = SettingsModel(configURL: Config.defaultURL, persists: false)
            preview.config.provider = .apple
            preview.config.setOrder([OutputLanguage.english])
            preview.config.uiLanguage = chinese ? .chinese : .english
            preview.runTest()
            _ = pump(timeout: 30) { preview.testStatus != .running }
            if case let .passed(text) = preview.testStatus {
                check(true, "Test Connection with Apple Intelligence: \(text.replacingOccurrences(of: "\n", with: " / "))")
            } else {
                check(false, "Test Connection with Apple Intelligence failed: \(preview.testStatus)")
            }
            SettingsImage.render(preview, page: .provider,
                                 to: snapshotDirectory.appendingPathComponent(chinese ? "apple-settings.png" : "apple-settings-en.png")) { seconds in
                _ = pump(timeout: seconds) { false }
            }
        }
    }
}
