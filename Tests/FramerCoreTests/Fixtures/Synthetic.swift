import CoreGraphics
import Foundation
import Testing
@testable import FramerCore

struct RGBA: Equatable, CustomStringConvertible {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    var description: String { "(\(r),\(g),\(b),\(a))" }

    static let red = RGBA(r: 255, g: 0, b: 0, a: 255)
    static let green = RGBA(r: 0, g: 255, b: 0, a: 255)
    static let blue = RGBA(r: 0, g: 0, b: 255, a: 255)
    static let gray = RGBA(r: 128, g: 128, b: 128, a: 255)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    func isClose(to other: RGBA, tolerance: Int = 3) -> Bool {
        abs(Int(r) - Int(other.r)) <= tolerance
            && abs(Int(g) - Int(other.g)) <= tolerance
            && abs(Int(b) - Int(other.b)) <= tolerance
            && abs(Int(a) - Int(other.a)) <= tolerance
    }
}

enum Synthetic {
    /// Portrait screenshot: red fill, blue 8px squares in the corners, green 20px square top-centre (orientation marker).
    static func screenshot(size: PixelSize, fill: RGBAColor = RGBAColor(red: 1, green: 0, blue: 0)) -> CGImage {
        let ctx = CGContext.makeCanvas(size: size)
        let h = Double(size.height)
        ctx.fill(CGRect(origin: .zero, size: size.cgSize), color: fill)
        let blue = RGBAColor(red: 0, green: 0, blue: 1)
        let m = 8.0
        for rect in [
            CGRect(x: 0, y: 0, width: m, height: m),
            CGRect(x: Double(size.width) - m, y: 0, width: m, height: m),
            CGRect(x: 0, y: h - m, width: m, height: m),
            CGRect(x: Double(size.width) - m, y: h - m, width: m, height: m),
        ] {
            ctx.fill(rect, color: blue)
        }
        ctx.fill(CGRect(x: Double(size.width) / 2 - 10, y: 0, width: 20, height: 20), color: RGBAColor(red: 0, green: 1, blue: 0))
        return ctx.makeImage()!
    }

    /// A fake portrait frame: 300x600 opaque gray rounded body, transparent rounded cutout at (30,40) 240x520,
    /// black "island" inside the cutout top-centre. Everything outside the body is transparent.
    static let frameSize = PixelSize(300, 600)
    static let frameOffset = FrameOffset(x: 30, y: 40, width: 240)
    static let cutout = CGRect(x: 30, y: 40, width: 240, height: 520)
    static let island = CGRect(x: 120, y: 50, width: 60, height: 16)
    static let device = Device(
        name: "Test Phone", screenSize: PixelSize(240, 520), cornerRadius: 20, priority: 1,
        framePrefix: "Apple Test Phone", colors: ["Gray"], defaultColor: "Gray"
    )

    static func frame() -> CGImage {
        let ctx = CGContext.makeCanvas(size: frameSize)
        let h = Double(frameSize.height)
        let body = CGRect(x: 5, y: 5, width: 290, height: 590).flipped(in: h)
        ctx.setFillColor(RGBAColor(red: 0.5, green: 0.5, blue: 0.5).cgColor)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: 40, cornerHeight: 40, transform: nil))
        ctx.fillPath()
        // Cut the screen out of the body. Square, so an unclipped screenshot corner would show through —
        // the compositor's rounded clip is what keeps the corners clean.
        ctx.clear(cutout.flipped(in: h))
        ctx.fill(island, color: .black)
        return ctx.makeImage()!
    }

    static func portraitGeometry() -> OrientedGeometry {
        FrameGeometry.oriented(frameSize: frameSize, cutout: cutout, orientation: .portrait, side: .left)
    }

    static func framed(orientation: Orientation = .portrait, side: LandscapeSide = .left, screenshotSize: PixelSize? = nil) -> CGImage {
        let geometry = FrameGeometry.oriented(frameSize: frameSize, cutout: cutout, orientation: orientation, side: side)
        let shotSize = screenshotSize ?? (orientation == .portrait ? device.screenSize : device.screenSize.swapped)
        return FrameCompositor.composite(FrameCompositor.Input(
            screenshot: screenshot(size: shotSize),
            frame: frame(),
            geometry: geometry,
            cornerRadius: device.cornerRadius
        ))
    }

    static func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("framer-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Straight (un-premultiplied) RGBA8 copy of an image, indexed in top-left coordinates.
struct Bitmap {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        bytes = buffer
    }

    subscript(_ x: Int, _ y: Int) -> RGBA {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel (\(x),\(y)) out of \(width)x\(height)")
        // Row 0 of the buffer is the top of the image.
        let i = (y * width + x) * 4
        let a = bytes[i + 3]
        guard a > 0 else { return .clear }
        func un(_ v: UInt8) -> UInt8 { UInt8(min(255, Int(v) * 255 / Int(a))) }
        return RGBA(r: un(bytes[i]), g: un(bytes[i + 1]), b: un(bytes[i + 2]), a: a)
    }

    func expect(_ x: Int, _ y: Int, _ expected: RGBA, tolerance: Int = 3, sourceLocation: SourceLocation = #_sourceLocation) {
        let actual = self[x, y]
        #expect(actual.isClose(to: expected, tolerance: tolerance), "pixel (\(x),\(y)) = \(actual), expected \(expected)", sourceLocation: sourceLocation)
    }
}
