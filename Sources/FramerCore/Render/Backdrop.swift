import CoreGraphics
import Foundation

/// Soft light over the background gradient: `color` at the centre, fading out to nothing at `radius`.
public struct GlowSpec: Sendable, Hashable {
    /// Centre in page units: `x` in page widths from the left edge of the first page, `y` in page heights.
    public var x: Double
    public var y: Double
    /// In page widths.
    public var radius: Double
    public var color: RGBAColor

    public init(x: Double = 0.5, y: Double = 0.5, radius: Double = 0.5, color: RGBAColor) {
        self.x = x
        self.y = y
        self.radius = radius
        self.color = color
    }

    /// Fraction of the centre's alpha left at `t` (0 at the centre, 1 at `radius`). Level at both ends, so the glow
    /// has neither a bright point in the middle nor a visible rim.
    static func falloff(_ t: Double) -> Double {
        let remaining = 1 - t * t
        return remaining * remaining
    }

    func draw(in ctx: CGContext, page: PixelSize) {
        let pageWidth = Double(page.width)
        let endRadius = radius * pageWidth
        guard endRadius > 0 else { return }
        let stops = (0...12).map { Double($0) / 12 }
        let colors = stops.map { t in
            RGBAColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha * Self.falloff(t)).cgColor
        }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace.sRGBSpace, colors: colors as CFArray, locations: stops.map { CGFloat($0) }) else {
            return
        }
        let center = CGPoint(x: x * pageWidth, y: Double(ctx.height) - y * Double(page.height))
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: endRadius, options: [])
    }
}

/// A picture drawn over the background gradient and its glows, under the devices.
public struct BackgroundImageSpec: Sendable, Hashable {
    public var input: URL
    /// Centre, width and rotation in page units, as for a device.
    public var placement: DevicePlacement
    /// 0–1.
    public var opacity: Double

    public init(input: URL, placement: DevicePlacement, opacity: Double = 1) {
        self.input = input
        self.placement = placement
        self.opacity = opacity
    }
}

extension InsetRenderer {
    /// What goes between the background gradient and the devices.
    public struct Backdrop {
        public var glows: [GlowSpec]
        public var images: [Image]

        public struct Image {
            public var image: CGImage
            public var placement: DevicePlacement
            public var opacity: Double

            public init(image: CGImage, placement: DevicePlacement, opacity: Double = 1) {
                self.image = image
                self.placement = placement
                self.opacity = opacity
            }
        }

        public init(glows: [GlowSpec] = [], images: [Image] = []) {
            self.glows = glows
            self.images = images
        }

        var isEmpty: Bool { glows.isEmpty && images.isEmpty }

        func draw(in ctx: CGContext, page: PixelSize) {
            for glow in glows {
                glow.draw(in: ctx, page: page)
            }
            for image in images {
                ctx.saveGState()
                ctx.setAlpha(image.opacity)
                ctx.draw(image.image, placed: image.placement.resolve(page: page, contentSize: image.image.pixelSize))
                ctx.restoreGState()
            }
        }
    }
}
