import ArgumentParser
import Foundation
import FramerCore

struct FrameCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frame",
        abstract: "Put screenshots into device frames (simple mode, no text)."
    )

    @Argument(help: "Screenshot files (PNG or JPEG).", completion: .file(extensions: ["png", "jpg", "jpeg"]))
    var inputs: [String]

    @Option(name: [.short, .customLong("output-dir")], help: "Directory for framed images.", completion: .directory)
    var outputDir: String = "framed"

    @Option(name: .long, help: "Output width in pixels (default: screenshot width).")
    var width: Int?

    @Option(name: .long, help: "Output height in pixels (default: screenshot height).")
    var height: Int?

    @Option(name: .long, help: "Force a device, e.g. \"iPhone 17 Pro\". See list-devices.")
    var device: String?

    @Option(name: .long, help: "Frame colour, e.g. \"Deep Blue\". Falls back to the device default.")
    var color: String?

    @Option(name: .long, help: "Output format: png or jpeg.")
    var format: OutputFormat = .png

    @Option(name: .long, help: "Background: one hex colour or two or more comma-separated for a gradient, e.g. \"#1E3A8A,#9333EA\".")
    var background: String?

    @Option(name: .long, help: "Gradient angle in degrees (CSS convention; 180 = top to bottom).")
    var angle: Double = 180

    @Option(name: .long, help: "For landscape screenshots, which side the notch / Dynamic Island is on.")
    var landscapeSide: LandscapeSide = .left

    @OptionGroup var global: GlobalOptions

    func validate() throws {
        guard !inputs.isEmpty else { throw ValidationError("provide at least one screenshot") }
    }

    mutating func run() async throws {
        let outputDirectory = URL(fileURLWithPath: (outputDir as NSString).expandingTildeInPath, isDirectory: true)
        let gradient = try background.map { try parseBackground($0, angle: angle) }

        let jobs = inputs.map { path -> RenderJob in
            let input = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            return RenderJob(
                input: input,
                outputBase: outputDirectory.appendingPathComponent(input.deletingPathExtension().lastPathComponent),
                format: format,
                mode: .simple,
                deviceName: device,
                frameColor: color,
                landscapeSide: landscapeSide,
                requestedWidth: width,
                requestedHeight: height,
                background: gradient
            )
        }
        try await runJobs(jobs, options: global)
    }
}

func parseBackground(_ spec: String, angle: Double) throws -> GradientSpec {
    let colors = try spec.split(separator: ",").map { try RGBAColor(hex: String($0)) }
    let gradient = GradientSpec(colors: colors, angleDegrees: angle)
    try gradient.validate()
    return gradient
}
