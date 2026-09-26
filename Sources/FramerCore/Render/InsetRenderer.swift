import CoreGraphics

/// Inset mode: gradient background, title/subtitle at top or bottom, framed devices and callouts.
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
        public var bleed: Bool
        public var shadow: ShadowSpec?

        public init(padding: Double, gap: Double, deviceScale: Double = 1, bleed: Bool = false, shadow: ShadowSpec? = nil) {
            self.padding = padding
            self.gap = gap
            self.deviceScale = deviceScale
            self.bleed = bleed
            self.shadow = shadow
        }
    }

    /// A framed device to draw.
    public struct Layer {
        public var framed: CGImage
        /// `nil` = automatic layout under/over the text (single device, single page only).
        public var placement: DevicePlacement?

        public init(framed: CGImage, placement: DevicePlacement? = nil) {
            self.framed = framed
            self.placement = placement
        }
    }

    public struct Callout {
        public var spec: CalloutSpec
        /// The magnified part of the screenshot.
        public var image: CGImage
        /// Where that part sits in the layer's framed image (see `CalloutLayout.framedRegion`).
        public var region: CGRect

        public init(spec: CalloutSpec, image: CGImage, region: CGRect) {
            self.spec = spec
            self.image = image
            self.region = region
        }
    }

    public static func render(
        framed: CGImage,
        canvas: PixelSize,
        background: GradientSpec,
        text: Text,
        style: Style
    ) throws -> CGImage {
        try render(layers: [Layer(framed: framed)], canvas: canvas, background: background, pages: [text], style: style)[0]
    }

    /// Renders one image per entry in `pages`. With several pages, layers and callouts are laid out on one
    /// continuous canvas `pages.count` pages wide, which is then cut into pages.
    public static func render(
        layers: [Layer],
        callouts: [Callout] = [],
        canvas: PixelSize,
        background: GradientSpec,
        pages: [Text],
        style: Style
    ) throws -> [CGImage] {
        guard !pages.isEmpty else { throw FramerError.config("inset mode needs at least one page") }
        let pageWidth = Double(canvas.width)
        let textWidth = pageWidth - 2 * style.padding
        let blocks = pages.enumerated().map { index, text in
            InsetLayout.textBlock(
                canvas: canvas,
                padding: style.padding,
                spacing: text.spacing,
                titleHeight: TextRenderer.measureHeight(text.title, style: text.titleStyle, width: textWidth),
                subtitleHeight: TextRenderer.measureHeight(text.subtitle, style: text.subtitleStyle, width: textWidth),
                position: text.position,
                originX: Double(index) * pageWidth
            )
        }

        let placed = try layers.map { layer -> PlacedRect in
            if let placement = layer.placement {
                return placement.resolve(page: canvas, contentSize: layer.framed.pixelSize)
            }
            guard layers.count == 1, pages.count == 1 else {
                throw FramerError.config("with several devices or pages, every device needs a placement")
            }
            let layout = try InsetLayout.compute(InsetLayout.Input(
                canvas: canvas,
                padding: style.padding,
                gap: style.gap,
                spacing: pages[0].spacing,
                titleHeight: blocks[0].titleRect.height,
                subtitleHeight: blocks[0].subtitleRect.height,
                framedSize: layer.framed.pixelSize,
                position: pages[0].position,
                deviceScale: style.deviceScale,
                bleed: style.bleed
            ))
            return PlacedRect(rect: layout.deviceRect)
        }

        let calloutLayouts = try callouts.map { callout -> CalloutLayout.Result in
            guard layers.indices.contains(callout.spec.device) else {
                throw FramerError.config("callout refers to device \(callout.spec.device), but there are only \(layers.count)")
            }
            return CalloutLayout.compute(
                callout.spec,
                region: callout.region,
                device: placed[callout.spec.device],
                framedSize: layers[callout.spec.device].framed.pixelSize,
                page: canvas
            )
        }

        let full = PixelSize(canvas.width * pages.count, canvas.height)
        let ctx = CGContext.makeCanvas(size: full)
        background.fill(ctx, rectTL: CGRect(origin: .zero, size: full.cgSize))

        for (layer, rect) in zip(layers, placed) {
            ctx.saveGState()
            style.shadow?.apply(to: ctx, pageWidth: pageWidth)
            ctx.draw(layer.framed, placed: rect)
            ctx.restoreGState()
        }

        for (callout, layout) in zip(callouts, calloutLayouts) where callout.spec.highlight {
            CalloutRenderer.highlight(
                layout.source,
                lineWidth: max(2, (pageWidth * 0.004).rounded()),
                cornerRadius: callout.spec.resolvedCornerRadius(pageWidth: pageWidth) / callout.spec.scale,
                color: callout.spec.borderColor,
                ctx: ctx
            )
        }

        for (callout, layout) in zip(callouts, calloutLayouts) {
            let size = PixelSize(max(1, Int(layout.card.rect.width)), max(1, Int(layout.card.rect.height)))
            let card = CalloutRenderer.card(
                callout.image,
                size: size,
                cornerRadius: callout.spec.resolvedCornerRadius(pageWidth: pageWidth),
                borderWidth: callout.spec.resolvedBorderWidth(pageWidth: pageWidth),
                borderColor: callout.spec.borderColor
            )
            ctx.saveGState()
            style.shadow?.apply(to: ctx, pageWidth: pageWidth)
            ctx.draw(card, placed: layout.card)
            ctx.restoreGState()
        }

        for (text, block) in zip(pages, blocks) {
            TextRenderer.draw(text.title, style: text.titleStyle, in: block.titleRect, ctx: ctx)
            TextRenderer.draw(text.subtitle, style: text.subtitleStyle, in: block.subtitleRect, ctx: ctx)
        }

        let image = ctx.makeImage()!
        guard pages.count > 1 else { return [image] }
        return pages.indices.map { index in
            image.cropping(to: CGRect(x: index * canvas.width, y: 0, width: canvas.width, height: canvas.height))!
        }
    }
}
