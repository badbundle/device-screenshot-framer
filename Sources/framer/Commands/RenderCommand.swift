import ArgumentParser
import Foundation
import FramerCore

struct RenderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render screenshots from a JSON config (supports inset mode with title/subtitle)."
    )

    @Option(name: [.short, .long], help: "Path to the JSON config.", completion: .file(extensions: ["json"]))
    var config: String = "framer.json"

    @Option(name: [.short, .customLong("output-dir")], help: "Override the config's outputDirectory.", completion: .directory)
    var outputDir: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Only render entries whose output name or input basename matches.")
    var only: [String] = []

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let configURL = URL(fileURLWithPath: (config as NSString).expandingTildeInPath)
        let loaded = try ConfigLoader.load(configURL)
        let override = outputDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        var jobs = try ConfigLoader.jobs(
            from: loaded,
            baseDirectory: configURL.deletingLastPathComponent(),
            outputDirectoryOverride: override
        )

        if !only.isEmpty {
            let wanted = Set(only.map { $0.lowercased() })
            jobs = jobs.filter {
                wanted.contains($0.outputBase.lastPathComponent.lowercased())
                    || wanted.contains($0.input.deletingPathExtension().lastPathComponent.lowercased())
            }
            guard !jobs.isEmpty else { throw ValidationError("no screenshots match --only \(only.joined(separator: ", "))") }
        }

        try await runJobs(jobs, options: global)
    }
}
