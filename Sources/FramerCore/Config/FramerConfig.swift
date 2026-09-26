import CoreGraphics
import Foundation

public enum RenderMode: String, Sendable, Codable, CaseIterable {
    case simple
    case inset
}

/// JSON config for `framer render`. Every field except `screenshots` has a default so that
/// `{ "screenshots": [{ "path": "a.png" }] }` is a complete config.
public struct FramerConfig: Sendable, Codable, Equatable {
    public var outputDirectory: String
    public var output: OutputConfig
    public var mode: RenderMode
    public var device: String?
    public var frameColor: String?
    public var landscapeSide: LandscapeSide
    public var background: BackgroundConfig?
    public var text: TextConfig
    /// Edge padding in pixels (inset mode). Default: 5% of canvas width.
    public var padding: Double?
    /// Gap between text block and device in pixels (inset mode). Default: same as padding.
    public var gap: Double?
    public var deviceScale: Double
    /// Inset mode, automatic layout: size the device by width and let it run off the edge opposite the text.
    public var bleed: Bool
    /// Inset mode: drop shadow under devices and callout cards. JSON accepts `true` for the defaults.
    public var shadow: ShadowConfig?
    public var screenshots: [ScreenshotEntry]

    public init(
        outputDirectory: String = "framed",
        output: OutputConfig = OutputConfig(),
        mode: RenderMode = .simple,
        device: String? = nil,
        frameColor: String? = nil,
        landscapeSide: LandscapeSide = .left,
        background: BackgroundConfig? = nil,
        text: TextConfig = TextConfig(),
        padding: Double? = nil,
        gap: Double? = nil,
        deviceScale: Double = 1,
        bleed: Bool = false,
        shadow: ShadowConfig? = nil,
        screenshots: [ScreenshotEntry] = []
    ) {
        self.outputDirectory = outputDirectory
        self.output = output
        self.mode = mode
        self.device = device
        self.frameColor = frameColor
        self.landscapeSide = landscapeSide
        self.background = background
        self.text = text
        self.padding = padding
        self.gap = gap
        self.deviceScale = deviceScale
        self.bleed = bleed
        self.shadow = shadow
        self.screenshots = screenshots
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outputDirectory = try c.decodeIfPresent(String.self, forKey: .outputDirectory) ?? "framed"
        output = try c.decodeIfPresent(OutputConfig.self, forKey: .output) ?? OutputConfig()
        mode = try c.decodeIfPresent(RenderMode.self, forKey: .mode) ?? .simple
        device = try c.decodeIfPresent(String.self, forKey: .device)
        frameColor = try c.decodeIfPresent(String.self, forKey: .frameColor)
        landscapeSide = try c.decodeIfPresent(LandscapeSide.self, forKey: .landscapeSide) ?? .left
        background = try c.decodeIfPresent(BackgroundConfig.self, forKey: .background)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? TextConfig()
        padding = try c.decodeIfPresent(Double.self, forKey: .padding)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap)
        deviceScale = try c.decodeIfPresent(Double.self, forKey: .deviceScale) ?? 1
        bleed = try c.decodeIfPresent(Bool.self, forKey: .bleed) ?? false
        if let enabled = try? c.decodeIfPresent(Bool.self, forKey: .shadow) {
            shadow = enabled ? ShadowConfig() : nil
        } else {
            shadow = try c.decodeIfPresent(ShadowConfig.self, forKey: .shadow)
        }
        screenshots = try c.decodeIfPresent([ScreenshotEntry].self, forKey: .screenshots) ?? []
    }
}

public struct OutputConfig: Sendable, Codable, Equatable {
    public var width: Int?
    public var height: Int?
    public var format: OutputFormat
    public var jpegQuality: Double

    public init(width: Int? = nil, height: Int? = nil, format: OutputFormat = .png, jpegQuality: Double = 0.9) {
        self.width = width
        self.height = height
        self.format = format
        self.jpegQuality = jpegQuality
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        format = try c.decodeIfPresent(OutputFormat.self, forKey: .format) ?? .png
        jpegQuality = try c.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? 0.9
    }
}

public struct BackgroundConfig: Sendable, Codable, Equatable {
    public var colors: [RGBAColor]
    public var angle: Double
    public var locations: [Double]?

    public init(colors: [RGBAColor], angle: Double = 180, locations: [Double]? = nil) {
        self.colors = colors
        self.angle = angle
        self.locations = locations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colors = try c.decode([RGBAColor].self, forKey: .colors)
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 180
        locations = try c.decodeIfPresent([Double].self, forKey: .locations)
    }

    public var gradient: GradientSpec {
        GradientSpec(colors: colors, angleDegrees: angle, locations: locations)
    }
}

public struct ShadowConfig: Sendable, Codable, Equatable {
    public var color: RGBAColor
    /// Blur radius in pixels. Default: 5 % of canvas width.
    public var radius: Double?
    public var offsetX: Double
    /// Pixels, positive = down. Default: 2 % of canvas width.
    public var offsetY: Double?

    public init(color: RGBAColor = ShadowSpec().color, radius: Double? = nil, offsetX: Double = 0, offsetY: Double? = nil) {
        self.color = color
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ShadowConfig()
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? defaults.color
        radius = try c.decodeIfPresent(Double.self, forKey: .radius)
        offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY)
    }

    public var spec: ShadowSpec {
        ShadowSpec(color: color, radius: radius, offsetX: offsetX, offsetY: offsetY)
    }
}

public struct TextConfig: Sendable, Codable, Equatable {
    public var position: TextPosition
    public var title: FontConfig
    public var subtitle: FontConfig
    /// Gap between title and subtitle in pixels. Default: 0.4 × subtitle size.
    public var spacing: Double?

    public init(
        position: TextPosition = .top,
        title: FontConfig = FontConfig(size: 96, weight: .bold, color: .white),
        subtitle: FontConfig = FontConfig(size: 56, weight: .regular, color: RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.8)),
        spacing: Double? = nil
    ) {
        self.position = position
        self.title = title
        self.subtitle = subtitle
        self.spacing = spacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TextConfig()
        position = try c.decodeIfPresent(TextPosition.self, forKey: .position) ?? defaults.position
        title = try c.decodeIfPresent(FontConfig.self, forKey: .title) ?? defaults.title
        subtitle = try c.decodeIfPresent(FontConfig.self, forKey: .subtitle) ?? defaults.subtitle
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing)
    }

    public var resolvedSpacing: Double { spacing ?? (subtitle.size * 0.4).rounded() }
}

public struct FontConfig: Sendable, Codable, Equatable {
    public var font: String?
    public var size: Double
    public var weight: FontWeight?
    public var color: RGBAColor

    public init(font: String? = nil, size: Double, weight: FontWeight? = nil, color: RGBAColor = .white) {
        self.font = font
        self.size = size
        self.weight = weight
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        font = try c.decodeIfPresent(String.self, forKey: .font)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 64
        weight = try c.decodeIfPresent(FontWeight.self, forKey: .weight)
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .white
    }

    public var style: TextStyle {
        TextStyle(font: FontSpec(name: font, size: size, weight: weight), color: color)
    }
}

public struct ScreenshotEntry: Sendable, Codable, Equatable {
    /// Required unless every entry in `devices` has its own `path`. With `devices`, it is the default `path` for them.
    public var path: String?
    public var title: String?
    public var subtitle: String?
    public var device: String?
    public var frameColor: String?
    /// Output file name without extension. Default: input basename.
    public var output: String?
    public var background: BackgroundConfig?
    public var landscapeSide: LandscapeSide?
    public var bleed: Bool?
    /// Inset mode: explicitly placed devices instead of the automatic layout.
    public var devices: [DeviceEntry]?
    /// Inset mode: enlarged copies of parts of a device's screen.
    public var callouts: [CalloutEntry]?
    /// Inset mode: two or more make a panorama, one image per page. Requires `devices`.
    public var pages: [PageEntry]?

    public init(
        path: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        device: String? = nil,
        frameColor: String? = nil,
        output: String? = nil,
        background: BackgroundConfig? = nil,
        landscapeSide: LandscapeSide? = nil,
        bleed: Bool? = nil,
        devices: [DeviceEntry]? = nil,
        callouts: [CalloutEntry]? = nil,
        pages: [PageEntry]? = nil
    ) {
        self.path = path
        self.title = title
        self.subtitle = subtitle
        self.device = device
        self.frameColor = frameColor
        self.output = output
        self.background = background
        self.landscapeSide = landscapeSide
        self.bleed = bleed
        self.devices = devices
        self.callouts = callouts
        self.pages = pages
    }
}

/// A device at an explicit position. `x`, `y` (centre) and `width` are fractions of the page; see `DevicePlacement`.
public struct DeviceEntry: Sendable, Codable, Equatable {
    public var path: String?
    public var x: Double
    public var y: Double
    public var width: Double
    /// Degrees clockwise.
    public var rotation: Double
    public var device: String?
    public var frameColor: String?
    public var landscapeSide: LandscapeSide?

    public init(
        path: String? = nil,
        x: Double = 0.5,
        y: Double = 0.5,
        width: Double = 0.8,
        rotation: Double = 0,
        device: String? = nil,
        frameColor: String? = nil,
        landscapeSide: LandscapeSide? = nil
    ) {
        self.path = path
        self.x = x
        self.y = y
        self.width = width
        self.rotation = rotation
        self.device = device
        self.frameColor = frameColor
        self.landscapeSide = landscapeSide
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DeviceEntry()
        path = try c.decodeIfPresent(String.self, forKey: .path)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? defaults.x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? defaults.y
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? defaults.width
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? defaults.rotation
        device = try c.decodeIfPresent(String.self, forKey: .device)
        frameColor = try c.decodeIfPresent(String.self, forKey: .frameColor)
        landscapeSide = try c.decodeIfPresent(LandscapeSide.self, forKey: .landscapeSide)
    }

    public var placement: DevicePlacement {
        DevicePlacement(x: x, y: y, width: width, rotation: rotation)
    }
}

public struct CalloutEntry: Sendable, Codable, Equatable {
    /// Index into the entry's `devices` (0 for the automatically laid-out device).
    public var device: Int
    public var region: RegionConfig
    public var x: Double?
    public var y: Double?
    public var scale: Double
    public var rotation: Double?
    public var cornerRadius: Double?
    public var borderWidth: Double?
    public var borderColor: RGBAColor
    public var highlight: Bool

    public init(
        device: Int = 0,
        region: RegionConfig,
        x: Double? = nil,
        y: Double? = nil,
        scale: Double = 1.5,
        rotation: Double? = nil,
        cornerRadius: Double? = nil,
        borderWidth: Double? = nil,
        borderColor: RGBAColor = .white,
        highlight: Bool = true
    ) {
        self.device = device
        self.region = region
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.highlight = highlight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        device = try c.decodeIfPresent(Int.self, forKey: .device) ?? 0
        region = try c.decode(RegionConfig.self, forKey: .region)
        x = try c.decodeIfPresent(Double.self, forKey: .x)
        y = try c.decodeIfPresent(Double.self, forKey: .y)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1.5
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius)
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth)
        borderColor = try c.decodeIfPresent(RGBAColor.self, forKey: .borderColor) ?? .white
        highlight = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? true
    }

    public var spec: CalloutSpec {
        CalloutSpec(
            device: device,
            region: region.rect,
            x: x,
            y: y,
            scale: scale,
            rotation: rotation,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            borderColor: borderColor,
            highlight: highlight
        )
    }
}

/// A rectangle in screenshot pixels, top-left origin.
public struct RegionConfig: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct PageEntry: Sendable, Codable, Equatable {
    public var title: String?
    public var subtitle: String?

    public init(title: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}
