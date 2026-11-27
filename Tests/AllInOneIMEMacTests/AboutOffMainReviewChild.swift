// The ways of AboutOffMainReviewTests in the child process of Review076SecondPassChild (compiled into it after the third
// pass's, and asked by that suite's dispatch for a way neither pass knows): what the review of the look at the input
// source off the main thread found in the input method's own code. The input source is looked at through seams
// (`InputSourceStatus.check`), never Text Input Sources; the child's app is never made active (`isAppActive` says).

enum AboutOffMainReviewChild {
    static let ways = #"""

    extension P2 {
        /// The input source's looks: each answers the next of `answers` (the last one again after that) at once.
        final class SourceLooks: @unchecked Sendable {
            private let answers: [Bool]
            private let started = Locked(initialState: 0)

            init(_ answers: [Bool]) { self.answers = answers }

            var count: Int { started.withLock { $0 } }

            func check() -> InputSourceCheck {
                InputSourceCheck(id: "com.example.allinoneime.about", state: {
                    let look = self.started.withLock { count -> Int in
                        count += 1
                        return count
                    }
                    return InputSourceState(registered: true, enabled: self.answers[min(look - 1, self.answers.count - 1)])
                }, register: {})
            }
        }

        /// The installed input method's status, looking through `looks`; found enabled, nothing of the move's record is done.
        static func sourceStatus(_ looks: SourceLooks) -> InputSourceStatus {
            let status = InputSourceStatus.shared
            status.isInstalled = true
            status.check = looks.check()
            status.enabled = {}
            return status
        }

        // MARK: Settings opened again before what the launch shows first is decided

        /// The AllInOneIME Settings app opened the input method again (its reopen) at launch, before the first look at the
        /// input source answered; then the launch decides what it shows first: right after the move (`moved`) with the
        /// source not added, the step on About; else nothing. Which pages were asked for, and whether the window was up
        /// before the decision.
        static func reopenBeforeFirstShown(moved: Bool) {
            _ = NSApplication.shared
            SettingsModel.looksUpKeys = false
            var config = Config.default
            config.uiLanguage = "en"
            write(config, to: home.appendingPathComponent("config.json"))
            let status = sourceStatus(SourceLooks([false]))
            var pages: [String] = []
            NotificationCenter.default.addObserver(forName: .allInOneIMEShowSettingsPage, object: nil, queue: nil) { note in
                pages.append(note.userInfo?["page"] as? String ?? "?")
            }
            let updates = UpdateController.shared
            say("undecided", updates.firstShown == nil)
            _ = IMEAppDelegate.shared.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            pump(0.3)
            say("shownAtOnce", SettingsWindow.shared.isVisible)
            if moved {
                updates.decideFirstShown(after: UpdateResult(from: "0.7.1", to: SystemIdentity.since, ok: true))
                status.refresh(appActive: false)  // the launch's first look (`InputSourceStatus.start`)
                say("decided", pump(5) { updates.firstShown != nil })
            } else {
                updates.decideFirstShown(after: nil)
                say("decided", updates.firstShown != nil)
            }
            say("shown", pump(5) { SettingsWindow.shared.isVisible })
            pump(0.5)
            say("first", updates.firstShown.map { "\($0)" } ?? "none")
            say("pages", pages.joined(separator: " "))
        }

        /// Opened again once the launch decided it shows the step: shown at once, as any later reopen.
        static func reopenOnceDecided() {
            _ = NSApplication.shared
            SettingsModel.looksUpKeys = false
            var config = Config.default
            config.uiLanguage = "en"
            write(config, to: home.appendingPathComponent("config.json"))
            UpdateController.shared.firstShown = .inputSourceStep
            _ = IMEAppDelegate.shared.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
            say("shownAtOnce", SettingsWindow.shared.isVisible)
        }

        // MARK: The source found added by a look the app's becoming active asked for

        /// Not added at first; then added, and found by the look asked for when the app became active, which answers with
        /// the app `active` (the user still there) or not (gone to another app meanwhile). How often `whenAdded` ran.
        static func addedWhenBack(active: Bool) {
            _ = NSApplication.shared
            let looks = SourceLooks([false, true])
            let status = sourceStatus(looks)
            status.isAppActive = { active }
            var told = 0
            status.whenAdded = { told += 1 }
            status.refresh(appActive: false)
            say("notAdded", pump(5) { status.needsAdding })
            status.refresh(appActive: true)
            say("added", pump(5) { !status.needsAdding })
            pump(0.2)
            say("told", told)
            say("looks", looks.count)
        }

        /// This suite's way `way`; false: none of that name.
        static func aboutReview(_ way: String) -> Bool {
            switch way {
            case "reopen-undecided-step": reopenBeforeFirstShown(moved: true)
            case "reopen-undecided-nothing": reopenBeforeFirstShown(moved: false)
            case "reopen-decided": reopenOnceDecided()
            case "added-while-away": addedWhenBack(active: false)
            case "added-while-back": addedWhenBack(active: true)
            default: return false
            }
            return true
        }
    }
    """#
}
