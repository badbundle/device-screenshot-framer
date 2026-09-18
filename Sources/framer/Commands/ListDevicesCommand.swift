import ArgumentParser
import Foundation
import FramerCore

struct ListDevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-devices",
        abstract: "List supported devices, their screenshot sizes and frame colours."
    )

    @Flag(name: .long, help: "Output as JSON.")
    var json = false

    func run() throws {
        let devices = DeviceCatalog.all
        if json {
            let rows = devices.map { d in
                DeviceRow(
                    name: d.name,
                    aliases: d.aliases,
                    width: d.screenSize.width,
                    height: d.screenSize.height,
                    frame: d.framePrefix,
                    borrowedFrame: d.usesBorrowedFrame,
                    colors: d.colors,
                    defaultColor: d.defaultColor
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(rows), as: UTF8.self))
            return
        }

        let nameWidth = devices.map(\.name.count).max() ?? 20
        for d in devices {
            let name = d.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            var line = "\(name)  \(d.screenSize)".padding(toLength: nameWidth + 13, withPad: " ", startingAt: 0)
            line += "  " + d.colors.map { $0 == d.defaultColor ? "\($0)*" : $0 }.joined(separator: ", ")
            if d.usesBorrowedFrame {
                line += "  (uses \(d.framePrefix.replacingOccurrences(of: "Apple ", with: "")) frame)"
            }
            if !d.aliases.isEmpty {
                line += "  aka \(d.aliases.joined(separator: ", "))"
            }
            print(line)
        }
        print("\n* default colour. Sizes are portrait; landscape screenshots are detected automatically.")
    }

    private struct DeviceRow: Encodable {
        var name: String
        var aliases: [String]
        var width: Int
        var height: Int
        var frame: String
        var borrowedFrame: Bool
        var colors: [String]
        var defaultColor: String
    }
}
