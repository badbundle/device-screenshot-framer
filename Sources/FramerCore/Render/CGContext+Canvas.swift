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

    /// Fills `rectTL` (top-left coordinates) with a solid colour.
    func fill(_ rectTL: CGRect, color: RGBAColor) {
        saveGState()
        setFillColor(color.cgColor)
        fill(rectTL.flipped(in: Double(height)))
        restoreGState()
    }
}

extension CGImage {
    var pixelSize: PixelSize { PixelSize(width: width, height: height) }
}
