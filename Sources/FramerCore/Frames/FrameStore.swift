import Foundation

/// Downloads and caches frames from fastlane/frameit-frames.
///
/// Layout on disk:
/// ```
/// <cacheRoot>/current-version          # text, e.g. "1772014847"
/// <cacheRoot>/<version>/files.json
/// <cacheRoot>/<version>/offsets.json
/// <cacheRoot>/<version>/Apple iPhone 17 Pro Silver.png
/// ```
public struct FrameStore: Sendable {
    public static let defaultBaseURL = URL(string: "https://raw.githubusercontent.com/fastlane/frameit-frames/gh-pages/latest/")!

    public static var defaultCacheRoot: URL {
        if let env = ProcessInfo.processInfo.environment["FRAMER_CACHE_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("device-screenshot-framer/frames", isDirectory: true)
    }

    public typealias Fetcher = @Sendable (URL) async throws -> Data

    public var cacheRoot: URL
    public var baseURL: URL
    public var offline: Bool
    public var fetch: Fetcher

    public init(
        cacheRoot: URL = FrameStore.defaultCacheRoot,
        baseURL: URL = FrameStore.defaultBaseURL,
        offline: Bool = false,
        fetch: @escaping Fetcher = FrameStore.urlSessionFetch
    ) {
        self.cacheRoot = cacheRoot
        self.baseURL = baseURL
        self.offline = offline
        self.fetch = fetch
    }

    public static let urlSessionFetch: Fetcher = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw FramerError.download(url, status: http.statusCode)
        }
        return data
    }

    public struct ResolvedFrame: Sendable {
        public var fileURL: URL
        public var filename: String
        public var color: String
        public var offset: FrameOffset
    }

    // MARK: - Manifest

    /// Loads the cached manifest, or fetches the current one. With `refresh`, always re-fetches.
    public func manifest(refresh: Bool = false) async throws -> FrameManifest {
        if !refresh, let cached = try loadCachedManifest() {
            return cached
        }
        if offline {
            if let cached = try loadCachedManifest() { return cached }
            throw FramerError.offline("frames manifest")
        }
        do {
            return try await fetchManifest()
        } catch {
            if let cached = try loadCachedManifest() {
                Log.warn("could not refresh frames (\(error)); using cached version \(cached.version)")
                return cached
            }
            throw error
        }
    }

    private func loadCachedManifest() throws -> FrameManifest? {
        let versionFile = cacheRoot.appendingPathComponent("current-version")
        guard let version = try? String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty
        else { return nil }
        let dir = cacheRoot.appendingPathComponent(version, isDirectory: true)
        guard let files = try? Data(contentsOf: dir.appendingPathComponent("files.json")),
              let offsets = try? Data(contentsOf: dir.appendingPathComponent("offsets.json"))
        else { return nil }
        return FrameManifest(
            version: version,
            directory: dir,
            files: try FrameManifest.parseFiles(files),
            offsets: try FrameManifest.parseOffsets(offsets)
        )
    }

    private func fetchManifest() async throws -> FrameManifest {
        let versionData = try await fetch(baseURL.appendingPathComponent("version.txt"))
        let version = String(decoding: versionData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty, version.allSatisfy(\.isNumber) else {
            throw FramerError.config("unexpected frames version '\(version)'")
        }
        let dir = cacheRoot.appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filesData = try await fetch(baseURL.appendingPathComponent("files.json"))
        let offsetsData = try await fetch(baseURL.appendingPathComponent("offsets.json"))
        let files = try FrameManifest.parseFiles(filesData)
        let offsets = try FrameManifest.parseOffsets(offsetsData)

        try filesData.write(to: dir.appendingPathComponent("files.json"), options: .atomic)
        try offsetsData.write(to: dir.appendingPathComponent("offsets.json"), options: .atomic)
        try Data(version.utf8).write(to: cacheRoot.appendingPathComponent("current-version"), options: .atomic)

        return FrameManifest(version: version, directory: dir, files: files, offsets: offsets)
    }

    // MARK: - Frames

    /// Resolves (and downloads if needed) the frame for `device` in `color` (or the device default).
    public func frame(for device: Device, color requested: String?, manifest initial: FrameManifest) async throws -> ResolvedFrame {
        var manifest = initial
        var color = requested ?? device.defaultColor
        var filename = device.frameFilename(color: color)

        if !manifest.files.contains(filename), requested != nil {
            // Colours from the manifest whose filename round-trips exactly, so "iPhone 17 Pro" does not pick up "iPhone 17 Pro Max …".
            let available = device.colors
                .filter { manifest.files.contains(device.frameFilename(color: $0)) }
                .sorted()
            Log.warn("colour '\(color)' not available for \(device.name) (available: \(available.joined(separator: ", "))); using '\(device.defaultColor)'")
            color = device.defaultColor
            filename = device.frameFilename(color: color)
        }

        if !manifest.files.contains(filename), !offline {
            manifest = try await self.manifest(refresh: true)
        }
        guard manifest.files.contains(filename) else {
            throw FramerError.noFrame(device: device.name, filename: filename)
        }
        guard let offset = FrameResolver.offset(filename: filename, color: color, offsets: manifest.offsets) else {
            throw FramerError.offsetsMissing(filename: filename)
        }

        let fileURL = manifest.directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            if offline { throw FramerError.offline(filename) }
            try await download(filename: filename, to: fileURL)
        }
        return ResolvedFrame(fileURL: fileURL, filename: filename, color: color, offset: offset)
    }

    private func download(filename: String, to fileURL: URL) async throws {
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: encoded, relativeTo: baseURL)?.absoluteURL
        else {
            throw FramerError.download(baseURL, status: nil)
        }
        let data = try await fetch(url)
        let partial = fileURL.appendingPathExtension("part")
        try data.write(to: partial, options: .atomic)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: partial, to: fileURL)
    }

    /// Downloads every Apple frame not already cached. `progress` is called with each filename as it completes.
    public func downloadAll(manifest: FrameManifest, maxConcurrent: Int = 6, progress: @escaping @Sendable (String) -> Void) async throws {
        let wanted = manifest.files
            .filter { $0.hasPrefix("Apple ") && $0.hasSuffix(".png") }
            .filter { !FileManager.default.fileExists(atPath: manifest.directory.appendingPathComponent($0).path) }
            .sorted()
        guard !wanted.isEmpty else { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = wanted.makeIterator()
            var inFlight = 0
            func enqueue(_ name: String) {
                group.addTask {
                    try await download(filename: name, to: manifest.directory.appendingPathComponent(name))
                    progress(name)
                }
            }
            while inFlight < maxConcurrent, let next = iterator.next() {
                enqueue(next)
                inFlight += 1
            }
            while inFlight > 0 {
                try await group.next()
                inFlight -= 1
                if let next = iterator.next() {
                    enqueue(next)
                    inFlight += 1
                }
            }
        }
    }
}
