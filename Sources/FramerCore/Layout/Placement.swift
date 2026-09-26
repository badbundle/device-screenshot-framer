import CoreGraphics

/// Where a device goes, in page units: `x` and `width` are fractions of the page width, `y` of the page height.
/// `x` is measured from the left edge of the first page, so values above 1 reach into later pages of a panorama.
/// Values outside 0...1 put the device partly off the canvas.
public struct DevicePlacement: Sendable, Hashable {
    /// Horizontal centre of the device.
    public var x: Double
    /// Vertical centre of the device.
    public var y: Double
    public var width: Double
    /// Degrees clockwise.
    public var rotation: Double

    public init(x: Double = 0.5, y: Double = 0.5, width: Double = 0.8, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.rotation = rotation
    }

    public func resolve(page: PixelSize, contentSize: PixelSize) -> PlacedRect {
        let pageWidth = Double(page.width)
        let w = (width * pageWidth).rounded()
        let h = (w * Double(contentSize.height) / Double(contentSize.width)).rounded()
        let rect = CGRect(
            x: (x * pageWidth - w / 2).rounded(),
            y: (y * Double(page.height) - h / 2).rounded(),
            width: w,
            height: h
        )
        return PlacedRect(rect: rect, rotation: rotation)
    }
}

/// A rect in top-left canvas pixels, rotated clockwise by `rotation` degrees about its centre.
public struct PlacedRect: Sendable, Equatable {
    public var rect: CGRect
    public var rotation: Double

    public init(rect: CGRect, rotation: Double = 0) {
        self.rect = rect
        self.rotation = rotation
    }

    public var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// Maps top-left pixel coordinates of content sized `size` onto the canvas.
    public func transform(from size: CGSize) -> CGAffineTransform {
        CGAffineTransform(scaleX: rect.width / size.width, y: rect.height / size.height)
            .concatenating(CGAffineTransform(translationX: -rect.width / 2, y: -rect.height / 2))
            .concatenating(CGAffineTransform(rotationAngle: rotation * .pi / 180))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }
}

extension PlacedRect {
    /// Corners on the canvas after rotation, clockwise from the rect's own top-left.
    public var corners: [CGPoint] {
        let t = transform(from: rect.size)
        return [
            CGPoint(x: 0, y: 0),
            CGPoint(x: rect.width, y: 0),
            CGPoint(x: rect.width, y: rect.height),
            CGPoint(x: 0, y: rect.height),
        ].map { $0.applying(t) }
    }

    /// Topmost and bottommost canvas y of the rotated rect within the vertical strip `xRange`. `nil` if it misses the strip.
    public func verticalExtent(within xRange: ClosedRange<Double>) -> ClosedRange<Double>? {
        let clipped = Self.clip(Self.clip(corners, toX: xRange.lowerBound, keepAbove: true), toX: xRange.upperBound, keepAbove: false)
        guard let top = clipped.map(\.y).min(), let bottom = clipped.map(\.y).max() else { return nil }
        return top...bottom
    }

    /// Axis-aligned bounds of the rotated rect.
    public var bounds: CGRect {
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// How far this rect can move straight down (`downward`) or up before it touches `other`; negative if they already
    /// overlap, or `other` is on the side it moves away from. `nil` if no vertical line crosses both.
    public func verticalClearance(to other: PlacedRect, downward: Bool) -> Double? {
        let mine = corners
        let theirs = other.corners
        let low = max(mine.map(\.x).min()!, theirs.map(\.x).min()!)
        let high = min(mine.map(\.x).max()!, theirs.map(\.x).max()!)
        guard low <= high else { return nil }
        // Both outlines are straight between corners, so the closest approach is at a corner or an end of the overlap.
        let xs = [low, high] + (mine + theirs).map(\.x).filter { $0 > low && $0 < high }
        return xs.compactMap { x -> Double? in
            guard let a = verticalExtent(within: x...x), let b = other.verticalExtent(within: x...x) else { return nil }
            return downward ? b.lowerBound - a.upperBound : a.lowerBound - b.upperBound
        }.min()
    }

    /// One Sutherland–Hodgman step: the part of a convex polygon on one side of the vertical line `x = limit`.
    private static func clip(_ points: [CGPoint], toX limit: Double, keepAbove: Bool) -> [CGPoint] {
        func inside(_ p: CGPoint) -> Bool { keepAbove ? p.x >= limit : p.x <= limit }
        var out: [CGPoint] = []
        for (index, p) in points.enumerated() {
            let q = points[(index + 1) % points.count]
            if inside(p) { out.append(p) }
            if inside(p) != inside(q) {
                let t = (limit - p.x) / (q.x - p.x)
                out.append(CGPoint(x: limit, y: p.y + t * (q.y - p.y)))
            }
        }
        return out
    }
}
