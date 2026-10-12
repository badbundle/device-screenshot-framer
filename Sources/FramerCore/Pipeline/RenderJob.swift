import Foundation

/// Everything needed to render one screenshot. Pure values, so jobs can cross task boundaries.
public struct RenderJob: Sendable, Hashable {
    public var input: URL
    /// Output file path without extension; the format decides the extension.
    public var outputBase: URL
    public var format: OutputFormat
    public var jpegQuality: Double
    public var mode: RenderMode
    /// Device frame or Mac window, for the job's `input` and any placed device that doesn't set its own.
    public var frameStyle: FrameStyle
    /// How every window in the job looks.
    public var window: WindowStyle
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
        /// Part of `title` drawn in `accentColor`. Empty for none.
        public var accent: String
        public var titleStyle: TextStyle
        public var subtitleStyle: TextStyle
        public var position: TextPosition
        public var spacing: Double
        public var padding: Double?
        public var gap: Double?
        public var deviceScale: Double
        /// Automatic layout only: size the device by width and let it run off the edge opposite the text.
        public var bleed: Bool
        public var shadow: ShadowSpec?
        /// With `devices`, how far the text may shrink or grow, as a multiple of its size.
        public var textScale: ClosedRange<Double>
        /// With `devices`, the most the text may tilt, in degrees.
        public var maxTextRotation: Double
        /// With `devices`, whether the text moves towards them or stays at its edge.
        public var textAnchor: TextAnchor
        public var accentColor: RGBAColor
        /// Drawn over the background gradient, under the devices.
        public var glows: [GlowSpec]
        public var backgroundImages: [BackgroundImageSpec]
        /// Explicitly placed devices, drawn in order. Empty = the job's `input` laid out automatically.
        public var devices: [PlacedDevice]
        public var callouts: [CalloutSpec]
        /// Two or more pages make a panorama: one canvas cut into `pages.count` images. `title` and `subtitle` are
        /// ignored when `pages` is non-empty.
        public var pages: [Page]

        public init(
            title: String,
            subtitle: String,
            titleStyle: TextStyle,
            subtitleStyle: TextStyle,
            position: TextPosition,
            spacing: Double,
            padding: Double?,
            gap: Double?,
            deviceScale: Double,
            bleed: Bool = false,
            shadow: ShadowSpec? = nil,
            textScale: ClosedRange<Double> = 0.75...1.5,
            maxTextRotation: Double = 4,
            devices: [PlacedDevice] = [],
            callouts: [CalloutSpec] = [],
            pages: [Page] = [],
            accent: String = "",
            accentColor: RGBAColor = TextConfig.defaultAccentColor,
            textAnchor: TextAnchor = .devices,
            glows: [GlowSpec] = [],
            backgroundImages: [BackgroundImageSpec] = []
        ) {
            self.title = title
            self.subtitle = subtitle
            self.accent = accent
            self.accentColor = accentColor
            self.textAnchor = textAnchor
            self.glows = glows
            self.backgroundImages = backgroundImages
            self.titleStyle = titleStyle
            self.subtitleStyle = subtitleStyle
            self.position = position
            self.spacing = spacing
            self.padding = padding
            self.gap = gap
            self.deviceScale = deviceScale
            self.bleed = bleed
            self.shadow = shadow
            self.textScale = textScale
            self.maxTextRotation = maxTextRotation
            self.devices = devices
            self.callouts = callouts
            self.pages = pages
        }

        var resolvedPages: [Page] { pages.isEmpty ? [Page(title: title, subtitle: subtitle, accent: accent)] : pages }
    }

    /// One screenshot in a device frame, or as a window, at an explicit position.
    public struct PlacedDevice: Sendable, Hashable {
        public var input: URL
        public var frameStyle: FrameStyle
        public var deviceName: String?
        public var frameColor: String?
        public var landscapeSide: LandscapeSide
        public var placement: DevicePlacement

        public init(
            input: URL,
            frameStyle: FrameStyle = .device,
            deviceName: String? = nil,
            frameColor: String? = nil,
            landscapeSide: LandscapeSide = .left,
            placement: DevicePlacement
        ) {
            self.input = input
            self.frameStyle = frameStyle
            self.deviceName = deviceName
            self.frameColor = frameColor
            self.landscapeSide = landscapeSide
            self.placement = placement
        }
    }

    public struct Page: Sendable, Hashable {
        public var title: String
        public var subtitle: String
        /// Part of `title` drawn in the accent colour. Empty for none.
        public var accent: String

        public init(title: String = "", subtitle: String = "", accent: String = "") {
            self.title = title
            self.subtitle = subtitle
            self.accent = accent
        }
    }

    public init(
        input: URL,
        outputBase: URL,
        format: OutputFormat = .png,
        jpegQuality: Double = 0.9,
        mode: RenderMode = .simple,
        frameStyle: FrameStyle = .device,
        window: WindowStyle = WindowStyle(),
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
        self.frameStyle = frameStyle
        self.window = window
        self.deviceName = deviceName
        self.frameColor = frameColor
        self.landscapeSide = landscapeSide
        self.requestedWidth = requestedWidth
        self.requestedHeight = requestedHeight
        self.background = background
        self.inset = inset
    }

    public var outputURL: URL { outputBase.appendingPathExtension(format.fileExtension) }

    /// One file per page: `outputURL` for a single page, `<outputBase>-1`, `-2`, … for a panorama.
    public var outputURLs: [URL] {
        let pageCount = mode == .inset ? inset?.pages.count ?? 0 : 0
        guard pageCount > 1 else { return [outputURL] }
        return (1...pageCount).map { page in
            outputBase.deletingLastPathComponent()
                .appendingPathComponent("\(outputBase.lastPathComponent)-\(page)")
                .appendingPathExtension(format.fileExtension)
        }
    }

    typealias Source = (input: URL, frameStyle: FrameStyle, deviceName: String?, frameColor: String?, landscapeSide: LandscapeSide)

    /// The screenshots this job frames, in drawing order.
    var sources: [Source] {
        guard mode == .inset, let devices = inset?.devices, !devices.isEmpty else {
            return [(input, frameStyle, deviceName, frameColor, landscapeSide)]
        }
        return devices.map { ($0.input, $0.frameStyle, $0.deviceName, $0.frameColor, $0.landscapeSide) }
    }

    /// Whether any screenshot goes in a device frame, so the frames manifest is needed.
    var needsFrames: Bool { sources.contains { $0.frameStyle == .device } }
}
