import CoreGraphics

/// Puts a screenshot into a device frame at the frame's native pixel size.
public enum FrameCompositor {
    public struct Input {
        public var screenshot: CGImage
        public var frame: CGImage
        public var geometry: OrientedGeometry
        /// Screen corner radius in cutout pixels (before any fill scaling).
        public var cornerRadius: Double

        public init(screenshot: CGImage, frame: CGImage, geometry: OrientedGeometry, cornerRadius: Double) {
            self.screenshot = screenshot
            self.frame = frame
            self.geometry = geometry
            self.cornerRadius = cornerRadius
        }
    }

    /// Returns the framed image. Transparent outside the device body.
    public static func composite(_ input: Input) -> CGImage {
        let geometry = input.geometry
        let canvasHeight = Double(geometry.canvasSize.height)
        let ctx = CGContext.makeCanvas(size: geometry.canvasSize)

        // Screenshot: aspect-fill into the cutout, clipped to the rounded screen shape.
        let fill = FrameGeometry.aspectFill(content: input.screenshot.pixelSize, into: geometry.cutout)
        let radius = input.cornerRadius * fill.scale
        ctx.saveGState()
        let clip = CGPath(
            roundedRect: geometry.cutout.flipped(in: canvasHeight),
            cornerWidth: min(radius, geometry.cutout.width / 2),
            cornerHeight: min(radius, geometry.cutout.height / 2),
            transform: nil
        )
        ctx.addPath(clip)
        ctx.clip()
        ctx.draw(input.screenshot, in: fill.rect.flipped(in: canvasHeight))
        ctx.restoreGState()

        // Frame on top so the notch / Dynamic Island covers the screenshot.
        ctx.saveGState()
        ctx.concatenate(geometry.frameTransform)
        ctx.draw(input.frame, in: geometry.frameDrawRect)
        ctx.restoreGState()

        return ctx.makeImage()!
    }
}
