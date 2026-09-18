import CoreGraphics
import Foundation

/// A linear gradient (or solid fill when one colour). Angle follows CSS: 0° = bottom→top,
/// 90° = left→right, 180° = top→bottom.
public struct GradientSpec: Sendable, Hashable {
    public var colors: [RGBAColor]
    public var angleDegrees: Double
    /// Optional colour stops in 0...1; count must equal `colors.count`.
    public var locations: [Double]?

    public init(colors: [RGBAColor], angleDegrees: Double = 180, locations: [Double]? = nil) {
        self.colors = colors
        self.angleDegrees = angleDegrees
        self.locations = locations
    }

    public init(solid color: RGBAColor) {
        self.init(colors: [color])
    }

    public func validate() throws {
        guard !colors.isEmpty else { throw FramerError.config("background needs at least one color") }
        if let locations {
            guard locations.count == colors.count else {
                throw FramerError.config("background 'locations' count (\(locations.count)) must match 'colors' count (\(colors.count))")
            }
            guard locations.allSatisfy({ (0...1).contains($0) }) else {
                throw FramerError.config("background 'locations' must be within 0...1")
            }
        }
    }

    /// Gradient line endpoints for a rect in CoreGraphics (y-up) coordinates.
    /// Uses the CSS gradient-line length so the end colours land exactly on the corners.
    public func endpoints(in rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        let theta = angleDegrees * .pi / 180
        let dx = sin(theta)
        let dy = cos(theta)
        let length = abs(rect.width * dx) + abs(rect.height * dy)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let half = length / 2
        return (
            CGPoint(x: center.x - dx * half, y: center.y - dy * half),
            CGPoint(x: center.x + dx * half, y: center.y + dy * half)
        )
    }

    /// Fills `rectTL` (top-left coordinates) in `ctx`.
    func fill(_ ctx: CGContext, rectTL: CGRect) {
        let rect = rectTL.flipped(in: Double(ctx.height))
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if colors.count == 1 {
            ctx.setFillColor(colors[0].cgColor)
            ctx.fill(rect)
            return
        }

        let cgColors = colors.map(\.cgColor) as CFArray
        let stops = locations?.map { CGFloat($0) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpace.sRGBSpace, colors: cgColors, locations: stops) else {
            ctx.setFillColor(colors[0].cgColor)
            ctx.fill(rect)
            return
        }
        ctx.clip(to: rect)
        let (start, end) = endpoints(in: rect)
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
