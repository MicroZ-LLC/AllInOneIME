import Foundation
import Testing
@testable import AllInOneIMECore

struct PageContextTests {
    /// A text piece at row `y`.
    static func text(_ words: String, y: CGFloat, height: CGFloat = 16) -> PageNode {
        PageNode(role: "AXStaticText", value: words, frame: CGRect(x: 20, y: y, width: 200, height: height))
    }

    static func field(_ label: String, y: CGFloat, value: String? = nil, focused: Bool = false, invalid: Bool = false,
                      password: Bool = false, id: String? = nil) -> PageNode {
        PageNode(role: "AXTextField", subrole: password ? "AXSecureTextField" : nil, label: label, value: password ? nil : value,
                 domID: id, invalid: invalid, focused: focused, frame: CGRect(x: 20, y: y, width: 200, height: 24))
    }

    /// A sign-in page: a search box up top, the form, a feedback box, and a footer scrolled out of view.
    static func signIn(focusUser: Bool = true) -> PageNode {
        let form = PageNode(role: "AXGroup", domID: "login", children: [
            Self.text("Username", y: 200),
            field("Username", y: 220, value: "bob", focused: focusUser, invalid: true, id: "user"),
            Self.text("Username must be an email address", y: 250),
            Self.text("Password", y: 280),
            field("Password", y: 300, password: true),
            PageNode(role: "AXButton", label: "Sign in", frame: CGRect(x: 20, y: 340, width: 80, height: 24)),
        ])
        return PageNode(role: "AXWebArea", children: [
            field("Search", y: 120),
            PageNode(role: "AXHeading", children: [Self.text("Sign in", y: 160)]),
            form,
            field("Comments", y: 420),
            Self.text("Footer far below", y: 956, height: 0),  // pinned to the window's edge: off screen
        ])
    }

    static let window = CGRect(x: 0, y: 34, width: 1470, height: 922)

    @Test func theFieldItsFormAndWhatIsVisible() {
        let context = PageContext.make(page: Self.signIn(), url: "https://example.com/login", title: "Sign in",
                                       selection: nil, viewport: Self.window)
        #expect(context.field == "[field: Username] bob (invalid)\nid: user")
        #expect(context.surrounding == """
            Username
            ★ [field: Username] bob (invalid)   ← you are here
            Username must be an email address
            Password
            [password: Password] <not read>
            [button: Sign in]
            """)
        // Other fields on the page aren't its form; the footer off screen isn't visible.
        #expect(context.surrounding?.contains("Search") == false && context.surrounding?.contains("Comments") == false)
        #expect(context.visible?.contains("[field: Search]") == true && context.visible?.contains("[field: Comments]") == true)
        #expect(context.visible?.contains("Footer") == false && context.underPointer == nil)
    }

    @Test func aPasswordIsNeverRead() {
        var page = Self.signIn(focusUser: false)
        page.children[2].children[4].focused = true  // typing in the password field
        page.children[2].children[4].value = "hunter2"  // even if a reader got it
        let context = PageContext.make(page: page, url: "u", title: "t", selection: nil, viewport: nil)
        #expect(context.field == nil)
        #expect(!context.prompt(request: "x").contains("hunter2"))
    }

    @Test func withTheFocusOutsideThePageTheSectionUnderThePointer() {
        let long = String(repeating: "The pipeline is blocked on the Beta stage by a failed approval. ", count: 4)
        let stage = PageNode(role: "AXGroup", children: [Self.text("Beta", y: 300), Self.text(long, y: 320), PageNode(role: "AXButton", label: "Retry", pointer: true)])
        let page = PageNode(role: "AXWebArea", children: [Self.text("Pipelines", y: 100), stage, Self.text("Prod", y: 600)])
        let context = PageContext.make(page: page, url: "https://pipelines.example/p/1", title: "p", selection: nil, viewport: Self.window)
        #expect(context.field == nil && context.surrounding == nil)
        #expect(context.underPointer?.hasPrefix("Beta\nThe pipeline is blocked") == true && context.underPointer?.contains("Prod") == false)
        #expect(context.prompt(request: "为什么 block").contains("with the mouse pointer over <under_pointer>"))
    }

    @Test func thePromptIsTheRequestThenTheLayers() {
        let context = PageContext.make(page: Self.signIn(), url: "https://example.com/login?a=1&b=\"2\"", title: "Sign in",
                                       selection: "  the error  ", viewport: Self.window)
        let prompt = context.prompt(request: "为什么不行")
        #expect(prompt.hasPrefix("为什么不行\n\n---\nContext from the Google Chrome page"))
        #expect(prompt.contains(#"<page url="https://example.com/login?a=1&amp;b=&quot;2&quot;" title="Sign in"/>"#))
        let order = ["<you_are_here>", "<surrounding>", "<selection>\nthe error\n</selection>", "<visible>", "<note>"]
            .map { prompt.range(of: $0)?.lowerBound }
        #expect(order.allSatisfy { $0 != nil } && order.map { $0! } == order.map { $0! }.sorted())
        #expect(!prompt.contains("<under_pointer>"))
    }

    @Test func layersAreClipped() {
        let huge = String(repeating: "word ", count: 3000)
        let page = PageNode(role: "AXWebArea", children: [
            PageNode(role: "AXGroup", children: [Self.text(huge, y: 100), Self.field("Q", y: 300, value: huge, focused: true)]),
        ])
        let context = PageContext.make(page: page, url: "u", title: "t", selection: huge, viewport: nil)
        #expect((context.field?.count ?? 0) < PageContext.Limits.field + 40)
        #expect((context.surrounding?.count ?? 0) <= PageContext.Limits.surrounding + 1)
        #expect((context.selection?.count ?? 0) <= PageContext.Limits.selection + 1)
        #expect((context.visible?.count ?? 0) <= PageContext.Limits.visible + 1)
    }

    @Test func theSettingIsOnByDefaultAndKept() throws {
        #expect(Config.default.agentPageContext)
        var config = Config.default
        config.agentPageContext = false
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)).agentPageContext == false)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).agentPageContext)
    }
}
