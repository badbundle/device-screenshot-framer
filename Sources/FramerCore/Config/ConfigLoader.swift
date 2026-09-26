import Foundation

public enum ConfigLoader {
    public static func load(_ url: URL) throws -> FramerConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw FramerError.config("could not read '\(url.path)': \(error.localizedDescription)")
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> FramerConfig {
        do {
            return try JSONDecoder().decode(FramerConfig.self, from: data)
        } catch let error as DecodingError {
            throw FramerError.config(describe(error))
        }
    }

    /// Expands config entries into jobs. Relative paths resolve against `baseDirectory` (the config's directory).
    /// `outputDirectoryOverride` replaces the config's output directory.
    public static func jobs(
        from config: FramerConfig,
        baseDirectory: URL,
        outputDirectoryOverride: URL? = nil
    ) throws -> [RenderJob] {
        guard !config.screenshots.isEmpty else {
            throw FramerError.config("'screenshots' is empty")
        }
        try config.background?.gradient.validate()

        let outputDirectory = outputDirectoryOverride ?? resolve(config.outputDirectory, against: baseDirectory)

        return try config.screenshots.enumerated().map { index, entry in
            try job(for: entry, context: "screenshots[\(index)]", config: config, baseDirectory: baseDirectory, outputDirectory: outputDirectory)
        }
    }

    private static func job(
        for entry: ScreenshotEntry,
        context: String,
        config: FramerConfig,
        baseDirectory: URL,
        outputDirectory: URL
    ) throws -> RenderJob {
        let devices = entry.devices ?? []
        let callouts = entry.callouts ?? []
        let pages = entry.pages ?? []
        try entry.background?.gradient.validate()

        if config.mode == .simple {
            for (key, isUsed) in [("devices", !devices.isEmpty), ("callouts", !callouts.isEmpty), ("pages", !pages.isEmpty)] where isUsed {
                throw FramerError.config("\(context): '\(key)' needs \"mode\": \"inset\"")
            }
        }
        if !pages.isEmpty {
            guard !devices.isEmpty else {
                throw FramerError.config("\(context): 'pages' needs 'devices' to place devices across the pages")
            }
            guard entry.title == nil, entry.subtitle == nil else {
                throw FramerError.config("\(context): with 'pages', put titles and subtitles in each page instead")
            }
        }

        let placed = try devices.enumerated().map { deviceIndex, device -> RenderJob.PlacedDevice in
            guard let path = device.path ?? entry.path else {
                throw FramerError.config("\(context).devices[\(deviceIndex)]: missing 'path' (and the entry has none to inherit)")
            }
            return RenderJob.PlacedDevice(
                input: resolve(path, against: baseDirectory),
                deviceName: device.device ?? entry.device ?? config.device,
                frameColor: device.frameColor ?? entry.frameColor ?? config.frameColor,
                landscapeSide: device.landscapeSide ?? entry.landscapeSide ?? config.landscapeSide,
                placement: device.placement
            )
        }

        let deviceCount = max(placed.count, 1)
        for (calloutIndex, callout) in callouts.enumerated() {
            guard (0..<deviceCount).contains(callout.device) else {
                throw FramerError.config("\(context).callouts[\(calloutIndex)]: 'device' \(callout.device) is out of range; the entry has \(deviceCount) device(s)")
            }
            guard callout.region.width > 0, callout.region.height > 0 else {
                throw FramerError.config("\(context).callouts[\(calloutIndex)]: 'region' needs a positive width and height")
            }
            guard callout.scale > 0 else {
                throw FramerError.config("\(context).callouts[\(calloutIndex)]: 'scale' must be greater than 0")
            }
        }

        let input: URL
        if let first = placed.first {
            input = first.input
        } else if let path = entry.path {
            input = resolve(path, against: baseDirectory)
        } else {
            throw FramerError.config("\(context): missing 'path'")
        }
        let outputName = entry.output ?? input.deletingPathExtension().lastPathComponent

        let inset: RenderJob.InsetSettings? = config.mode == .inset ? RenderJob.InsetSettings(
            title: entry.title ?? "",
            subtitle: entry.subtitle ?? "",
            titleStyle: config.text.title.style,
            subtitleStyle: config.text.subtitle.style,
            position: config.text.position,
            spacing: config.text.resolvedSpacing,
            padding: config.padding,
            gap: config.gap,
            deviceScale: config.deviceScale,
            bleed: entry.bleed ?? config.bleed,
            shadow: config.shadow?.spec,
            devices: placed,
            callouts: callouts.map(\.spec),
            pages: pages.map { RenderJob.Page(title: $0.title ?? "", subtitle: $0.subtitle ?? "") }
        ) : nil

        return RenderJob(
            input: input,
            outputBase: outputDirectory.appendingPathComponent(outputName),
            format: config.output.format,
            jpegQuality: config.output.jpegQuality,
            mode: config.mode,
            deviceName: entry.device ?? config.device,
            frameColor: entry.frameColor ?? config.frameColor,
            landscapeSide: entry.landscapeSide ?? config.landscapeSide,
            requestedWidth: config.output.width,
            requestedHeight: config.output.height,
            background: (entry.background ?? config.background)?.gradient,
            inset: inset
        )
    }

    static func resolve(_ path: String, against base: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return base.appendingPathComponent(expanded).standardizedFileURL
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue)
            return keys.isEmpty ? "root" : keys.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default:
            return "\(error)"
        }
    }

    /// The sample config written by `framer init`.
    public static let sampleJSON = """
    {
      "outputDirectory": "framed",
      "output": { "width": 1290, "height": 2796, "format": "png", "jpegQuality": 0.9 },
      "mode": "inset",
      "device": null,
      "frameColor": null,
      "landscapeSide": "left",
      "background": { "colors": ["#1E3A8A", "#9333EA"], "angle": 160 },
      "text": {
        "position": "top",
        "title":    { "font": "system", "size": 96, "weight": "bold",    "color": "#FFFFFF" },
        "subtitle": { "font": "system", "size": 56, "weight": "regular", "color": "#FFFFFFCC" },
        "spacing": 24
      },
      "padding": 96,
      "gap": 64,
      "deviceScale": 1.0,
      "screenshots": [
        { "path": "raw/home.png",   "title": "Plan your day",     "subtitle": "Everything in one place" },
        { "path": "raw/detail.png", "title": "Dive into details", "device": "iPhone 17 Pro", "frameColor": "Silver", "output": "02-detail" }
      ]
    }

    """
}
