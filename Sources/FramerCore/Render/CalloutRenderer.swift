import CoreGraphics

/// Draws zoom callouts: the enlarged card and the outline around the region it magnifies.
public enum CalloutRenderer {
    /// `crop` inside a rounded border, at exactly `size` pixels.
    public static func card(_ crop: CGImage, size: PixelSize, cornerRadius: Double, borderWidth: Double, borderColor: RGBAColor) -> CGImage {
        let ctx = CGContext.makeCanvas(size: size)
        let bounds = CGRect(origin: .zero, size: size.cgSize)
        if borderWidth > 0 {
            ctx.setFillColor(borderColor.cgColor)
            ctx.addPath(roundedRect(bounds, radius: cornerRadius))
            ctx.fillPath()
        }
        let inner = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        guard inner.width > 0, inner.height > 0 else { return ctx.makeImage()! }
        ctx.addPath(roundedRect(inner, radius: cornerRadius - borderWidth))
        ctx.clip()
        ctx.draw(crop, in: inner)
        return ctx.makeImage()!
    }

    /// Strokes an outline just outside `source`, following its rotation.
    static func highlight(_ source: PlacedRect, lineWidth: Double, cornerRadius: Double, color: RGBAColor, ctx: CGContext) {
        let local = CGRect(origin: .zero, size: source.rect.size).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        var toDevice = source.transform(from: source.rect.size).concatenating(.flipY(height: Double(ctx.height)))
        let clamped = max(0, min(cornerRadius, local.width / 2, local.height / 2))
        let path = CGPath(roundedRect: local, cornerWidth: clamped, cornerHeight: clamped, transform: &toDevice)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func roundedRect(_ rect: CGRect, radius: Double) -> CGPath {
        // CGPath traps if a corner radius exceeds half the rect.
        let clamped = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
    }
}
