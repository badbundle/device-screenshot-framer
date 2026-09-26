import CoreGraphics
import Foundation

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

        public var center: CGPoint { CGPoint(x: titleRect.midX, y: titleRect.minY + height / 2) }
    }

    /// Title and subtitle rects for one page whose left edge is at `originX`. `shift` moves the block from its edge
    /// towards the middle of the page.
    public static func textBlock(
        canvas: PixelSize,
        padding: Double,
        spacing: Double,
        titleHeight: Double,
        subtitleHeight: Double,
        position: TextPosition,
        originX: Double = 0,
        shift: Double = 0
    ) -> TextBlock {
        let spacing = (titleHeight > 0 && subtitleHeight > 0) ? spacing : 0
        let height = titleHeight + spacing + subtitleHeight
        let width = Double(canvas.width) - 2 * padding
        let y: Double
        switch position {
        case .top:
            y = padding + shift
        case .bottom:
            y = Double(canvas.height) - padding - height - shift
        }
        return TextBlock(
            titleRect: CGRect(x: originX + padding, y: y, width: width, height: titleHeight),
            subtitleRect: CGRect(x: originX + padding, y: y + titleHeight + spacing, width: width, height: subtitleHeight),
            height: height
        )
    }

    /// Tilt for the text on the page whose left edge is at `originX`, following the nearest part of `content` straight
    /// below (or above) the text's centre: half that content's tilt from level, at most `maxRotation` degrees either
    /// way. 0 if nothing is there.
    public static func textRotation(
        canvas: PixelSize,
        position: TextPosition,
        content: [PlacedRect],
        maxRotation: Double,
        originX: Double = 0
    ) -> Double {
        let centerX = originX + Double(canvas.width) / 2
        let crossing = content.compactMap { item in item.verticalExtent(within: centerX...centerX).map { (item, $0) } }
        let nearest: PlacedRect?
        switch position {
        case .top: nearest = crossing.min { $0.1.lowerBound < $1.1.lowerBound }?.0
        case .bottom: nearest = crossing.max { $0.1.upperBound < $1.1.upperBound }?.0
        }
        guard let rotation = nearest?.rotation else { return 0 }
        // A device turned 90° has level edges too.
        let tilt = rotation - 90 * (rotation / 90).rounded()
        return min(max(tilt / 2, -maxRotation), maxRotation)
    }

    /// Where a text block of `size`, centred across the page whose left edge is at `originX` and turned `rotation`
    /// degrees clockwise, starts: at its edge of the page, its bounding box `padding` in.
    public static func textFootprint(
        size: CGSize,
        rotation: Double,
        canvas: PixelSize,
        padding: Double,
        position: TextPosition,
        originX: Double = 0
    ) -> PlacedRect {
        let angle = rotation * .pi / 180
        let boundsHeight = size.width * abs(sin(angle)) + size.height * cos(angle)
        let centerY: Double
        switch position {
        case .top: centerY = padding + boundsHeight / 2
        case .bottom: centerY = Double(canvas.height) - padding - boundsHeight / 2
        }
        let centerX = originX + Double(canvas.width) / 2
        return PlacedRect(
            rect: CGRect(x: centerX - size.width / 2, y: centerY - size.height / 2, width: size.width, height: size.height),
            rotation: rotation
        )
    }

    /// How far `footprint` can move from its edge towards the middle of the page before it comes within `gap` of any of
    /// `content`. Negative if it already is. `nil` if nothing is in the way.
    public static func textTravel(_ footprint: PlacedRect, gap: Double, position: TextPosition, content: [PlacedRect]) -> Double? {
        let padded = PlacedRect(rect: footprint.rect.insetBy(dx: -gap, dy: -gap), rotation: footprint.rotation)
        return content.compactMap { padded.verticalClearance(to: $0, downward: position == .top) }.min()
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
