import Foundation
@testable import AllInOneIMECore

/// The Korean and Hindi packs' data as this checkout has it (LanguagePacks/), for the tests.
enum PackData {
    static let folder = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LanguagePacks")
    static let hangul = try! HangulTables.load(from: folder.appendingPathComponent("ko-hangul"))
    static let hindi = try! HindiTables.load(from: folder.appendingPathComponent("hi-phonetic"))
}
