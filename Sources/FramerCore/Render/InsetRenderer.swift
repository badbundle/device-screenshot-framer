import CoreGraphics

/// Inset mode: gradient background, title/subtitle at top or bottom, framed device in the remaining space.
public enum InsetRenderer {
    public struct Text: Sendable, Hashable {
        public var title: String
        public var subtitle: String
        public var titleStyle: TextStyle
        public var subtitleStyle: TextStyle
        public var position: TextPosition
        /// Gap between title and subtitle.
        public var spacing: Double

        public init(
            title: String,
            subtitle: String = "",
            titleStyle: TextStyle,
            subtitleStyle: TextStyle,
            position: TextPosition,
            spacing: Double
        ) {
            self.title = title
            self.subtitle = subtitle
            self.titleStyle = titleStyle
            self.subtitleStyle = subtitleStyle
            self.position = position
            self.spacing = spacing
        }
    }

    public struct Style: Sendable, Hashable {
        public var padding: Double
        public var gap: Double
        public var deviceScale: Double

        public init(padding: Double, gap: Double, deviceScale: Double = 1) {
            self.padding = padding
            self.gap = gap
            self.deviceScale = deviceScale
        }
    }

    public static func render(
        framed: CGImage,
        canvas: PixelSize,
        background: GradientSpec,
        text: Text,
        style: Style
    ) throws -> CGImage {
        let textWidth = Double(canvas.width) - 2 * style.padding
        let layout = try InsetLayout.compute(InsetLayout.Input(
            canvas: canvas,
            padding: style.padding,
            gap: style.gap,
            spacing: text.spacing,
            titleHeight: TextRenderer.measureHeight(text.title, style: text.titleStyle, width: textWidth),
            subtitleHeight: TextRenderer.measureHeight(text.subtitle, style: text.subtitleStyle, width: textWidth),
            framedSize: framed.pixelSize,
            position: text.position,
            deviceScale: style.deviceScale
        ))

        let ctx = CGContext.makeCanvas(size: canvas)
        background.fill(ctx, rectTL: CGRect(origin: .zero, size: canvas.cgSize))
        TextRenderer.draw(text.title, style: text.titleStyle, in: layout.titleRect, ctx: ctx)
        TextRenderer.draw(text.subtitle, style: text.subtitleStyle, in: layout.subtitleRect, ctx: ctx)
        ctx.draw(framed, inTopLeft: layout.deviceRect)
        return ctx.makeImage()!
    }
}
