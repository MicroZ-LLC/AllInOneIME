import Foundation
import Testing
@testable import AllInOneIMECore

/// The user guide the app ships (Resources/user-guide.md, which the Makefile copies into the app and @question reads for
/// a question about AllInOneIME: `UserGuide` in the core): short sections in both languages, and the right one first for
/// the questions people ask.
struct UserGuideShippedTests {
    static let shippedURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/user-guide.md")

    static func shipped() throws -> UserGuide { UserGuide(text: try String(contentsOf: shippedURL, encoding: .utf8)) }

    func headings(_ excerpts: String?) -> [String] {
        (excerpts ?? "").split(separator: "\n").filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
    }

    @Test(arguments: [
        ("怎么打开双拼", "Shuangpin"), ("how do I turn on Shuangpin", "Shuangpin"),
        ("怎么改魔法键", "Magic key"), ("how to change the action key", "Magic key"),
        ("AllInOneIME 怎么设置自动补全", "Autocomplete"), ("how do I turn off autocomplete", "Autocomplete"),
        ("⌃V 怎么用", "Clipboard history"), ("怎么关掉剪贴板历史", "Clipboard history"),
        ("how do I use @translate", "Commands"), ("@question 的 ⇧⏎ 是做什么的", "@question"),
        ("AllInOneIME doesn't show up in input sources", "Setup"), ("输入法怎么切换繁体", "Chinese"),
        ("how do I set up the input method with an API key", "AI provider"), ("AllInOneIME 怎么更新", "Updates"),
        ("how do I add English words", "English words"), ("AllInOneIME 会把我打的字发出去吗", "Privacy"),
        ("边打边译怎么关", "Translate as You Type"), ("the accessibility permission for AllInOneIME", "Accessibility"),
        ("怎么用自己的命令 AllInOneIME", "Your own commands"),
    ])
    func theShippedGuideAnswersWithTheRightSectionFirst(question: String, first: String) throws {
        let excerpts = try Self.shipped().excerpts(for: question)
        #expect(headings(excerpts).first?.hasPrefix(first) == true, "\(question): \(headings(excerpts))")
        #expect((2...3).contains(headings(excerpts).count) && (excerpts?.count ?? 0) <= UserGuide.budget)
    }

    @Test func everySectionOfTheShippedGuideIsShortAndInBothLanguages() throws {
        let guide = try Self.shipped()
        #expect(guide.sections.count >= 20)
        for section in guide.sections {
            // Three of them fit in what is sent.
            #expect(section.text.count <= UserGuide.budget / 3, "\(section.heading): \(section.text.count)")
            #expect(section.heading.contains(" / "), "\(section.heading)")
            #expect(section.body.contains(where: UserGuide.isCJK) && section.body.contains { $0.isASCII && $0.isLetter },
                    "\(section.heading)")
        }
    }

    @Test(arguments: ["what is the capital of France", "帮我解释这句话", "帮我续写这个故事", "这个英文词什么意思"])
    func ordinaryQuestionsGetNothing(question: String) throws {
        #expect(try Self.shipped().excerpts(for: question) == nil)
    }
}
