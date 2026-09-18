import CoreGraphics

/// Screen cutout position inside a portrait frame PNG, as stored in frameit's offsets.json.
public struct FrameOffset: Hashable, Sendable {
    public var x: Int
    public var y: Int
    /// Cutout width in frame pixels (equals the frame device's native screenshot width).
    public var width: Int

    public init(x: Int, y: Int, width: Int) {
        self.x = x
        self.y = y
        self.width = width
    }

    /// Parses frameit's `"+72+69"` format.
    public init(offsetString: String, width: Int) throws {
        let parts = offsetString.split(separator: "+", omittingEmptySubsequences: false)
        // "+72+69" splits into ["", "72", "69"].
        guard parts.count == 3, parts[0].isEmpty, let x = Int(parts[1]), let y = Int(parts[2]) else {
            throw FramerError.config("invalid offset '\(offsetString)': expected '+X+Y'")
        }
        self.init(x: x, y: y, width: width)
    }
}

/// Geometry of a frame in its output orientation. All rects are in top-left pixel coordinates.
public struct OrientedGeometry: Sendable {
    /// Size of the framed image (frame pixels, rotated for landscape).
    public var canvasSize: PixelSize
    /// Screen cutout in the oriented canvas.
    public var cutout: CGRect
    /// Transform to apply to a CGContext (y-up) before drawing the *portrait* frame image into `frameDrawRect`.
    public var frameTransform: CGAffineTransform
    /// Rect the portrait frame is drawn into, in the transformed (y-up) space.
    public var frameDrawRect: CGRect
}

public enum FrameGeometry {
    /// Cutout rect in portrait frame space. Height is derived from the frame device's native aspect.
    public static func portraitCutout(offset: FrameOffset, frameScreenSize: PixelSize) -> CGRect {
        let height = (Double(offset.width) * Double(frameScreenSize.height) / Double(frameScreenSize.width)).rounded()
        return CGRect(x: Double(offset.x), y: Double(offset.y), width: Double(offset.width), height: height)
    }

    /// Validates that the cutout lies within the frame image.
    public static func validate(cutout: CGRect, frameSize: PixelSize, filename: String) throws {
        let bounds = CGRect(origin: .zero, size: frameSize.cgSize)
        guard bounds.contains(cutout) else {
            throw FramerError.inconsistentFrame(
                filename: filename,
                detail: "cutout \(Int(cutout.minX)),\(Int(cutout.minY)) \(Int(cutout.width))x\(Int(cutout.height)) exceeds frame \(frameSize)"
            )
        }
    }

    /// Orients a portrait frame for the requested output orientation.
    public static func oriented(
        frameSize: PixelSize,
        cutout: CGRect,
        orientation: Orientation,
        side: LandscapeSide
    ) -> OrientedGeometry {
        let wf = Double(frameSize.width)
        let hf = Double(frameSize.height)
        let portraitDrawRect = CGRect(x: 0, y: 0, width: wf, height: hf)

        switch orientation {
        case .portrait:
            return OrientedGeometry(
                canvasSize: frameSize,
                cutout: cutout,
                frameTransform: .identity,
                frameDrawRect: portraitDrawRect
            )
        case .landscape:
            let canvas = frameSize.swapped
            switch side {
            case .left:
                // 90° CCW. Top-left mapping: (x, y) -> (y, wf - x)
                let rotated = CGRect(
                    x: cutout.minY,
                    y: wf - cutout.maxX,
                    width: cutout.height,
                    height: cutout.width
                )
                // CG (y-up): (x, y) -> (hf - y, x)
                let transform = CGAffineTransform(translationX: hf, y: 0).rotated(by: .pi / 2)
                return OrientedGeometry(canvasSize: canvas, cutout: rotated, frameTransform: transform, frameDrawRect: portraitDrawRect)
            case .right:
                // 90° CW. Top-left mapping: (x, y) -> (hf - y, x)
                let rotated = CGRect(
                    x: hf - cutout.maxY,
                    y: cutout.minX,
                    width: cutout.height,
                    height: cutout.width
                )
                // CG (y-up): (x, y) -> (y, wf - x)
                let transform = CGAffineTransform(translationX: 0, y: wf).rotated(by: -.pi / 2)
                return OrientedGeometry(canvasSize: canvas, cutout: rotated, frameTransform: transform, frameDrawRect: portraitDrawRect)
            }
        }
    }

    /// Scales `content` to completely cover `target`, centred. Sizes are ceiled so coverage is guaranteed.
    public static func aspectFill(content: PixelSize, into target: CGRect) -> (rect: CGRect, scale: Double) {
        let scale = max(target.width / Double(content.width), target.height / Double(content.height))
        let w = (Double(content.width) * scale).rounded(.up)
        let h = (Double(content.height) * scale).rounded(.up)
        let rect = CGRect(
            x: (target.midX - w / 2).rounded(),
            y: (target.midY - h / 2).rounded(),
            width: w,
            height: h
        )
        return (rect, scale)
    }

    /// Scales `content` to fit entirely inside `target`, centred.
    public static func aspectFit(content: PixelSize, into target: CGRect) -> (rect: CGRect, scale: Double) {
        let scale = min(target.width / Double(content.width), target.height / Double(content.height))
        let w = (Double(content.width) * scale).rounded()
        let h = (Double(content.height) * scale).rounded()
        let rect = CGRect(
            x: (target.midX - w / 2).rounded(),
            y: (target.midY - h / 2).rounded(),
            width: w,
            height: h
        )
        return (rect, scale)
    }
}

extension CGRect {
    /// Converts a top-left-origin rect to CoreGraphics' bottom-left origin for a canvas of height `height`.
    public func flipped(in height: Double) -> CGRect {
        CGRect(x: minX, y: height - maxY, width: width, height: self.height)
    }
}
