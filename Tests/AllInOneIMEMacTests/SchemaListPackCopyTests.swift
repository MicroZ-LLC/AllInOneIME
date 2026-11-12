import Foundation
import Testing
@testable import AllInOneIMECore

/// The Chinese pack's schema list (Resources/rime/default.custom.yaml), which librime's start copies into the Rime user
/// folder where there is none, is one the app takes as its own (`PinyinScheme.earlierSchemaLists`): any other unmarked
/// list is the user's, left alone, so a copy the app didn't know would keep Shuangpin and Zhuyin from being listed.
struct SchemaListPackCopyTests {
    /// The repository root (this file is Tests/AllInOneIMEMacTests/SchemaListPackCopyTests.swift).
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func thePacksCopyIsTheAppsToReplace() throws {
        let copy = try String(contentsOf: root.appendingPathComponent("Resources/rime/default.custom.yaml"), encoding: .utf8)
        #expect(PinyinScheme.earlierSchemaLists.last == copy)
        #expect(PinyinScheme.ownsSchemaList(copy) && PinyinScheme.listedSchemas(copy) == [PinyinScheme.fullSchema])
    }
}
