import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac
import AllInOneIMETestSupport

/// One @ on the Mac: what is known at once finds an app by a word's start of its name, and by the pinyin and initials of
/// its Chinese name (`AppIndex.spellings`, `InstantFiles.ranked`); and how long the rows take on the key with this Mac's
/// own app index and date reading (printed for the record).
struct OneAtMacTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("OneAtMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func app(_ name: String, chinese: String? = nil) throws {
        let contents = root.appendingPathComponent("\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": name], format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard let chinese else { return }
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["zh_CN": ["CFBundleDisplayName": chinese]], format: .binary, options: 0)
            .write(to: contents.appendingPathComponent("Resources/InfoPlist.loctable"))
    }

    @Test func chineseNamesAreSpelledInPinyinAndInitials() {
        #expect(AppIndex.spellings("系统设置") == ["xitongshezhi", "xtsz"])
        #expect(AppIndex.spellings("微信") == ["weixin", "wx"])
        #expect(AppIndex.spellings("下載項目") == ["xiazaixiangmu", "xzxm"], "traditional characters too")
        #expect(AppIndex.spellings("Safari").isEmpty)
    }

    @Test func appsAreFoundByAWordsStartThenByTheirPinyinAndInitials() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try app("WeChat", chinese: "微信")
        try app("System Settings", chinese: "系统设置")
        try app("Preset Manager")
        try app("Wxcode")
        let files = InstantFiles(index: AppIndex(folders: [root.path], apps: [], home: nil, recheckInterval: 0))
        files.make(history: OpenHistory())
        func names(_ query: String) -> [String] { files.results(query, history: OpenHistory()).map(\.name) }
        #expect(names("set") == ["System Settings", "Preset Manager"], "a word's start first: \(names("set"))")
        #expect(names("wx") == ["Wxcode", "WeChat"], "the name first, then the initials: \(names("wx"))")
        #expect(names("xtsz") == ["System Settings"])
        #expect(names("weix") == ["WeChat"])
        #expect(names("xt").contains("System Settings") && !names("tsz").contains("System Settings"), "the start of the pinyin only")
    }

    /// The rows on the key that changed the text, with this Mac's app index (`InstantFiles.shared`) and dates read as
    /// `@reminder` reads them, pinyin from the stand-in engine (its own engine aside, as the spec has it): printed.
    @Test func rowsOnTheKeyWithThisMacsSources() {
        do {
            InstantFiles.shared.make(history: OpenHistory())
            var config = Config.default
            config.setOrder([Language.chinese, .english])
            let fixed = config
            var services = SessionServices(loadSettings: { fixed })
            services.levelOne = {
                let engine = FakeEngine()
                engine.dictionary.merge(["wx": ["我想", "无线"], "mingtianxiawusandiankaihui": ["明天下午3点开会"]]) { $1 }
                return .engine(engine)
            }
            services.instantResults = { InstantFiles.shared.results($0, history: $1) }
            services.parseReminder = { ReminderParser().parse($0, now: Date()) }
            var lines: [String] = []
            func measure(_ name: String, english: Bool, _ keys: [KeyEvent]) {
                var times: [Double] = []
                var first = ""
                for _ in 0..<15 {
                    let host = FakeHost(services: services)
                    host.focus()
                    if english { host.composer.setInputMode(.english) }
                    for key in keys.dropLast() { host.press(key) }
                    let start = DispatchTime.now().uptimeNanoseconds
                    host.press(keys.last!)
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    first = host.panel?.rows.first(where: { row in !host.composer.engineState.candidates.contains { $0.text == row.text } })
                        .map { $0.text + " " + $0.comment } ?? "-"
                }
                times.sort()
                lines.append(String(format: "%@: %.1f ms (median of 15, worst %.1f), first row “%@”", name, times[times.count / 2],
                                    times.last!, first))
            }
            func keys(_ text: String) -> [KeyEvent] {
                text.map { $0 == "@" ? FakeHost.at : $0 == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String($0)) }
            }
            measure("@saf", english: true, keys("@saf"))
            measure("@wx (composed as 我想)", english: false, keys("@wx"))
            measure("@3*7+2", english: true, keys("@3*7+2"))
            measure("@明天下午3点开会 (Space picks it)", english: false, keys("@mingtianxiawusandiankaihui") + [FakeHost.space])
            measure("@thank you for the gift", english: true, keys("@thank you for the gift"))
            print("one @, rows on the key (debug build):\n  " + lines.joined(separator: "\n  "))
        }
    }
}
