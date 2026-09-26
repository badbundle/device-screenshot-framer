import CoreGraphics

/// An enlarged copy of part of a device's screen, drawn as a card.
public struct CalloutSpec: Sendable, Hashable {
    /// Index of the device whose screenshot is magnified.
    public var device: Int
    /// Area to magnify, in the screenshot's own pixels (top-left origin).
    public var region: CGRect
    /// Card centre in page units. `nil` centres the card over the region it magnifies.
    public var x: Double?
    public var y: Double?
    /// Card size relative to the region's size on the device.
    public var scale: Double
    /// Degrees clockwise. `nil` matches the device's rotation.
    public var rotation: Double?
    /// Pixels. `nil` = 3 % of the page width.
    public var cornerRadius: Double?
    /// Pixels. `nil` = 0.8 % of the page width. 0 for no border.
    public var borderWidth: Double?
    public var borderColor: RGBAColor
    /// Outline the magnified region on the device.
    public var highlight: Bool

    public init(
        device: Int = 0,
        region: CGRect,
        x: Double? = nil,
        y: Double? = nil,
        scale: Double = 1.5,
        rotation: Double? = nil,
        cornerRadius: Double? = nil,
        borderWidth: Double? = nil,
        borderColor: RGBAColor = .white,
        highlight: Bool = true
    ) {
        self.device = device
        self.region = region
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.highlight = highlight
    }

    public func resolvedCornerRadius(pageWidth: Double) -> Double { cornerRadius ?? (pageWidth * 0.03).rounded() }
    public func resolvedBorderWidth(pageWidth: Double) -> Double { borderWidth ?? (pageWidth * 0.008).rounded() }

    // CGRect is only Hashable from macOS 15, and the package deploys to macOS 14.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(device)
        hasher.combine(region.minX)
        hasher.combine(region.minY)
        hasher.combine(region.width)
        hasher.combine(region.height)
    }
}

public enum CalloutLayout {
    public struct Result: Sendable, Equatable {
        /// The magnified region where it appears on the device.
        public var source: PlacedRect
        /// Where the enlarged card goes.
        public var card: PlacedRect
    }

    /// Converts a region in screenshot pixels into the framed image's pixels, given how the screenshot was
    /// aspect-filled into the frame (`FrameGeometry.aspectFill`).
    public static func framedRegion(_ region: CGRect, screenshotFill fill: (rect: CGRect, scale: Double)) -> CGRect {
        CGRect(
            x: fill.rect.minX + region.minX * fill.scale,
            y: fill.rect.minY + region.minY * fill.scale,
            width: region.width * fill.scale,
            height: region.height * fill.scale
        )
    }

    /// - Parameters:
    ///   - region: the magnified area in the device's framed-image pixels (see `framedRegion`).
    ///   - device: where that framed image is drawn on the canvas.
    public static func compute(_ spec: CalloutSpec, region: CGRect, device: PlacedRect, framedSize: PixelSize, page: PixelSize) -> Result {
        let toCanvas = device.transform(from: framedSize.cgSize)
        let scale = device.rect.width / Double(framedSize.width)
        let sourceCenter = CGPoint(x: region.midX, y: region.midY).applying(toCanvas)
        let sourceSize = CGSize(width: region.width * scale, height: region.height * scale)
        let source = PlacedRect(
            rect: CGRect(x: sourceCenter.x - sourceSize.width / 2, y: sourceCenter.y - sourceSize.height / 2, width: sourceSize.width, height: sourceSize.height),
            rotation: device.rotation
        )

        let cardSize = CGSize(width: (sourceSize.width * spec.scale).rounded(), height: (sourceSize.height * spec.scale).rounded())
        let cardCenter = CGPoint(
            x: spec.x.map { $0 * Double(page.width) } ?? sourceCenter.x,
            y: spec.y.map { $0 * Double(page.height) } ?? sourceCenter.y
        )
        let card = PlacedRect(
            rect: CGRect(x: cardCenter.x - cardSize.width / 2, y: cardCenter.y - cardSize.height / 2, width: cardSize.width, height: cardSize.height),
            rotation: spec.rotation ?? device.rotation
        )
        return Result(source: source, card: card)
    }
}
