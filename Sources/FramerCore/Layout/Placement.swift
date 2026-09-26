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
