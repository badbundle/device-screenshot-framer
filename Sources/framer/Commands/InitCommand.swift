import ArgumentParser
import Foundation
import FramerCore

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Write a sample config file to get started with `framer render`."
    )

    @Option(name: .long, help: "Where to write the config.", completion: .file(extensions: ["json"]))
    var path: String = "framer.json"

    @Flag(name: .long, help: "Overwrite an existing file.")
    var force = false

    func run() throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: url.path), !force {
            throw ValidationError("'\(url.path)' exists; pass --force to overwrite")
        }
        try Data(ConfigLoader.sampleJSON.utf8).write(to: url, options: .atomic)
        print("wrote \(url.path)")
    }
}
