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

        return try config.screenshots.map { entry in
            let input = resolve(entry.path, against: baseDirectory)
            let outputName = entry.output ?? input.deletingPathExtension().lastPathComponent
            try entry.background?.gradient.validate()

            let inset: RenderJob.InsetSettings? = config.mode == .inset ? RenderJob.InsetSettings(
                title: entry.title ?? "",
                subtitle: entry.subtitle ?? "",
                titleStyle: config.text.title.style,
                subtitleStyle: config.text.subtitle.style,
                position: config.text.position,
                spacing: config.text.resolvedSpacing,
                padding: config.padding,
                gap: config.gap,
                deviceScale: config.deviceScale
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
