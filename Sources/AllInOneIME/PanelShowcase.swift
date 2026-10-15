import AllInOneIMECore
import AppKit
import SwiftUI

/// `AllInOneIME --showcase OUT-DIR [dark] [zh]`: the menu bar panel as it looks on screen, for the release
/// notes and the wiki. The real panel with the self-test's sample data (English; `zh`: Chinese) drops down over a
/// colorful window, so its frosted glass has something to blur, and is captured with `screencapture`:
/// `panel.png` as it opens, `panel-swipe.png` with a task swiped open to its Remove button, and the candidate
/// panel under a line being typed: `candidates.png` in a column, `candidates-horizontal.png` in a row. An
/// offscreen render can't show the glass (nothing is behind it). Needs the screen unlocked; the windows
/// are up for about four seconds. Nothing real is read: Notes, Reminders and Claude Code are stand-ins.
@MainActor
enum PanelShowcase {
    static let backdrop = CGRect(x: 120, y: 160, width: 760, height: 450)

    static func run(output: URL, dark: Bool, chinese: Bool) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UIText.choice = chinese ? .chinese : .english
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let back = NSWindow(contentRect: backdrop, styleMask: [.borderless], backing: .buffered, defer: false)
        back.contentView = NSHostingView(rootView: Backdrop(chinese: chinese))
        back.level = .normal
        back.orderFrontRegardless()

        let stand = PanelStandIns()
        stand.sample(chinese: chinese)
        let panel = FloatingPanel(sources: stand.sources)
        panel.prepareWindow = { $0.appearance = appearance }
        // Under an icon near the backdrop's top right, as from the menu bar.
        let anchor = CGRect(x: backdrop.maxX - 120, y: backdrop.maxY - 40, width: 22, height: 24)
        panel.show(below: anchor)

        func capture(_ name: String) {
            let height = NSScreen.screens[0].frame.height  // screencapture counts from the top
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-R", "\(Int(backdrop.minX)),\(Int(height - backdrop.maxY)),\(Int(backdrop.width)),\(Int(backdrop.height))",
                              output.appendingPathComponent(name).path]
            try? task.run()
            task.waitUntilExit()
            print("  \(output.appendingPathComponent(name).path)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                capture("panel.png")
                // The candidate panel, as under a line being typed at the backdrop's left.
                panel.closeDropDown()
                let rows = (chinese ? ["哦", "噢", "喔", "欧", "偶"] : ["oh", "ok", "of", "on", "out"]).enumerated().map {
                    CandidateView.Row(label: "\($0.offset + 1)", text: $0.element, style: .candidate)
                }
                let line = NSRect(x: backdrop.minX + 60, y: backdrop.maxY - 150, width: 2, height: 20)
                CandidatePanel.shared.appearance = appearance
                CandidatePanel.shared.show(CandidateView.Model(rows: rows, highlighted: 0,
                                                               footer: chinese ? "空格 选词 · 开头打 @ 用命令" : "Space picks · @ for commands"),
                                           anchor: line)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            MainActor.assumeIsolated {
                capture("candidates.png")
                // The same in a row (`candidateLayout`), the second highlighted as → would.
                let rows = (chinese ? ["我们", "我门", "握们", "沃们", "卧"] : ["we", "well", "were", "went", "west"]).enumerated().map {
                    CandidateView.Row(label: "\($0.offset + 1)", text: $0.element, style: .candidate)
                }
                let line = NSRect(x: backdrop.minX + 60, y: backdrop.maxY - 150, width: 2, height: 20)
                CandidatePanel.shared.show(CandidateView.Model(rows: rows, highlighted: 1,
                                                               footer: chinese ? "空格 选词 · 开头打 @ 用命令" : "Space picks · @ for commands",
                                                               detail: chinese ? "第 1 页" : "page 1", horizontal: true),
                                           anchor: line)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            MainActor.assumeIsolated {
                capture("candidates-horizontal.png")
                CandidatePanel.shared.hide()
                panel.show(below: anchor)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
            MainActor.assumeIsolated {
                if case let .list(rows) = panel.tasks, let row = rows.first { panel.showSwiped(.task(row.id)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated {
                        capture("panel-swipe.png")
                        panel.closeDropDown()
                        exit(0)
                    }
                }
            }
        }
        app.run()
        exit(0)
    }

    /// A busy, colorful screen: the glass blurs it.
    private struct Backdrop: View {
        let chinese: Bool
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.98, green: 0.6, blue: 0.3), Color(red: 0.92, green: 0.3, blue: 0.45),
                                        Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.25, green: 0.55, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    Text(chinese ? "第四季度计划" : "Q4 Planning").font(.system(size: 44, weight: .heavy))
                    ForEach(chinese ? ["上线新手引导", "改版价格页", "招两位工程师", "用户访谈", "进入欧洲市场"]
                                    : ["Ship the onboarding flow", "Review the pricing page", "Hire two engineers",
                                       "Customer interviews", "Launch in Europe"], id: \.self) {
                        Text("• " + $0).font(.system(size: 24, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(40)
            }
            .frame(width: PanelShowcase.backdrop.width, height: PanelShowcase.backdrop.height)
        }
    }
}

/// `AllInOneIME --settings-image OUT-DIR [zh] [dark]`: every page of the settings window drawn offscreen,
/// `settings-<page>.png`, from the config file as it is (nothing is saved).
@MainActor
enum SettingsPageImages {
    static func run(output: URL, chinese: Bool, dark: Bool, extensions: String? = nil, update: String? = nil) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UIText.choice = chinese ? .chinese : .english
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        model.profileShownAs = "default"  // not the user's own profile name
        // Fuzzy pinyin shown on, with its pairs (the model saves nothing).
        if !model.config.inputLanguages.contains(.chinese) { model.config.setOrder(model.config.inputLanguages + [.chinese]) }
        if model.config.fuzzyPinyin.isEmpty { model.config.fuzzyPinyin = SettingsModel.fuzzyDefaults }
        // Public examples rather than the user's own folders, when given (`extensions=<folder>[,<found folder>…]`:
        // the first as added, any others as if Spotlight had found them).
        if let extensions {
            let paths = extensions.split(separator: ",").map { ExtensionStore.abbreviated((String($0) as NSString).expandingTildeInPath) }
            model.config.extensionFolders = Array(paths.prefix(1))
            model.config.findRaycastScripts = paths.count > 1
            model.config.hiddenExtensionFolders = []
            LiveExtensions.shownFound = Array(paths.dropFirst())
        }
        // The Updates card in a state of its own (nothing is checked or downloaded).
        if let update {
            let updates = UpdateController.shared
            updates.lastChecked = Date().addingTimeInterval(-2 * 3600)
            updates.updatesInPlace = true  // as the installed copy shows it (Update, not Download)
            switch update {
            case "available": updates.state = .available(.sample())
            case "downloading": updates.state = .downloading(.sample(), 0.42)
            case "failed": updates.state = .failed(UpdateText.describe(UpdateError.hashMismatch), .sample())
            case "updated":
                updates.state = .upToDate
                updates.lastResult = UpdateResult(from: "0.6.2", to: AppVersion.string, ok: true)
            default: updates.state = .upToDate
            }
        }
        for page in SettingsPage.allCases {
            SettingsImage.render(model, page: page, to: output.appendingPathComponent("settings-\(page.rawValue).png"),
                                 appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        // The Input page with each input language's tab picked.
        for language in model.config.inputLanguages {
            SettingsImage.render(model, page: .input, inputTab: language,
                                 to: output.appendingPathComponent("settings-input-\(language.rawValue).png"),
                                 appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        exit(0)
    }
}
