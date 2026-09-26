import CoreGraphics

extension CGContext {
    /// A transparent RGBA8 sRGB bitmap context with a bottom-left origin (standard CoreGraphics).
    static func makeCanvas(size: PixelSize) -> CGContext {
        let ctx = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace.sRGBSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Draws `image` into `rectTL` given in top-left coordinates.
    func draw(_ image: CGImage, inTopLeft rectTL: CGRect) {
        draw(image, in: rectTL.flipped(in: Double(height)))
    }

    /// Draws `image` into `placed` (top-left coordinates), rotating it about the rect's centre.
    func draw(_ image: CGImage, placed: PlacedRect) {
        guard placed.rotation != 0 else {
            draw(image, inTopLeft: placed.rect)
            return
        }
        let size = CGSize(width: image.width, height: image.height)
        saveGState()
        concatenate(CGAffineTransform.flipY(height: size.height)
            .concatenating(placed.transform(from: size))
            .concatenating(.flipY(height: Double(height))))
        draw(image, in: CGRect(origin: .zero, size: size))
        restoreGState()
    }

    /// Turns everything drawn after it `degrees` clockwise about `pointTL` (top-left coordinates).
    func rotate(degrees: Double, aboutTopLeft pointTL: CGPoint) {
        let pivot = CGPoint(x: pointTL.x, y: Double(height) - pointTL.y)
        translateBy(x: pivot.x, y: pivot.y)
        rotate(by: -degrees * .pi / 180)
        translateBy(x: -pivot.x, y: -pivot.y)
    }

    /// Fills `rectTL` (top-left coordinates) with a solid colour.
    func fill(_ rectTL: CGRect, color: RGBAColor) {
        saveGState()
        setFillColor(color.cgColor)
        fill(rectTL.flipped(in: Double(height)))
        restoreGState()
    }
}

extension CGAffineTransform {
    /// Converts between top-left and CoreGraphics' bottom-left origin in a space of the given height (its own inverse).
    static func flipY(height: Double) -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
    }
}

extension CGImage {
    var pixelSize: PixelSize { PixelSize(width: width, height: height) }
}
