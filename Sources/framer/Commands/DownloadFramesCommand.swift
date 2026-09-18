import ArgumentParser
import Foundation
import FramerCore

struct DownloadFramesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download-frames",
        abstract: "Prefetch every Apple frame into the cache (frames are otherwise downloaded on demand)."
    )

    @Flag(name: .long, help: "Re-check the upstream version even if a manifest is cached.")
    var force = false

    @OptionGroup var global: GlobalOptions

    mutating func run() async throws {
        let store = global.store
        let manifest = try await store.manifest(refresh: force)
        print("frames version \(manifest.version) → \(manifest.directory.path)")
        try await store.downloadAll(manifest: manifest) { name in
            print("  \(name)")
        }
        print("done")
    }
}
