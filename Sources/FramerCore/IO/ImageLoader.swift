import CoreGraphics
import Foundation
import ImageIO

public enum ImageLoader {
    /// Loads the first image in the file. Orientation metadata is ignored (screenshots carry none).
    public static func load(_ url: URL) throws -> CGImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else {
            throw FramerError.unsupportedImage(url)
        }
        return image
    }

    /// Reads only the pixel dimensions without decoding the bitmap.
    public static func size(of url: URL) throws -> PixelSize {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else {
            throw FramerError.unsupportedImage(url)
        }
        return PixelSize(width: width, height: height)
    }
}
