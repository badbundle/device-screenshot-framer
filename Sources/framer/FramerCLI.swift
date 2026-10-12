import ArgumentParser
import Foundation
import FramerCore

@main
struct FramerCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "framer",
        abstract: "Frame iOS, iPadOS and macOS screenshots in Apple device frames, or as Mac windows.",
        discussion: """
            Frames are downloaded on demand from fastlane/frameit-frames and cached in
            ~/Library/Caches/device-screenshot-framer (override with --cache-dir or FRAMER_CACHE_DIR).
            """,
        subcommands: [FrameCommand.self, RenderCommand.self, DownloadFramesCommand.self, ListDevicesCommand.self, InitCommand.self],
        defaultSubcommand: FrameCommand.self
    )
}

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Directory for cached frames.", completion: .directory)
    var cacheDir: String?

    @Flag(name: .long, help: "Never touch the network; fail if a frame is not cached.")
    var offline = false

    @Flag(name: .shortAndLong, help: "Print extra diagnostics.")
    var verbose = false

    var store: FrameStore {
        FrameStore(
            cacheRoot: cacheDir.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? FrameStore.defaultCacheRoot,
            offline: offline
        )
    }
}

extension LandscapeSide: ExpressibleByArgument {}
extension FrameStyle: ExpressibleByArgument {}
extension OutputFormat: ExpressibleByArgument {}

enum CLIError: Error, CustomStringConvertible {
    case failed(count: Int)

    var description: String {
        switch self {
        case .failed(let count): return "\(count) screenshot(s) failed"
        }
    }
}

/// Runs jobs, prints a summary, exits non-zero if anything failed.
func runJobs(_ jobs: [RenderJob], options: GlobalOptions) async throws {
    let renderer = Renderer(store: options.store, verbose: options.verbose)
    let (outcomes, failures) = await renderer.run(jobs)

    for outcome in outcomes {
        let devices = outcome.screens.map { screen in
            guard let device = screen.device, let frame = screen.frame else { return "window" }
            let frameNote = device.usesBorrowedFrame ? " (\(device.framePrefix.replacingOccurrences(of: "Apple ", with: "")) frame)" : ""
            return "\(device.name), \(frame.color)\(frameNote)"
        }
        for output in outcome.outputs {
            print("✓ \(output.path)  [\(devices.joined(separator: " + ")), \(outcome.size)]")
        }
    }
    for (job, error) in failures {
        FileHandle.standardError.write(Data("✗ \(job.input.path): \(error)\n".utf8))
    }
    if !failures.isEmpty {
        throw CLIError.failed(count: failures.count)
    }
}
