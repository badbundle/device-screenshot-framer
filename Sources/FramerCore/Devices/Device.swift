/// A device we know how to frame.
public struct Device: Sendable, Hashable {
    /// Canonical name, e.g. "iPhone 17 Pro". Also accepted (case-insensitively) as a `--device` value.
    public let name: String
    /// Other devices that share `screenSize` and render acceptably with this frame. Display only.
    public let aliases: [String]
    /// Native screenshot size in pixels, in the orientation the frame is drawn in: portrait for iPhone and iPad,
    /// landscape for Mac.
    public let screenSize: PixelSize
    /// Screen corner radius in native pixels. 0 for square-cornered screens.
    public let cornerRadius: Double
    /// When several devices share `screenSize`, the highest priority is auto-detected.
    public let priority: Int
    /// Frame file prefix, e.g. "Apple iPhone 17 Pro". Filename = "\(framePrefix) \(color)\(frameSuffix).png".
    public let framePrefix: String
    /// Usually empty; " Portrait" for the iPad Air 2020 frames.
    public let frameSuffix: String
    /// Native screen size of the device the frame was made for. `nil` means the frame is this device's own.
    /// Set when borrowing a frame for a device frameit-frames does not cover.
    public let frameScreenSize: PixelSize?
    /// Colours available upstream (informational; FrameStore validates against the live manifest).
    public let colors: [String]
    public let defaultColor: String
    /// How the frame image is drawn. iPhones and iPads are portrait and turn for landscape screenshots; Macs don't turn.
    public let frameOrientation: Orientation

    public init(
        name: String,
        aliases: [String] = [],
        screenSize: PixelSize,
        cornerRadius: Double,
        priority: Int,
        framePrefix: String,
        frameSuffix: String = "",
        frameScreenSize: PixelSize? = nil,
        colors: [String],
        defaultColor: String,
        frameOrientation: Orientation = .portrait
    ) {
        self.name = name
        self.aliases = aliases
        self.screenSize = screenSize
        self.cornerRadius = cornerRadius
        self.priority = priority
        self.framePrefix = framePrefix
        self.frameSuffix = frameSuffix
        self.frameScreenSize = frameScreenSize
        self.colors = colors
        self.defaultColor = defaultColor
        self.frameOrientation = frameOrientation
    }

    /// Screen size the frame's cutout was drawn for.
    public var effectiveFrameScreenSize: PixelSize { frameScreenSize ?? screenSize }

    /// True when this device uses another device's frame (aspect-fill may crop slightly).
    public var usesBorrowedFrame: Bool { frameScreenSize != nil }

    public var isIPad: Bool { name.hasPrefix("iPad") }

    public var isMac: Bool { name.hasPrefix("MacBook") }

    /// Whether a screenshot in the other orientation turns the frame. Only portrait frames do.
    public var canRotate: Bool { frameOrientation == .portrait }

    public func frameFilename(color: String) -> String {
        "\(framePrefix) \(color)\(frameSuffix).png"
    }
}
