// Makes the logos of Settings → AI's choices, Resources/AILogos/<name>.pdf, from the SVGs beside them: each drawn by
// macOS's own SVG support into a vector PDF page of 24 × 24 points (a logo that isn't square centred in it), black on
// clear, which the app draws as a template image (in the text's color: AIPicker.swift). PDF because every macOS the app
// runs on draws it (NSImage reads SVG on recent ones only). Run when an SVG changes:
//
//   swift Scripts/make-ai-logos.swift
//
// The SVGs: Simple Icons' (CC0: claude, anthropic, openai, googlegemini, amazonwebservices, apple) as they publish them,
// Kiro's mark from kiro.dev made one color, its eyes cut out of it (kiro.svg), and Google Antigravity's mark from
// antigravity.google/favicon.svg, its outline alone, one color (antigravity.svg). The marks are their owners' trademarks,
// shown to name their products.

import AppKit

let folder = URL(fileURLWithPath: "Resources/AILogos", isDirectory: true)
let side: CGFloat = 24
let svgs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "svg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
for svg in svgs {
    guard let image = NSImage(contentsOf: svg), image.size.width > 0, image.size.height > 0 else {
        print("can't read \(svg.lastPathComponent)")
        exit(1)
    }
    let scale = side / max(image.size.width, image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let rect = NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
    let pdf = svg.deletingPathExtension().appendingPathExtension("pdf")
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    guard let context = CGContext(pdf as CFURL, mediaBox: &box, [kCGPDFContextCreator: "AllInOneIME"] as CFDictionary) else {
        print("can't write \(pdf.lastPathComponent)")
        exit(1)
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    print(pdf.path)
}
