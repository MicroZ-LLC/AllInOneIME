import Foundation

/// Reads a PDF's text, for `@read` (`WebReader`): PDFKit on Apple platforms (`PDFKitTextExtractor`); elsewhere none
/// yet, and a PDF can't be read.
public protocol PDFTextExtractor: Sendable {
    /// The document's title (empty: none) and its text; nil when it can't be read.
    func text(ofPDF data: Data) -> (title: String, body: String)?
}

/// No PDF reader on this platform.
public struct UnsupportedPDFTextExtractor: PDFTextExtractor {
    public init() {}
    public func text(ofPDF data: Data) -> (title: String, body: String)? { nil }
}
