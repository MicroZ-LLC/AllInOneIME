import AllInOneIMECore
import AppKit
import SwiftUI

extension SelfTest {
    /// Privacy → Learned… (Settings v2, 3.2) on a store of samples of its own (in memory: the user's is never read): the
    /// Privacy page's row says how many things were learned; the list has a row for each (the app's starting input, where
    /// autocomplete stopped, where typos couldn't be fixed, the rows picked, a model without a temperature), as VoiceOver
    /// finds them; a row's Forget forgets that one where it is kept, Forget All the rest, and the list then says "Nothing
    /// learned yet"; the search finds the row. The separate Forget buttons of before are gone from General, Advanced and
    /// AI. And the images, in both languages, light and dark (`settings-learned*.png`).
    static func testLearnedList(snapshotDirectory: URL) {
        section("Settings: Privacy → Learned…")
        let folder = snapshotDirectory.appendingPathComponent("learned-samples")
        let url = snapshotDirectory.appendingPathComponent("learned-config.json")
        let before = LearnedShared.store
        defer {
            LearnedShared.store = before
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: url)
        }
        var config = settings
        config.typeOut = true  // Advanced's typing out shows all its rows
        try? config.write(to: url)
        let store = LearnedSamples.store(in: folder)
        LearnedShared.store = store
        let model = SettingsModel(configURL: url, persists: false)
        model.refreshLearned()
        let kinds = model.learned.map(\.kind)
        check(kinds == [.startingInput(app: "com.apple.mail", input: .language(.english)), .autocompleteStopped(app: "com.apple.dt.xcode"),
                        .typosOff(app: "com.apple.Terminal"), .pickedRows(count: 42), .noTemperature(provider: .openai, model: "o3-mini")],
              "the list has a row for each thing learned, in order (\(model.learned.map(\.text)))")
        check(SettingsSpot.search(SettingsSpot.learned.title, trigger: "@", config: config).first == .learned
              && ["学到的内容", "forget", "忘掉", "typos", "temperature"].allSatisfy { SettingsSpot.search($0, trigger: "@", config: config).contains(.learned) }
              && SettingsSpot.learned.page == .privacy,
              "the search finds Privacy → Learned, by its name and by what it holds")

        // VoiceOver's view (`AXEnhancedUserInterface` on this process's own app, as testSettingsPages has it).
        func enhanced(_ on: Bool) {
            _ = NSApp.perform(Selector(("accessibilitySetValue:forAttribute:")), with: on as NSNumber, with: "AXEnhancedUserInterface")
        }
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        func nodes(_ node: NSObject) -> [NSObject] {
            let children = ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []) + ((ax(node, "accessibilityRows") as? [NSObject]) ?? [])
            return [node] + children.flatMap(nodes)
        }
        func texts(_ window: NSWindow) -> [String] {
            nodes(window).map { (ax($0, "accessibilityValue") as? String) ?? (ax($0, "accessibilityLabel") as? String) ?? "" }
        }
        func buttons(_ window: NSWindow, _ title: String) -> [NSObject] {
            nodes(window).filter {
                ax($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
                    && [ax($0, "accessibilityLabel"), ax($0, "accessibilityTitle")].contains { $0 as? String == title }
            }
        }
        func press(_ button: NSObject?) {
            _ = button?.perform(NSSelectorFromString("accessibilityPerformPress"))
            _ = pump(timeout: 0.6) { false }
        }
        func open(_ view: some View, height: CGFloat = 700) -> NSWindow {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.setContentSize(NSSize(width: 880, height: height))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            _ = pump(timeout: 0.8) { false }
            return window
        }
        func close(_ window: NSWindow) {
            window.close()
            _ = pump(timeout: 0.3) { false }
        }
        enhanced(true)
        defer { enhanced(false) }

        // Privacy: the row, with how many things; the old Forget buttons nowhere else.
        let privacy = open(SettingsView(model: model, page: .privacy))
        let onPrivacy = texts(privacy)
        check(onPrivacy.contains(SettingsSpot.learned.title) && onPrivacy.contains(LearnedRow.count(5))
              && !buttons(privacy, tr("学到的内容…", "Learned…")).isEmpty,
              "Privacy has the Learned row, its count and its Learned… button")
        close(privacy)
        let gone = [tr("忘掉选过的行（42）", "Forget Picked Rows (42)"), tr("忘掉改不回来的 App（1）", "Forget apps where typos couldn't be fixed (1)"),
                    tr("不发 temperature 的模型：1 个（它们不接受）", "Models that get no temperature: 1 (they refused it)")]
        let elsewhere = [SettingsPage.general, .advanced, .ai].flatMap { page -> [String] in
            let window = open(SettingsView(model: model, page: page), height: 900)
            defer { close(window) }
            return texts(window)
        }
        check(!gone.contains(where: elsewhere.contains) && !elsewhere.contains(tr("这些 App 里不再打错：Terminal", "No typos in: com.apple.Terminal")),
              "General, Advanced and AI have no Forget of their own any more")

        // The list: a row each, Forget on the first (Mail's starting input), then Forget All.
        let sheet = open(LearnedSheet(model: model) {}, height: 420)
        let listed = texts(sheet)
        check(model.learned.allSatisfy { listed.contains($0.text) } && buttons(sheet, tr("忘掉", "Forget")).count == 5,
              "the list shows each row with its Forget (\(model.learned.map(\.text)))")
        press(buttons(sheet, tr("忘掉", "Forget")).first)
        let mail = AppNames.name(for: "com.apple.mail")
        check(store.startingInput(in: "com.apple.mail") == nil && model.learned.count == 4 && !texts(sheet).contains { $0.contains(mail) },
              "Forget forgets that row's thing alone (\(model.learned.map(\.text)))")
        press(buttons(sheet, tr("全部忘掉", "Forget All")).first)
        check(model.learned.isEmpty && store.items(appName: { _ in nil }).isEmpty && !store.autocomplete.learning.stopped("com.apple.dt.xcode")
              && !store.typosOff(in: "com.apple.Terminal") && store.picks.isEmpty && store.temperature.models.isEmpty,
              "Forget All forgets the rest, where each is kept")
        check(texts(sheet).contains(LearnedSheet.nothing), "the list then says \(LearnedSheet.nothing)")
        close(sheet)

        // The images: the list over the Privacy page, with the samples again.
        let chosen = UIText.choice
        defer { UIText.choice = chosen }
        for (language, suffix) in [("zh", ""), ("en", "-en")] {
            UIText.choice = language
            LearnedShared.store = LearnedSamples.store(in: folder)
            let preview = SettingsModel(configURL: url, persists: false)
            for (appearance, dark) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
                let image = snapshotDirectory.appendingPathComponent("settings-learned\(suffix)\(dark).png")
                SettingsImage.render(preview, page: .privacy, learned: true, to: image, appearance: appearance) { seconds in
                    _ = pump(timeout: seconds) { false }
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: image.path))?[.size] as? Int ?? 0
                check(size > 10_000, "the Learned list renders in \(language == "zh" ? "Chinese" : "English")\(dark.isEmpty ? "" : ", dark") (\(image.lastPathComponent))")
            }
        }
    }
}
