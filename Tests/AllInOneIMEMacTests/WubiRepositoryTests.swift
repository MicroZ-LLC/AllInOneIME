import AllInOneIMECore
import Foundation
import Testing

/// Wubi 86 (`PinyinScheme.wubi`) in what the Mac shell and the release are made of: the settings search's words (the
/// search reads them from its row, in the executable), the data the Makefile fetches and the app carries, its license
/// on the disk image and in the notices, the documentation.
struct WubiRepositoryTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func settingsSearchFindsItAsWubi86() throws {
        let source = try read("Sources/AllInOneIME/SettingsSearch.swift")
        let start = try #require(source.range(of: "case .pinyinScheme:\n"))
        let end = try #require(source.range(of: "case .chineseCharacters:", range: start.upperBound..<source.endIndex))
        let keywords = source[start.upperBound..<end.lowerBound].lowercased()
        for word in ["wubi", "五笔", "五筆", "86"] {
            #expect(keywords.contains(word), "Settings search must find \(word)")
        }
        // Its names in either language come from the scheme's own (`PinyinScheme.others`).
        #expect(keywords.contains("pinyinscheme.others.map"))
        #expect(PinyinScheme.others.contains(.wubi))
    }

    @Test func theAppCarriesRimeWubisDataAndItsLicense() throws {
        let makefile = try read("Makefile")
        #expect(makefile.contains("WUBI_FILES := " + PinyinScheme.wubiData.joined(separator: " ")))
        #expect(makefile.contains("RIME_WUBI_COMMIT     := 152a0d3f3efe40cae216d1e3b338242446848d07"))
        #expect(makefile.contains("RIME_WUBI_SCHEMA_SHA256 :=") && makefile.contains("RIME_WUBI_DICT_SHA256   :="))
        #expect(makefile.contains(#"ditto $(WUBI_DATA) "$(APP)/Contents/SharedSupport/rime-wubi""#))
        #expect(makefile.contains(#"EXCLUDE="$(ZHUYIN_FILES) $(WUBI_FILES)""#), "the pack leaves it out")
        #expect(try read("Scripts/make-dmg.sh").contains(#"cp "$thirdparty/rime-wubi/LICENSE" "$stage/LICENSE-Wubi-data-LGPL-3.0.txt""#))
        #expect(try read("Resources/DMG-ReadMe.txt").contains("LICENSE-Wubi-data-LGPL-3.0.txt"))
        let notices = try read("THIRD_PARTY_NOTICES.md")
        #expect(notices.contains("## rime-wubi (Wubi 86)") && notices.contains("wubi86.custom.yaml"))
        #expect(notices.contains("LICENSE-Wubi-data-LGPL-3.0.txt"))
    }

    @Test func theDocumentationNamesIt() throws {
        #expect(try read("README.md").contains("**Wubi 86**") && read("README.md").contains(#"`"wubi86"` for Wubi 86"#))
        #expect(try read("README.zh-CN.md").contains("**五笔 86**") && read("README.zh-CN.md").contains(#"五笔 86 写 `"wubi86"`"#))
    }
}
