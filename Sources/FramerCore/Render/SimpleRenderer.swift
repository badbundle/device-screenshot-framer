import CoreGraphics

/// Simple mode: framed device aspect-fit and centred on a canvas.
public enum SimpleRenderer {
    public static func render(framed: CGImage, canvas: PixelSize, background: GradientSpec?) -> CGImage {
        let ctx = CGContext.makeCanvas(size: canvas)
        let bounds = CGRect(origin: .zero, size: canvas.cgSize)
        background?.fill(ctx, rectTL: bounds)
        let fit = FrameGeometry.aspectFit(content: framed.pixelSize, into: bounds)
        ctx.draw(framed, inTopLeft: fit.rect)
        return ctx.makeImage()!
    }
}
