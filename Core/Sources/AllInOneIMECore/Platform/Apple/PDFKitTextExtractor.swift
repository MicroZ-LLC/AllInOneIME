#if canImport(PDFKit)
import Foundation
import PDFKit

/// PDFKit's reading of a PDF.
public struct PDFKitTextExtractor: PDFTextExtractor {
    public init() {}

    public func text(ofPDF data: Data) -> (title: String, body: String)? {
        guard let document = PDFDocument(data: data) else { return nil }
        return ((document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) ?? "", document.string ?? "")
    }
}
#endif
