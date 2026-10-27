import AllInOneIMECore
import AppKit

extension SelfTest {
    /// Issue #23: what the reused candidate window tells its callers (`shows`) and keeps (an invisible panel stays
    /// invisible), the cached config following another file and a broken one, and rapid commits through the controller
    /// with real Rime. No AI requests, posted keys or changes to the user's config. (The window's reuse, idle cleanup and
    /// geometry, and the input menu's cache: TypingLagIndependentAcceptanceTests.)
    static func testTypingLag(_ controller: AllInOneIMEInputController, _ client: FakeTextClient) {
        section("typing lag: candidate window reuse")
        let panel = CandidatePanel()
        defer { panel.orderOut(nil) }
        let model = PanelModel(rows: [PanelModel.Row(label: "1", text: "你好", kind: .candidate)], highlighted: 0)
        let anchor = client.caretRect
        panel.show(model, anchor: anchor)
        check(panel.shows(model, anchor: anchor), "the same model at the same caret needs no show again")
        panel.hide()
        check(!panel.shows(model, anchor: anchor), "a hidden window is not mistaken for an already shown chip")
        panel.show(model, anchor: anchor)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.hide()
        panel.show(model, anchor: anchor)
        check(panel.isShowing && panel.alphaValue == 0 && panel.ignoresMouseEvents,
              "offscreen self-tests keep their panel invisible and click-through across reuse")

        section("typing lag: cached config")
        let savedURL = Config.selfTestURL
        let directory = Config.defaultURL.deletingLastPathComponent().appendingPathComponent("typing-lag-config")
        defer {
            Config.selfTestURL = savedURL
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let first = directory.appendingPathComponent("first.json")
            let second = directory.appendingPathComponent("second.json")
            var config = Config.default
            config.modelId = "typing-lag-first"
            try config.write(to: first)
            config.modelId = "typing-lag-second"
            try config.write(to: second)
            let date = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: first.path)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: second.path)
            Config.selfTestURL = first
            _ = LiveConfig.current
            Config.selfTestURL = second
            check(LiveConfig.currentIfValid?.modelId == config.modelId, "cache follows a different file even with the same modification date")
            try Data("{broken json".utf8).write(to: second)
            check(LiveConfig.currentIfValid == nil && LiveConfig.current == .default, "broken config stays an error for the menu, defaults for typing")
        } catch {
            check(false, "config cache: \(error)")
        }
        Config.selfTestURL = savedURL

        section("typing lag: rapid pinyin commits", needs: .composing)
        let savedSettings = settings
        let load = controller.services.loadSettings
        let savedClient = (document: client.document, inserted: client.inserted)
        defer {
            _ = escape(controller, client)
            client.document = savedClient.document
            client.inserted = savedClient.inserted
            settings = savedSettings
            controller.services.loadSettings = load
            controller.applySettings()
        }
        controller.services.loadSettings = { SelfTest.settings }
        controller.applySettings()
        controller.ensureEngine()
        let before = client.inserted.count
        var commits: [Double] = []
        for _ in 0..<60 {
            let start = Date()
            type("nihao", controller, client)
            _ = space(controller, client)
            commits.append(Date().timeIntervalSince(start) * 1000)
        }
        check(client.inserted.count == before + 60 && client.inserted.suffix(60).allSatisfy { $0 == "你好" },
              "60 rapid words commit exactly once each with no lost or duplicated keys")
        check(!CandidatePanel.shared.isShowing && !controller.composer.isComposing, "the last commit leaves no stale candidates or marked text")
        let words = commits.sorted()
        print(String(format: "  60 real-Rime words (5 keys + Space): median %.2f ms, p95 %.2f ms, max %.2f ms",
                     words[30], words[57], words[59]))
    }
}
