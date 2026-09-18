import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum OutputFormat: String, Sendable, Codable, CaseIterable {
    case png
    case jpeg

    public var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    var utType: UTType { self == .png ? .png : .jpeg }
}

public enum ImageWriter {
    /// Writes `image` to `url`, creating parent directories. JPEG output is flattened onto white.
    public static func write(_ image: CGImage, to url: URL, format: OutputFormat, jpegQuality: Double = 0.9) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let output = format == .jpeg ? flatten(image, onto: .white) : image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw FramerError.write(url)
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(jpegQuality, 0), 1)
        }
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FramerError.write(url)
        }
    }

    /// Composites `image` over a solid colour, dropping alpha.
    static func flatten(_ image: CGImage, onto color: RGBAColor) -> CGImage {
        let bounds = CGRect(origin: .zero, size: image.pixelSize.cgSize)
        // noneSkipLast so the encoder sees an opaque image.
        let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace.sRGBSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.setFillColor(color.cgColor)
        ctx.fill(bounds)
        ctx.draw(image, in: bounds)
        return ctx.makeImage()!
    }
}
