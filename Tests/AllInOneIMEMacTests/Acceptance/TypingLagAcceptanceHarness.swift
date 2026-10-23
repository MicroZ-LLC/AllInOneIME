import Foundation

/// Source for an isolated executable. Compiles against the production code, never the app's self-tests.
enum Issue23AcceptanceHarness {
    static let swift = #"""
import AllInOneIMECore
import AllInOneIMERime
import AppKit
import Foundation
import ObjectiveC

// Only dependencies unrelated to constructing the production menu are stand-ins. Menu actions
// are deliberately inert; the tests inspect their enabled states without opening other apps.
func tr(_ chinese: String, _ english: String) -> String { english }
enum SettingsPage: String { case writing, input }
struct AcceptanceMenuServices {
    func loadSettings() -> Config { var config = Config.default; config.uiLanguage = "en"; return config }
}
final class LanguagePackManager {
    static let shared = LanguagePackManager()
    func isUsable(_ language: Language) -> Bool { true }
}
final class UpdateController {
    struct Available { var version: String }
    static let shared = UpdateController()
    var available: Available? = nil
}
@objc final class AllInOneIMEInputController: NSObject {
    var services = AcceptanceMenuServices()
    var activeApp: String? = nil
    var appID: String? = nil
    func appMenuItem(config: Config?, app: String?) -> NSMenuItem? { nil }
    @objc func showPreferences(_ sender: Any?) {}
    @objc func setOutputLanguage(_ sender: Any?) {}
    @objc func setDefaultInput(_ sender: Any?) {}
    @objc func toggleStyle(_ sender: Any?) {}
    @objc func toggleImproveTranslates(_ sender: Any?) {}
    @objc func openRimeDirectory(_ sender: Any?) {}
    @objc func redeploy(_ sender: Any?) {}
    @objc func reportIssue(_ sender: Any?) {}
    @objc func checkForUpdates(_ sender: Any?) {}
}

@_silgen_name("issue23_watch_config") func watchConfig(_ path: UnsafePointer<CChar>)
@_silgen_name("issue23_config_reads") func configReads() -> Int32
@_silgen_name("issue23_reset_reads") func resetConfigReads()

enum WindowCalls {
    static weak var watched: NSWindow?
    static var frames = 0
    static var shadows = 0
    static var fronts = 0
    static var outs = 0
    static func reset() { frames = 0; shadows = 0; fronts = 0; outs = 0 }
    static func install() {
        for (original, replacement) in [
            (#selector(NSWindow.setFrame(_:display:)), #selector(NSWindow.issue23_setFrame(_:display:))),
            (#selector(NSWindow.invalidateShadow), #selector(NSWindow.issue23_invalidateShadow)),
            (#selector(NSWindow.orderFrontRegardless), #selector(NSWindow.issue23_orderFrontRegardless)),
            (#selector(NSWindow.orderOut(_:)), #selector(NSWindow.issue23_orderOut(_:)))
        ] {
            method_exchangeImplementations(class_getInstanceMethod(NSWindow.self, original)!,
                                           class_getInstanceMethod(NSWindow.self, replacement)!)
        }
    }
}
extension NSWindow {
    @objc func issue23_setFrame(_ rect: NSRect, display: Bool) {
        if self === WindowCalls.watched { WindowCalls.frames += 1 }
        issue23_setFrame(rect, display: display)
    }
    @objc func issue23_invalidateShadow() {
        if self === WindowCalls.watched { WindowCalls.shadows += 1 }
        issue23_invalidateShadow()
    }
    @objc func issue23_orderFrontRegardless() {
        if self === WindowCalls.watched { WindowCalls.fronts += 1 }
        issue23_orderFrontRegardless()
    }
    @objc func issue23_orderOut(_ sender: Any?) {
        if self === WindowCalls.watched { WindowCalls.outs += 1 }
        issue23_orderOut(sender)
    }
}

enum Acceptance {
    static var failures = 0
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: " + message) }
    }
    static func pump(_ seconds: TimeInterval) {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
    static func presented(_ panel: CandidatePanel) -> Bool { panel.isVisible && panel.alphaValue > 0 }
    static var anchor: NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.midX, y: screen.midY, width: 1, height: 20)
    }
    static var models: [(String, PanelModel)] {
        [("candidates", PanelModel(rows: [.init(label: "1", text: "你好", kind: .candidate),
                                          .init(label: "2", text: "拟好", kind: .candidate)], highlighted: 0)),
         ("notice", .notice("Saved")),
         ("translate chip", PanelModel(chip: .init(source: "ZH", target: "EN")))]
    }

    @MainActor static func windows() {
        WindowCalls.install()
        for (name, model) in models {
            let panel = CandidatePanel()
            let firstOwner = NSObject(), secondOwner = NSObject()
            panel.owner = firstOwner
            WindowCalls.watched = panel
            WindowCalls.reset()
            panel.show(model, anchor: anchor)
            expect(panel.animationBehavior == .none, "\(name): animations disabled")
            expect(panel.isVisible && presented(panel) && panel.alphaValue > 0,
                   "\(name): first presentation is visible")
            expect(!panel.ignoresMouseEvents, "\(name): shown panel accepts pointer input")
            expect(WindowCalls.fronts == 1, "\(name): first show orders one window in")
            // A nondefault alpha catches failure to restore the presentation after an invisible reuse.
            panel.alphaValue = 0.77
            let initialWindowNumber = panel.windowNumber
            let initialFronts = WindowCalls.fronts
            panel.hide()
            panel.hide()
            expect(!presented(panel) && panel.alphaValue == 0 && panel.ignoresMouseEvents,
                   "\(name): commit immediately removes stale pixels and mouse interception")
            expect(panel.isVisible && WindowCalls.outs == 0,
                   "\(name): commit keeps the ordered window available for reuse")
            pump(0.25)
            expect(panel.isVisible && WindowCalls.outs == 0,
                   "\(name): no orderOut before the 300ms lower bound")
            panel.owner = secondOwner
            panel.show(model, anchor: anchor)
            expect(panel.owner === secondOwner && presented(panel) && panel.alphaValue == 0.77 && !panel.ignoresMouseEvents,
                   "\(name): another owner can reopen with the original presentation")
            expect(panel.windowNumber == initialWindowNumber && WindowCalls.fronts == initialFronts,
                   "\(name): reopening during a burst does not reorder or replace the window")
            pump(0.27)
            expect(presented(panel) && WindowCalls.outs == 0,
                   "\(name): first owner's old hide deadline cannot dismiss the new presentation")
            // Several overlapping deferred hides: every canceled deadline passes while a word is up.
            for _ in 0..<5 {
                panel.hide()
                pump(0.075)
                panel.show(model, anchor: anchor)
            }
            pump(0.45)
            expect(presented(panel) && WindowCalls.outs == 0 && WindowCalls.fronts == initialFronts,
                   "\(name): sustained typing reuses one ordered window after all old deadlines")
            let hiddenAt = ProcessInfo.processInfo.systemUptime
            panel.hide()
            while panel.isVisible && ProcessInfo.processInfo.systemUptime - hiddenAt < 0.65 { pump(0.005) }
            let delay = ProcessInfo.processInfo.systemUptime - hiddenAt
            expect(!panel.isVisible && WindowCalls.outs == 1,
                   "\(name): idle window is eventually ordered out exactly once")
            // 75ms allowance is for dispatch scheduling on a busy CI host, not an extra hide interval.
            expect(delay >= 0.3 && delay <= 0.575, "\(name): deferred hide in 300–500ms (observed \(delay)s)")
            panel.show(model, anchor: anchor)
            expect(presented(panel) && panel.alphaValue == 0.77 && !panel.ignoresMouseEvents,
                   "\(name): reopening after idle restores visibility and hit testing")
            panel.hide()
            pump(0.6)
        }
    }

    @MainActor static func geometry() {
        WindowCalls.install()
        for (name, model) in models {
            let panel = CandidatePanel()
            WindowCalls.watched = panel
            panel.show(model, anchor: anchor)
            pump(0.05)
            WindowCalls.reset()
            for _ in 0..<50 { panel.show(model, anchor: anchor) }
            expect(WindowCalls.frames == 0 && WindowCalls.shadows == 0,
                   "\(name): unchanged frame causes no setFrame(display:) or shadow invalidation")
            if !model.rows.isEmpty {
                var next = model
                next.highlighted = 1
                panel.show(next, anchor: anchor)
                expect(WindowCalls.frames == 0 && WindowCalls.shadows == 0,
                       "changed candidate selection with identical geometry avoids both AppKit mutators")
                expect(panel.view.model.highlighted == 1, "skipping geometry still updates the candidate selection")
            }
            let before = panel.frame
            let movedAnchor = anchor.offsetBy(dx: 21, dy: 0)
            panel.show(model, anchor: movedAnchor)
            expect(panel.frame != before && WindowCalls.frames > 0 && WindowCalls.shadows > 0,
                   "\(name): a real movement reaches both mutators (observer positive control)")
            WindowCalls.reset()
            panel.show(model, anchor: movedAnchor)
            expect(WindowCalls.frames == 0 && WindowCalls.shadows == 0,
                   "\(name): repeated presentation at the new location is also stable")
            WindowCalls.reset()
            panel.hide()
            panel.show(model, anchor: movedAnchor)
            expect(WindowCalls.frames == 0 && WindowCalls.shadows == 0 && WindowCalls.fronts == 0 && WindowCalls.outs == 0,
                   "\(name): commit/reopen with the same geometry does no window geometry or ordering work")
            panel.hide()
            pump(0.6)
        }
    }

    static func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }
    static let writes = Set(["setOutputLanguage:", "setDefaultInput:", "toggleStyle:", "toggleImproveTranslates:"])
    static func writeItems(_ menu: NSMenu) -> [NSMenuItem] {
        allItems(menu).filter { $0.action.map(NSStringFromSelector).map(writes.contains) ?? false }
    }
    @MainActor static func menu(_ root: URL) throws {
        let fm = FileManager.default, url = root.appendingPathComponent("config.json")
        Config.selfTestURL = url
        url.path.withCString(watchConfig)
        func timestamp(_ revision: Int) throws {
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(revision))], ofItemAtPath: url.path)
        }
        let controller = AllInOneIMEInputController()
        // A direct production load proves that zero later opens means caching, not a broken observer.
        var first = Config.default
        first.modelId = "independent-acceptance-A"
        first.uiLanguage = "en"
        first.inputLanguages = [.english, .chinese]
        try first.write(to: url)
        try timestamp(1)
        resetConfigReads()
        _ = try Config.load(from: url)
        expect(configReads() > 0, "configuration-open observer detects a direct production Config.load")
        resetConfigReads()
        let initial = controller.makeMenu()
        expect(configReads() > 0, "first production menu reads the config")
        expect(allItems(initial).contains { $0.title.contains(first.modelId) }, "menu shows configured model")
        expect(!writeItems(initial).isEmpty && writeItems(initial).allSatisfy(\.isEnabled),
               "valid-config menu allows its setting actions")
        resetConfigReads()
        for _ in 0..<100 { _ = controller.makeMenu() }
        expect(configReads() == 0, "100 warm menu rebuilds perform no config file opens (actual \(configReads()))")

        try Data("{ malformed independent acceptance config".utf8).write(to: url, options: .atomic)
        try timestamp(2)
        resetConfigReads()
        let broken = controller.makeMenu()
        expect(allItems(broken).contains { $0.title == "The config file has an error" },
               "external malformed edit shows the existing config error UX")
        expect(!writeItems(broken).isEmpty && writeItems(broken).allSatisfy { !$0.isEnabled },
               "all config-writing menu actions disabled after parse failure")
        expect(allItems(broken).contains { $0.title == "Settings…" && $0.isEnabled },
               "settings remain reachable with a broken config")
        let brokenBytes = try Data(contentsOf: url)
        resetConfigReads()
        for _ in 0..<20 { _ = controller.makeMenu() }
        expect(configReads() == 0, "malformed results are cached too")
        expect(try Data(contentsOf: url) == brokenBytes, "menu construction preserves malformed file bytes")

        var second = first
        second.modelId = "independent-acceptance-B"
        try second.write(to: url)
        try timestamp(3)
        let repaired = controller.makeMenu()
        expect(allItems(repaired).contains { $0.title.contains(second.modelId) }, "repairing config refreshes menu model")
        expect(writeItems(repaired).allSatisfy(\.isEnabled), "repairing config re-enables setting actions")
        try fm.removeItem(at: url)
        let missing = controller.makeMenu()
        expect(!allItems(missing).contains { $0.title == "The config file has an error" },
               "a missing file remains a fresh-config state, not a malformed state")
        expect(!writeItems(missing).isEmpty && writeItems(missing).allSatisfy(\.isEnabled),
               "fresh users can use setting actions")
        expect(!fm.fileExists(atPath: url.path), "merely constructing the menu does not create a config")
    }

    struct Preserved {
        var url: URL
        var data: Data
        var date: Date?
        var inode: NSNumber?
        var permissions: NSNumber?
        init(_ url: URL) throws {
            self.url = url
            data = try Data(contentsOf: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            date = attributes[.modificationDate] as? Date
            inode = attributes[.systemFileNumber] as? NSNumber
            permissions = attributes[.posixPermissions] as? NSNumber
        }
        func verify() throws {
            let after = try Preserved(url)
            Acceptance.expect(after.data == data && after.date == date && after.inode == inode && after.permissions == permissions,
                              "preserves custom file contents, identity, timestamp and permissions: \(url.lastPathComponent)")
        }
    }
    static func lunar(_ root: URL, _ thirdParty: URL, existing: Bool) throws {
        let fm = FileManager.default
        let shared = thirdParty.appendingPathComponent("rime-data")
        let source = shared.appendingPathComponent("lua/lunar.db")
        let sourceBefore = try Preserved(source)
        let user = root.appendingPathComponent("user")
        let logs = root.appendingPathComponent("logs")
        let database = user.appendingPathComponent("lua/lunar.db")
        var preserved: [Preserved] = []
        if existing {
            try fm.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: database)
            // A valid, read-only custom DB must stay byte-for-byte intact, and must not be replaced
            // even by an identical bundled file. Identity + mtime catches such replacement.
            try fm.setAttributes([.posixPermissions: 0o400, .modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: database.path)
            let customPatch = user.appendingPathComponent("default.custom.yaml")
            let patch = try String(contentsOf: shared.appendingPathComponent("default.custom.yaml"), encoding: .utf8)
            try (patch + "\n# independent acceptance custom patch\n").write(to: customPatch, atomically: true, encoding: .utf8)
            let customLua = user.appendingPathComponent("lua/user-owned.lua")
            try "return { independently_owned = true }\n".write(to: customLua, atomically: true, encoding: .utf8)
            let customPhrases = user.appendingPathComponent("custom_phrase.txt")
            try "验收\tyanshou\t100\n".write(to: customPhrases, atomically: true, encoding: .utf8)
            preserved = try [database, customPatch, customLua, customPhrases].map(Preserved.init)
        } else {
            expect(!fm.fileExists(atPath: user.path), "fresh user's Rime directory does not exist before start")
        }
        let service = RimeService.shared
        try service.start(sharedDataDir: shared, userDataDir: user, logDir: logs)
        expect(service.waitUntilReady(timeout: 60), "real librime becomes ready in isolated user directory")
        expect(fm.fileExists(atPath: database.path), "lunar database becomes available in the new user directory")
        let installed = try? Data(contentsOf: database)
        expect(installed == sourceBefore.data, "installed lunar database has the bundled data")
        for query in ["nl", "N20240210", "nl"] {
            guard let session = service.makeSession() else { expect(false, "real Rime session is created"); continue }
            session.setAsciiMode(false)
            for scalar in query.unicodeScalars { _ = session.processKey(Int32(scalar.value), mask: 0) }
            let candidates = session.snapshot().candidates
            if query == "nl" {
                expect(candidates.contains { $0.text.contains("年") && $0.comment.contains("星期") },
                       "nl produces an actual lunar date; candidates: \(candidates.map(\.text))")
            } else {
                expect(candidates.contains { $0.text == "甲辰龙年正月初一" },
                       "known Gregorian date 2024-02-10 yields lunar New Year's Day; candidates: \(candidates.map(\.text))")
            }
            expect(!candidates.contains { $0.text == "错误" && $0.comment.contains("农历") },
                   "lunar translator reports no missing-database lookup error")
        }
        for file in preserved { try file.verify() }
        try sourceBefore.verify()
        let logFiles = (try? fm.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)) ?? []
        let logText = logFiles.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        expect(!logText.contains("lunar.db"), "librime emits no lunar.db open error across multiple sessions")
    }
}

@main struct Issue23IndependentMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count == 4 else { print("expected scenario, temporary root, third-party root"); exit(2) }
        let scenario = args[1], root = URL(fileURLWithPath: args[2]), thirdParty = URL(fileURLWithPath: args[3])
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            switch scenario {
            case "windows": Acceptance.windows()
            case "geometry": Acceptance.geometry()
            case "menu": try Acceptance.menu(root)
            case "lunar-fresh": try Acceptance.lunar(root, thirdParty, existing: false)
            case "lunar-existing": try Acceptance.lunar(root, thirdParty, existing: true)
            default: print("unknown scenario"); exit(2)
            }
        } catch { Acceptance.expect(false, "unexpected error: \(error)") }
        print("\(Acceptance.failures == 0 ? "ACCEPTANCE PASS" : "ACCEPTANCE FAIL") \(scenario): \(Acceptance.checks) checks, \(Acceptance.failures) failures")
        exit(Acceptance.failures == 0 ? 0 : 1)
    }
}
"""#

    // Observe real Foundation config opens, rather than assuming a source-level cache means no I/O.
    // Both regular and cancellation-safe Darwin entry points are covered. The direct Config.load
    // positive control makes an unsupported observer fail visibly instead of silently passing.
    static let readObserver = #"""
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

static char watched[PATH_MAX];
static char canonical[PATH_MAX];
static int32_t reads;
void issue23_watch_config(const char *path) {
    strlcpy(watched, path, sizeof(watched));
    canonical[0] = 0;
    realpath(path, canonical);
    reads = 0;
}
int32_t issue23_config_reads(void) { return reads; }
void issue23_reset_reads(void) { reads = 0; }
static void note(const char *path) {
    if (path && watched[0] && (!strcmp(path, watched) || (canonical[0] && !strcmp(path, canonical)))) reads++;
}
static int observed_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); }
    note(path);
    return open(path, flags, mode);
}
static int observed_openat(int fd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); }
    note(path);
    return openat(fd, path, flags, mode);
}
extern int original_open_nocancel(const char *, int, ...) __asm("_open$NOCANCEL");
static int observed_open_nocancel(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); }
    note(path);
    return original_open_nocancel(path, flags, mode);
}
extern int original_openat_nocancel(int, const char *, int, ...) __asm("_openat$NOCANCEL");
static int observed_openat_nocancel(int fd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); }
    note(path);
    return original_openat_nocancel(fd, path, flags, mode);
}
static FILE *observed_fopen(const char *path, const char *mode) {
    note(path);
    return fopen(path, mode);
}
#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *newFunction; const void *oldFunction; } \
    interpose_##replacement __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&original };
INTERPOSE(observed_open, open)
INTERPOSE(observed_openat, openat)
INTERPOSE(observed_open_nocancel, original_open_nocancel)
INTERPOSE(observed_openat_nocancel, original_openat_nocancel)
INTERPOSE(observed_fopen, fopen)
"""#
}
