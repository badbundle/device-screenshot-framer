import Foundation

/// Everything needed to render one screenshot. Pure values, so jobs can cross task boundaries.
public struct RenderJob: Sendable, Hashable {
    public var input: URL
    /// Output file path without extension; the format decides the extension.
    public var outputBase: URL
    public var format: OutputFormat
    public var jpegQuality: Double
    public var mode: RenderMode
    public var deviceName: String?
    public var frameColor: String?
    public var landscapeSide: LandscapeSide
    public var requestedWidth: Int?
    public var requestedHeight: Int?
    public var background: GradientSpec?
    public var inset: InsetSettings?

    public struct InsetSettings: Sendable, Hashable {
        public var title: String
        public var subtitle: String
        public var titleStyle: TextStyle
        public var subtitleStyle: TextStyle
        public var position: TextPosition
        public var spacing: Double
        public var padding: Double?
        public var gap: Double?
        public var deviceScale: Double

        public init(
            title: String,
            subtitle: String,
            titleStyle: TextStyle,
            subtitleStyle: TextStyle,
            position: TextPosition,
            spacing: Double,
            padding: Double?,
            gap: Double?,
            deviceScale: Double
        ) {
            self.title = title
            self.subtitle = subtitle
            self.titleStyle = titleStyle
            self.subtitleStyle = subtitleStyle
            self.position = position
            self.spacing = spacing
            self.padding = padding
            self.gap = gap
            self.deviceScale = deviceScale
        }
    }

    public init(
        input: URL,
        outputBase: URL,
        format: OutputFormat = .png,
        jpegQuality: Double = 0.9,
        mode: RenderMode = .simple,
        deviceName: String? = nil,
        frameColor: String? = nil,
        landscapeSide: LandscapeSide = .left,
        requestedWidth: Int? = nil,
        requestedHeight: Int? = nil,
        background: GradientSpec? = nil,
        inset: InsetSettings? = nil
    ) {
        self.input = input
        self.outputBase = outputBase
        self.format = format
        self.jpegQuality = jpegQuality
        self.mode = mode
        self.deviceName = deviceName
        self.frameColor = frameColor
        self.landscapeSide = landscapeSide
        self.requestedWidth = requestedWidth
        self.requestedHeight = requestedHeight
        self.background = background
        self.inset = inset
    }

    public var outputURL: URL { outputBase.appendingPathExtension(format.fileExtension) }
}
