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
        /// With placed devices, how far the text may shrink or grow (as a multiple of its size) to fit the room they leave.
        public var textScale: ClosedRange<Double>
        /// With placed devices, the most the text may tilt, in degrees, to follow them.
        public var maxTextRotation: Double

        public init(
            padding: Double,
            gap: Double,
            deviceScale: Double = 1,
            bleed: Bool = false,
            shadow: ShadowSpec? = nil,
            textScale: ClosedRange<Double> = 0.75...1.5,
            maxTextRotation: Double = 4
        ) {
            self.padding = padding
            self.gap = gap
            self.deviceScale = deviceScale
            self.bleed = bleed
            self.shadow = shadow
            self.textScale = textScale
            self.maxTextRotation = maxTextRotation
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
        var pages = pages
        var blocks = pages.enumerated().map { index, text in
            text.block(canvas: canvas, padding: style.padding, originX: Double(index) * pageWidth)
        }
        var rotations = Array(repeating: 0.0, count: pages.count)

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

        if layers.contains(where: { $0.placement != nil }),
           let fitted = fitText(pages, around: placed + calloutLayouts.map(\.card), canvas: canvas, style: style) {
            pages = fitted.map(\.text)
            blocks = fitted.map(\.block)
            rotations = fitted.map(\.rotation)
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

        for (index, (text, block)) in zip(pages, blocks).enumerated() {
            ctx.saveGState()
            if rotations[index] != 0 {
                ctx.rotate(degrees: rotations[index], aboutTopLeft: block.center)
            }
            TextRenderer.draw(text.title, style: text.titleStyle, in: block.titleRect, ctx: ctx)
            TextRenderer.draw(text.subtitle, style: text.subtitleStyle, in: block.subtitleRect, ctx: ctx)
            ctx.restoreGState()
        }

        let image = ctx.makeImage()!
        guard pages.count > 1 else { return [image] }
        return pages.indices.map { index in
            image.cropping(to: CGRect(x: index * canvas.width, y: 0, width: canvas.width, height: canvas.height))!
        }
    }

    /// Text ready to draw: `block` turned `rotation` degrees clockwise about its centre.
    struct FittedText {
        var text: Text
        var block: InsetLayout.TextBlock
        var rotation: Double
    }

    /// Placed devices don't make room for the text, so the text fits itself to them. It tilts a little to follow the
    /// device or card nearest to it, scales within `textScale` (never onto more lines) to fill the room they leave, and
    /// moves towards them until it is `gap` away. Panorama pages share one scale and move the same distance, so their
    /// text lines up across the joins. `nil` leaves the text as it is: when there is none, when nothing is in its way,
    /// or when something is within `gap` of it even at the smallest scale.
    static func fitText(_ pages: [Text], around content: [PlacedRect], canvas: PixelSize, style: Style) -> [FittedText]? {
        let pageWidth = Double(canvas.width)
        let width = pageWidth - 2 * style.padding
        let lineCounts = pages.map { $0.lineWidths(width: width).map(\.count) }
        guard lineCounts.contains(where: { $0 != [0, 0] }) else { return nil }
        let rotations = pages.indices.map { index in
            InsetLayout.textRotation(
                canvas: canvas,
                position: pages[index].position,
                content: content,
                maxRotation: style.maxTextRotation,
                originX: Double(index) * pageWidth
            )
        }

        struct Layout {
            var text: Text
            var footprint: PlacedRect
            /// How far the text can move towards the middle: up to `gap` from the content, or `padding` from the far edge.
            var travel: Double
            var blocked: Bool
        }
        /// Page `index` at `scale`; `nil` if that puts the title or subtitle on more lines.
        func layout(_ index: Int, scale: Double) -> Layout? {
            let text = pages[index].scaled(by: scale)
            let lines = text.lineWidths(width: width)
            guard zip(lines.map(\.count), lineCounts[index]).allSatisfy({ $0 <= $1 }) else { return nil }
            let size = CGSize(width: lines.joined().max() ?? 0, height: text.block(canvas: canvas, padding: style.padding).height)
            let footprint = InsetLayout.textFootprint(
                size: size,
                rotation: rotations[index],
                canvas: canvas,
                padding: style.padding,
                position: text.position,
                originX: Double(index) * pageWidth
            )
            let bounds = footprint.bounds
            let farEdge = text.position == .top ? Double(canvas.height) - style.padding - bounds.maxY : bounds.minY - style.padding
            let travel = InsetLayout.textTravel(footprint, gap: style.gap, position: text.position, content: content)
            return Layout(text: text, footprint: footprint, travel: min(travel ?? farEdge, farEdge), blocked: travel != nil)
        }
        func fits(_ scale: Double) -> Bool {
            pages.indices.allSatisfy { index in (layout(index, scale: scale)?.travel ?? -1) >= 0 }
        }

        var low = min(style.textScale.lowerBound, 1)
        var high = max(style.textScale.upperBound, 1)
        guard fits(low) else { return nil }
        if fits(high) {
            low = high
        } else {
            for _ in 0..<12 {
                let mid = (low + high) / 2
                if fits(mid) { low = mid } else { high = mid }
            }
        }

        let layouts = pages.indices.map { layout($0, scale: low)! }
        guard layouts.contains(where: \.blocked) else { return nil }
        let travel = layouts.map(\.travel).min()!.rounded(.down)
        return layouts.enumerated().map { index, layout in
            // Turned, the block reaches past its own edges; `padding` is measured to its bounding box.
            let overhang = (layout.footprint.bounds.height - layout.footprint.rect.height) / 2
            return FittedText(
                text: layout.text,
                block: layout.text.block(canvas: canvas, padding: style.padding, originX: Double(index) * pageWidth, shift: overhang + travel),
                rotation: rotations[index]
            )
        }
    }
}

extension InsetRenderer.Text {
    /// Title and subtitle sizes and the spacing between them times `scale`, in whole points.
    func scaled(by scale: Double) -> Self {
        guard scale != 1 else { return self }
        var text = self
        text.titleStyle.font.size = (titleStyle.font.size * scale).rounded()
        text.subtitleStyle.font.size = (subtitleStyle.font.size * scale).rounded()
        text.spacing = (spacing * scale).rounded()
        return text
    }

    /// Measures the text and lays it out on the page whose left edge is at `originX`.
    func block(canvas: PixelSize, padding: Double, originX: Double = 0, shift: Double = 0) -> InsetLayout.TextBlock {
        let width = Double(canvas.width) - 2 * padding
        return InsetLayout.textBlock(
            canvas: canvas,
            padding: padding,
            spacing: spacing,
            titleHeight: TextRenderer.measureHeight(title, style: titleStyle, width: width),
            subtitleHeight: TextRenderer.measureHeight(subtitle, style: subtitleStyle, width: width),
            position: position,
            originX: originX,
            shift: shift
        )
    }

    /// Line widths of the title, then the subtitle.
    func lineWidths(width: Double) -> [[Double]] {
        [TextRenderer.lineWidths(title, style: titleStyle, width: width), TextRenderer.lineWidths(subtitle, style: subtitleStyle, width: width)]
    }
}
