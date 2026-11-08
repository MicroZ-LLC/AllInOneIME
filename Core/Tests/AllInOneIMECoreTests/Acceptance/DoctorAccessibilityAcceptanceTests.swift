import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for Troubleshoot's Accessibility finding (0.6.9: when Accessibility isn't allowed, the finding lists
// what doesn't work without it), written from the brief by an independent reviewer; the implementer may not edit them.
// The fixtures are DoctorAcceptanceTests.swift's (`Doc.healthy`).
//
//   ax_listsWhatDoesntWorkWithoutIt      English: the list a user reads covers each thing that needs Accessibility
//   ax_listsItInChineseToo               the same list in Chinese
//   ax_keepsItsFixAndTheToggleHint       not yet asked counts as not allowed; the fix opens Privacy → Accessibility; the
//                                        "turn it off and on again" hint, in both languages
//   ax_allowedListsNothing               allowed: fine, no list
//   ax_theModelReadsItOnOneLine          `Doctor.report` (what a question sends): each finding on one line, the list on it

enum DAX {
    /// What doesn't work without Accessibility, each as words a line of the list must have (any one of a group, every
    /// group): English and Chinese.
    static let english: [(String, [[String]])] = [
        ("keys a list takes reaching some apps", [["key"], ["list", "↓"], ["app"]]),
        ("multi-line text into terminals", [["terminal"], ["line"]]),
        ("clipboard-history images", [["clipboard history"], ["image"]]),
        ("the selection in Chromium apps", [["select"], ["Chrome", "Chromium", "Slack", "VS Code"]]),
        ("@agent and @reply without the Chrome page", [["@agent"], ["@reply"], ["page"]]),
        ("the list away from the caret", [["list", "panel"], ["caret"]]),
        ("autocomplete past the field's edge", [["autocomplete"], ["edge"]]),
        ("password fields", [["password"]]),
    ]
    static let chinese: [(String, [[String]])] = [
        ("keys a list takes reaching some apps", [["键"], ["列表", "↓"], ["App", "应用"]]),
        ("multi-line text into terminals", [["终端"], ["行"]]),
        ("clipboard-history images", [["剪贴板"], ["图片"]]),
        ("the selection in Chromium apps", [["选中", "选择", "所选"], ["Chrome", "Chromium", "Slack", "VS Code"]]),
        ("@agent and @reply without the Chrome page", [["@agent"], ["@reply"], ["网页", "页面"]]),
        ("the list away from the caret", [["列表", "候选"], ["光标"]]),
        ("autocomplete past the field's edge", [["续写", "自动补全"], ["输入框", "边"]]),
        ("password fields", [["密码"]]),
    ]

    static func finding(_ facts: Doctor.Facts, chinese: Bool) throws -> Doctor.Finding {
        let found = Doc.findings(facts, .permissions, chinese: chinese).filter { $0.fix == .openPrivacy(.accessibility) }
        try #require(found.count == 1, "one Accessibility finding: \(found)")
        return found[0]
    }

    static var denied: Doctor.Facts {
        var facts = Doc.healthy
        facts.accessibility = .denied
        return facts
    }

    /// The lines of `detail` that say what doesn't work, and which item none of them says.
    static func missing(_ items: [(String, [[String]])], in detail: String) -> [String] {
        let lines = detail.split(whereSeparator: \.isNewline).map(String.init)
        return items.filter { _, groups in
            !lines.contains { line in groups.allSatisfy { group in group.contains { line.localizedCaseInsensitiveContains($0) } } }
        }.map(\.0)
    }
}

struct DoctorAccessibilityAcceptanceTests {
    @Test func ax_listsWhatDoesntWorkWithoutIt() throws {
        let finding = try DAX.finding(DAX.denied, chinese: false)
        #expect(finding.status != .ok)
        let detail = try #require(finding.detail, "no list")
        #expect(DAX.missing(DAX.english, in: detail).isEmpty, "not listed: \(DAX.missing(DAX.english, in: detail))\n\(detail)")
        // The list is a list: a line each, more than a sentence.
        #expect(detail.split(whereSeparator: \.isNewline).count >= DAX.english.count, "\(detail)")
    }

    @Test func ax_listsItInChineseToo() throws {
        let finding = try DAX.finding(DAX.denied, chinese: true)
        let detail = try #require(finding.detail, "no list")
        #expect(DAX.missing(DAX.chinese, in: detail).isEmpty, "not listed: \(DAX.missing(DAX.chinese, in: detail))\n\(detail)")
        #expect(detail.split(whereSeparator: \.isNewline).count >= DAX.chinese.count, "\(detail)")
        // Chinese, not English left in (beyond names: Chrome, @agent …).
        #expect(!detail.contains("terminal") && !detail.contains("clipboard history") && !detail.contains("password"), "\(detail)")
    }

    @Test func ax_keepsItsFixAndTheToggleHint() throws {
        var notAsked = Doc.healthy
        notAsked.accessibility = .notDetermined
        for facts in [DAX.denied, notAsked] {
            let en = try DAX.finding(facts, chinese: false), zh = try DAX.finding(facts, chinese: true)
            #expect(en.fix == .openPrivacy(.accessibility) && zh.fix == .openPrivacy(.accessibility))
            let enText = en.text(chinese: false), zhText = zh.text(chinese: true)
            #expect(enText.contains("Accessibility"), "\(enText)")
            #expect(enText.localizedCaseInsensitiveContains("off and on again"), "the hint: \(enText)")
            #expect(zhText.contains("辅助功能") && zhText.contains("关掉") && zhText.contains("打开"), "the hint: \(zhText)")
            #expect(DAX.missing(DAX.english, in: en.detail ?? "").isEmpty && DAX.missing(DAX.chinese, in: zh.detail ?? "").isEmpty,
                    "not asked yet lists it too")
        }
    }

    @Test func ax_allowedListsNothing() {
        let allowed = Doc.findings(Doc.healthy, .permissions).filter { $0.title.contains("Accessibility") }
        #expect(allowed.count == 1 && allowed.allSatisfy { $0.status == .ok && $0.fix == nil }, "\(allowed)")
        let text = allowed.map { $0.text(chinese: false) }.joined()
        #expect(!text.localizedCaseInsensitiveContains("terminal") && !text.localizedCaseInsensitiveContains("password"), "\(text)")
    }

    @Test func ax_theModelReadsItOnOneLine() throws {
        let findings = Doctor.findings(Doc.broken, chinese: false)
        let report = Doctor.report(findings)
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == findings.count, "a line per finding: \(lines.count) for \(findings.count)\n\(report)")
        #expect(lines.allSatisfy { $0.hasPrefix("- ") }, "\(report)")
        let index = try #require(findings.firstIndex { $0.fix == .openPrivacy(.accessibility) })
        try #require(lines.indices.contains(index), "\(report)")
        let line = lines[index]
        #expect(line.contains("Accessibility") && line.contains("[fix F\(index + 1)]"), "\(line)")
        #expect(DAX.english.allSatisfy { _, groups in groups.allSatisfy { $0.contains { line.localizedCaseInsensitiveContains($0) } } },
                "the whole list on its line: \(line)")
        #expect(line.localizedCaseInsensitiveContains("off and on again"), "\(line)")
    }
}
