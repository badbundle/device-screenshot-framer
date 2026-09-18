import Foundation

/// Parsed `files.json` + `offsets.json` from a frameit-frames release.
public struct FrameManifest: Sendable {
    public var version: String
    /// Directory holding the cached files for this version.
    public var directory: URL
    public var files: Set<String>
    /// Keyed by frameit's "portrait" device key.
    public var offsets: [String: FrameOffset]

    public init(version: String, directory: URL, files: Set<String>, offsets: [String: FrameOffset]) {
        self.version = version
        self.directory = directory
        self.files = files
        self.offsets = offsets
    }

    public static func parseFiles(_ data: Data) throws -> Set<String> {
        do {
            return Set(try JSONDecoder().decode([String].self, from: data))
        } catch {
            throw FramerError.config("files.json is malformed: \(error)")
        }
    }

    public static func parseOffsets(_ data: Data) throws -> [String: FrameOffset] {
        struct RawOffset: Decodable {
            var offset: String
            var width: Int
        }
        struct Root: Decodable {
            var portrait: [String: RawOffset]
        }
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw FramerError.config("offsets.json is malformed: \(error)")
        }
        var result: [String: FrameOffset] = [:]
        for (key, raw) in root.portrait {
            result[key] = try FrameOffset(offsetString: raw.offset, width: raw.width)
        }
        return result
    }
}
