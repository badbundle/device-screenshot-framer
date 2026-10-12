/// How a screenshot is shown: in an Apple device frame, or as a Mac window.
public enum FrameStyle: String, Sendable, Codable, CaseIterable {
    /// In the frame of the device its pixel size matches, or the one forced with `device`.
    case device
    /// As a frameless Mac window: rounded corners and a hairline border, casting a shadow in inset mode. Any size.
    case window
}

/// What a screenshot shown as a window looks like. Sizes are in the screenshot's own pixels.
public struct WindowStyle: Sendable, Hashable {
    /// Corner radius. The default is about a macOS 26 window's, captured at 2×.
    public var cornerRadius: Double
    /// Hairline drawn just inside the edge. `0` for none.
    public var borderWidth: Double
    public var borderColor: RGBAColor

    public init(
        cornerRadius: Double = 36,
        borderWidth: Double = 2,
        borderColor: RGBAColor = RGBAColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 89 / 255)
    ) {
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
    }
}
