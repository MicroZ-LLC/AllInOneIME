import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// One @'s AI command typed by its name where AI isn't used (an app with No AI) is listed dimmed, and nothing picks it;
/// a click on it does what ⏎ on it does, as the keys and the README say: the notice why, the draft and the list as they
/// were (rule 1: the same for keys and clicks). The shell sends a click on it (`PanelModel.Row.saysWhy`,
/// `CandidateLayout.row(at:frames:rows:clicked:)`), never the pointer's highlight.
struct OneAtUnavailableClickTests {
    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.appProfiles = ["com.example.chat": AppProfile(noAI: true)]
        }
    }

    /// `@que` typed in an app with No AI: the field's host, and the dimmed row's place among the rows shown.
    func typed() throws -> (host: FakeHost, row: Int) {
        let settings = Settings()
        let host = FakeHost(services: SessionServices(loadSettings: { settings.config }))
        host.session.services.levelOne = { .engine(FakeEngine()) }
        host.app = "com.example.chat"
        host.focus()
        host.composer.setInputMode(.english)
        host.type("@que")
        let rows = try #require(host.panel?.rows, "no panel after @que")
        let row = try #require(rows.firstIndex { $0.text == "question" }, "\(rows.map(\.text))")
        return (host, row)
    }

    @Test func aClickOnTheDimmedRowSaysWhyAsReturnDoes() async throws {
        try await withInterfaceLanguage("en") {
            let (host, row) = try typed()
            let draft = host.composer.draft
            host.send(.pick(row))
            #expect(host.panel?.detail == InputSession.aiRefusal, "\(String(describing: host.panel?.detail))")
            #expect(host.composer.draft == draft && host.composer.oneAt != nil, "the draft or the list changed: \(host.composer.draft)")
            // As ⏎ on it.
            let (keyed, _) = try typed()
            keyed.press(FakeHost.enter)
            #expect(keyed.panel?.detail == host.panel?.detail)
        }
    }

    @Test func theDimmedRowTakesAClickButNoHighlight() async throws {
        try await withInterfaceLanguage("en") {
            let (host, row) = try typed()
            let rows = try #require(host.panel?.rows)
            #expect(!rows[row].pickable && rows[row].choice == nil && rows[row].saysWhy, "\(rows[row])")
            #expect(rows.filter(\.saysWhy).count == 1, "only the dimmed row: \(rows)")
            let frames = rows.indices.map { CGRect(x: 0, y: CGFloat($0) * 20, width: 200, height: 20) }
            let point = CGPoint(x: 10, y: CGFloat(row) * 20 + 10)
            #expect(CandidateLayout.row(at: point, frames: frames, rows: rows, clicked: false) == nil, "highlighted under the pointer")
            #expect(CandidateLayout.row(at: point, frames: frames, rows: rows, clicked: true) == row, "a click on it isn't sent")
            // A pickable row below it as before: picked by a click, highlighted under the pointer.
            let more = rows + [PanelModel.Row(label: "", text: "open", kind: .candidate)]
            let below = CGPoint(x: 10, y: CGFloat(rows.count) * 20 + 10), all = frames + [CGRect(x: 0, y: CGFloat(rows.count) * 20, width: 200, height: 20)]
            #expect(CandidateLayout.row(at: below, frames: all, rows: more, clicked: true) == rows.count)
            #expect(CandidateLayout.row(at: below, frames: all, rows: more, clicked: false) == rows.count)
        }
    }

    /// A row that is neither pickable nor says why (a list's information) still takes no click.
    @Test func aRowThatSaysNothingTakesNoClick() {
        let rows = [PanelModel.Row(label: "", text: "info", kind: .original, pickable: false)]
        let frames = [CGRect(x: 0, y: 0, width: 200, height: 20)]
        #expect(CandidateLayout.row(at: CGPoint(x: 10, y: 10), frames: frames, rows: rows, clicked: true) == nil)
    }
}
