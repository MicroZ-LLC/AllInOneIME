import AllInOneIMECore
import AppKit
import SwiftUI

/// `AllInOneIME --showcase OUT-DIR [dark] [zh]`: the menu bar panel as it looks on screen, for the release
/// notes and the wiki. The real panel with the self-test's sample data (English; `zh`: Chinese) drops down over a
/// colorful window, so its frosted glass has something to blur, and is captured with `screencapture`:
/// `panel.png` as it opens, `panel-swipe.png` with a task swiped open to its Remove button. An
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
                CandidatePanel.shared.hide()
                panel.show(below: anchor)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) {
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
    static func run(output: URL, chinese: Bool, dark: Bool) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UIText.choice = chinese ? .chinese : .english
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        model.profileShownAs = "default"  // not the user's own profile name
        for page in SettingsPage.allCases {
            SettingsImage.render(model, page: page, to: output.appendingPathComponent("settings-\(page.rawValue).png"),
                                 appearance: dark ? .darkAqua : .aqua) { RunLoop.main.run(until: Date().addingTimeInterval($0)) }
        }
        exit(0)
    }
}
