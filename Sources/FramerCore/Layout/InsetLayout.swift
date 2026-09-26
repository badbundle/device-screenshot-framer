import CoreGraphics

public enum TextPosition: String, Sendable, Codable, CaseIterable {
    case top
    case bottom
}

/// Pure layout for inset mode. All rects in top-left pixel coordinates.
public struct InsetLayout: Sendable, Equatable {
    public var titleRect: CGRect
    public var subtitleRect: CGRect
    public var deviceRect: CGRect

    public struct Input: Sendable {
        public var canvas: PixelSize
        public var padding: Double
        /// Gap between the text block and the device.
        public var gap: Double
        /// Gap between title and subtitle (ignored when either is empty).
        public var spacing: Double
        public var titleHeight: Double
        public var subtitleHeight: Double
        public var framedSize: PixelSize
        public var position: TextPosition
        /// Extra multiplier on the device size (1 = fill the available area).
        public var deviceScale: Double
        /// Size the device by width and pin it to the text, letting it run off the opposite edge.
        public var bleed: Bool

        public init(
            canvas: PixelSize,
            padding: Double,
            gap: Double,
            spacing: Double,
            titleHeight: Double,
            subtitleHeight: Double,
            framedSize: PixelSize,
            position: TextPosition,
            deviceScale: Double = 1,
            bleed: Bool = false
        ) {
            self.canvas = canvas
            self.padding = padding
            self.gap = gap
            self.spacing = spacing
            self.titleHeight = titleHeight
            self.subtitleHeight = subtitleHeight
            self.framedSize = framedSize
            self.position = position
            self.deviceScale = deviceScale
            self.bleed = bleed
        }
    }

    public struct TextBlock: Sendable, Equatable {
        public var titleRect: CGRect
        public var subtitleRect: CGRect
        /// Title + spacing + subtitle. 0 when there is no text.
        public var height: Double
    }

    /// Title and subtitle rects for one page whose left edge is at `originX`.
    public static func textBlock(
        canvas: PixelSize,
        padding: Double,
        spacing: Double,
        titleHeight: Double,
        subtitleHeight: Double,
        position: TextPosition,
        originX: Double = 0
    ) -> TextBlock {
        let spacing = (titleHeight > 0 && subtitleHeight > 0) ? spacing : 0
        let height = titleHeight + spacing + subtitleHeight
        let width = Double(canvas.width) - 2 * padding
        let y: Double
        switch position {
        case .top:
            y = padding
        case .bottom:
            y = Double(canvas.height) - padding - height
        }
        return TextBlock(
            titleRect: CGRect(x: originX + padding, y: y, width: width, height: titleHeight),
            subtitleRect: CGRect(x: originX + padding, y: y + titleHeight + spacing, width: width, height: subtitleHeight),
            height: height
        )
    }

    public static func compute(_ input: Input) throws -> InsetLayout {
        let cw = Double(input.canvas.width)
        let ch = Double(input.canvas.height)
        let p = input.padding
        let text = textBlock(
            canvas: input.canvas,
            padding: p,
            spacing: input.spacing,
            titleHeight: input.titleHeight,
            subtitleHeight: input.subtitleHeight,
            position: input.position
        )
        // No text at all: no gap either.
        let gap = text.height > 0 ? input.gap : 0

        let area: CGRect
        switch input.position {
        case .top:
            area = CGRect(x: p, y: p + text.height + gap, width: cw - 2 * p, height: ch - 2 * p - text.height - gap)
        case .bottom:
            area = CGRect(x: p, y: p, width: cw - 2 * p, height: ch - 2 * p - text.height - gap)
        }

        // CGRect.height is an absolute value; check the raw size so a negative area is caught.
        guard area.size.width > 0, area.size.height > 0 else { throw FramerError.textTooTall }

        let fw = Double(input.framedSize.width)
        let fh = Double(input.framedSize.height)
        let fitScale = input.bleed ? area.width / fw : min(area.width / fw, area.height / fh)
        let scale = fitScale * max(input.deviceScale, 0.01)
        let dw = (fw * scale).rounded()
        let dh = (fh * scale).rounded()
        let dx = (area.midX - dw / 2).rounded()
        let dy: Double
        switch (input.position, input.bleed) {
        case (.top, false):
            dy = (area.maxY - dh).rounded()
        case (.bottom, false):
            dy = area.minY.rounded()
        case (.top, true):
            dy = area.minY.rounded()
        case (.bottom, true):
            dy = (area.maxY - dh).rounded()
        }

        return InsetLayout(
            titleRect: text.titleRect,
            subtitleRect: text.subtitleRect,
            deviceRect: CGRect(x: dx, y: dy, width: dw, height: dh)
        )
    }
}
