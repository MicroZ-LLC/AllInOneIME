import AppKit
import QuartzCore

/// A light passing over the bars of rows on their way (`PanelModel.pending`), left to right, again and again: Core
/// Animation's, so the main thread (the keys) isn't asked for it. Drawn over the bars, which the panel draws; nothing to
/// click (clicks go to the panel), and nothing in an offscreen image.
public final class ShimmerView: NSView {
    private let gradient = CAGradientLayer()
    private let mask = CAShapeLayer()

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.mask = mask
        layer?.addSublayer(gradient)
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.3, 0]
        sweep.toValue = [1, 1.3, 1.6]
        sweep.duration = 1.4
        sweep.repeatCount = .infinity
        gradient.add(sweep, forKey: "sweep")
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override public func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The bars, in its own coordinates from its top left, and the light's color for the appearance.
    public func update(bars: [NSRect], dark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let light = NSColor.white.withAlphaComponent(dark ? 0.1 : 0.55).cgColor, clear = NSColor.white.withAlphaComponent(0).cgColor
        gradient.colors = [clear, light, clear]
        let path = CGMutablePath()
        let flipped = gradient.contentsAreFlipped()
        for bar in bars {
            // Unless the layers are flipped, their y goes up: the bar's from the bottom.
            let rect = CGRect(x: bar.minX, y: flipped ? bar.minY : bounds.height - bar.maxY, width: bar.width, height: bar.height)
            path.addRoundedRect(in: rect, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2)
        }
        mask.path = path
        CATransaction.commit()
    }
}
