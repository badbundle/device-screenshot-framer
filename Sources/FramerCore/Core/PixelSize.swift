import CoreGraphics

/// An integer pixel size.
public struct PixelSize: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public init(_ width: Int, _ height: Int) {
        self.init(width: width, height: height)
    }

    /// Same size with width and height exchanged.
    public var swapped: PixelSize { PixelSize(width: height, height: width) }

    /// width / height
    public var aspect: Double { Double(width) / Double(height) }

    public var cgSize: CGSize { CGSize(width: width, height: height) }

    public var isLandscape: Bool { width > height }
}

extension PixelSize: CustomStringConvertible {
    public var description: String { "\(width)x\(height)" }
}
