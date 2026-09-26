import CoreGraphics

/// A drop shadow cast by devices and callout cards.
public struct ShadowSpec: Sendable, Hashable {
    public var color: RGBAColor
    /// Blur radius in pixels. `nil` = 5 % of the page width.
    public var radius: Double?
    public var offsetX: Double
    /// Pixels, positive = down. `nil` = 2 % of the page width.
    public var offsetY: Double?

    public init(color: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.45), radius: Double? = nil, offsetX: Double = 0, offsetY: Double? = nil) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    func apply(to ctx: CGContext, pageWidth: Double) {
        // Shadow offsets are in device space (y-up) and ignore the CTM, so rotated content still casts downwards.
        ctx.setShadow(
            offset: CGSize(width: offsetX, height: -(offsetY ?? (pageWidth * 0.02).rounded())),
            blur: radius ?? (pageWidth * 0.05).rounded(),
            color: color.cgColor
        )
    }
}
