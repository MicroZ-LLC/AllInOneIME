#if canImport(AppKit)
import AppKit

extension NSColor {
    /// WCAG's contrast ratio of this color (its alpha over `background`) against `background`, both in sRGB (the
    /// candidate panel's highlighted row is at least 1.6:1).
    public func contrastRatio(over background: NSColor) -> CGFloat {
        guard let color = usingColorSpace(.sRGB), let background = background.usingColorSpace(.sRGB) else { return 1 }
        func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let a = color.alphaComponent
        func over(_ c: CGFloat, _ b: CGFloat) -> CGFloat { c * a + b * (1 - a) }
        let front = luminance(over(color.redComponent, background.redComponent), over(color.greenComponent, background.greenComponent),
                              over(color.blueComponent, background.blueComponent))
        let back = luminance(background.redComponent, background.greenComponent, background.blueComponent)
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }
}
#endif
