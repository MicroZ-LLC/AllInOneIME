import Foundation
import Testing

/// The macOS app's String Catalog, Resources/Localizable.xcstrings (the app's own text; the core's is in Core/), as
/// the core's is checked (InterfaceTextTests).
struct StringCatalogTests {
    /// The repository root (this file is Tests/AllInOneIMEMacTests/StringCatalogTests.swift).
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func catalogTranslationsFit() throws {
        try StringCatalogCheck.translationsFit(Self.root.appendingPathComponent("Resources/Localizable.xcstrings"))
    }
}
