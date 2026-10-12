import CoreGraphics

/// Draws a screenshot as a frameless Mac window, at the screenshot's own size.
public enum WindowCompositor {
    /// The screenshot with its corners rounded and a hairline just inside its edge. Transparent outside the corners,
    /// and wherever the screenshot already was, so a capture with its own rounded corners keeps them, and its hairline
    /// stays on the window rather than crossing those corners.
    public static func composite(_ screenshot: CGImage, style: WindowStyle) -> CGImage {
        let size = screenshot.pixelSize
        let ctx = CGContext.makeCanvas(size: size)
        let bounds = CGRect(origin: .zero, size: size.cgSize)
        let radius = max(0, min(style.cornerRadius, bounds.width / 2, bounds.height / 2))

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(screenshot, in: bounds)
        ctx.restoreGState()

        if style.borderWidth > 0 {
            let inset = style.borderWidth / 2
            let outline = bounds.insetBy(dx: inset, dy: inset)
            let outlineRadius = max(0, min(radius - inset, outline.width / 2, outline.height / 2))
            ctx.addPath(CGPath(roundedRect: outline, cornerWidth: outlineRadius, cornerHeight: outlineRadius, transform: nil))
            ctx.setStrokeColor(style.borderColor.cgColor)
            ctx.setLineWidth(style.borderWidth)
            ctx.setBlendMode(.sourceAtop)
            ctx.strokePath()
        }
        return ctx.makeImage()!
    }
}
