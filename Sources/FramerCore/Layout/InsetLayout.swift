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

        public init(
            canvas: PixelSize,
            padding: Double,
            gap: Double,
            spacing: Double,
            titleHeight: Double,
            subtitleHeight: Double,
            framedSize: PixelSize,
            position: TextPosition,
            deviceScale: Double = 1
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
        }
    }

    public static func compute(_ input: Input) throws -> InsetLayout {
        let cw = Double(input.canvas.width)
        let ch = Double(input.canvas.height)
        let p = input.padding
        let textWidth = cw - 2 * p

        let hT = input.titleHeight
        let hS = input.subtitleHeight
        let spacing = (hT > 0 && hS > 0) ? input.spacing : 0
        let hText = hT + spacing + hS
        // No text at all: no gap either.
        let gap = hText > 0 ? input.gap : 0

        let textY: Double
        let area: CGRect
        switch input.position {
        case .top:
            textY = p
            area = CGRect(x: p, y: p + hText + gap, width: textWidth, height: ch - 2 * p - hText - gap)
        case .bottom:
            textY = ch - p - hText
            area = CGRect(x: p, y: p, width: textWidth, height: ch - 2 * p - hText - gap)
        }

        // CGRect.height is an absolute value; check the raw size so a negative area is caught.
        guard area.size.width > 0, area.size.height > 0 else { throw FramerError.textTooTall }

        let fw = Double(input.framedSize.width)
        let fh = Double(input.framedSize.height)
        let scale = min(area.width / fw, area.height / fh) * max(input.deviceScale, 0.01)
        let dw = (fw * scale).rounded()
        let dh = (fh * scale).rounded()
        let dx = (area.midX - dw / 2).rounded()
        let dy: Double
        switch input.position {
        case .top:
            dy = (area.maxY - dh).rounded()
        case .bottom:
            dy = area.minY.rounded()
        }

        return InsetLayout(
            titleRect: CGRect(x: p, y: textY, width: textWidth, height: hT),
            subtitleRect: CGRect(x: p, y: textY + hT + spacing, width: textWidth, height: hS),
            deviceRect: CGRect(x: dx, y: dy, width: dw, height: dh)
        )
    }
}
