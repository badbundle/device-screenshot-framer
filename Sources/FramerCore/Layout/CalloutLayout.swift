import CoreGraphics

/// The shadow under a callout card.
public enum CalloutShadow: Sendable, Hashable {
    /// The one the devices cast, if any.
    case inherit
    case none
    /// Its own; with no offset and a colour, a glow.
    case custom(ShadowSpec)

    func resolve(inheriting inherited: ShadowSpec?) -> ShadowSpec? {
        switch self {
        case .inherit: inherited
        case .none: nil
        case .custom(let shadow): shadow
        }
    }
}

/// An enlarged copy of part of a device's screen, drawn as a card.
public struct CalloutSpec: Sendable, Hashable {
    /// Index of the device whose screenshot is magnified.
    public var device: Int
    /// Area to magnify, in the screenshot's own pixels (top-left origin).
    public var region: CGRect
    /// Card centre in page units. `nil` centres the card over the region it magnifies.
    public var x: Double?
    public var y: Double?
    /// Moves the card from `x` / `y` (or from over the region), in the screenshot's pixels along the device's own axes,
    /// so it follows the device's size and tilt.
    public var offsetX: Double
    public var offsetY: Double
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
    public var shadow: CalloutShadow

    public init(
        device: Int = 0,
        region: CGRect,
        x: Double? = nil,
        y: Double? = nil,
        offsetX: Double = 0,
        offsetY: Double = 0,
        scale: Double = 1.5,
        rotation: Double? = nil,
        cornerRadius: Double? = nil,
        borderWidth: Double? = nil,
        borderColor: RGBAColor = .white,
        highlight: Bool = true,
        shadow: CalloutShadow = .inherit
    ) {
        self.device = device
        self.region = region
        self.x = x
        self.y = y
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.highlight = highlight
        self.shadow = shadow
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

    /// Converts the spec's offset from screenshot pixels into the framed image's pixels.
    public static func framedOffset(_ spec: CalloutSpec, screenshotFill fill: (rect: CGRect, scale: Double)) -> CGSize {
        CGSize(width: spec.offsetX * fill.scale, height: spec.offsetY * fill.scale)
    }

    /// - Parameters:
    ///   - region: the magnified area in the device's framed-image pixels (see `framedRegion`).
    ///   - offset: how far to move the card, in the framed image's pixels along its axes (see `framedOffset`).
    ///   - device: where that framed image is drawn on the canvas.
    public static func compute(
        _ spec: CalloutSpec,
        region: CGRect,
        offset: CGSize = .zero,
        device: PlacedRect,
        framedSize: PixelSize,
        page: PixelSize
    ) -> Result {
        let toCanvas = device.transform(from: framedSize.cgSize)
        let scale = device.rect.width / Double(framedSize.width)
        let sourceCenter = CGPoint(x: region.midX, y: region.midY).applying(toCanvas)
        let sourceSize = CGSize(width: region.width * scale, height: region.height * scale)
        let source = PlacedRect(
            rect: CGRect(x: sourceCenter.x - sourceSize.width / 2, y: sourceCenter.y - sourceSize.height / 2, width: sourceSize.width, height: sourceSize.height),
            rotation: device.rotation
        )

        let cardSize = CGSize(width: (sourceSize.width * spec.scale).rounded(), height: (sourceSize.height * spec.scale).rounded())
        var cardCenter = CGPoint(
            x: spec.x.map { $0 * Double(page.width) } ?? sourceCenter.x,
            y: spec.y.map { $0 * Double(page.height) } ?? sourceCenter.y
        )
        if offset != .zero {
            let angle = device.rotation * .pi / 180
            let dx = offset.width * scale
            let dy = offset.height * scale
            cardCenter.x += dx * cos(angle) - dy * sin(angle)
            cardCenter.y += dx * sin(angle) + dy * cos(angle)
        }
        let card = PlacedRect(
            rect: CGRect(x: cardCenter.x - cardSize.width / 2, y: cardCenter.y - cardSize.height / 2, width: cardSize.width, height: cardSize.height),
            rotation: spec.rotation ?? device.rotation
        )
        return Result(source: source, card: card)
    }
}
