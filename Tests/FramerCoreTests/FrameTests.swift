import Foundation
import Testing
@testable import FramerCore

/// A slice of the real frameit-frames offsets.json, including its naming quirks.
let fixtureOffsetsJSON = """
{
  "portrait": {
    "iPhone 16 Pro Max": { "offset": "+75+66", "width": 1320 },
    "iPhone 17 Pro": { "offset": "+72+69", "width": 1206 },
    "iPhone 13 Mini": { "offset": "+71+63", "width": 1080 },
    "iPhone 13 Mini Midnight": { "offset": "+74+66", "width": 1080 },
    "iPhone 12 Pro": { "offset": "+72+63", "width": 1170 },
    "iPhone 12 Pro Pacific": { "offset": "+72+63", "width": 1170 },
    "iPhone 13 Pro Sierra": { "offset": "+74+62", "width": 1170 },
    "iPad Pro (11 inch)": { "offset": "+95+100", "width": 1668 },
    "iPad Pro (12.9 inch) (4th generation)": { "offset": "+96+102", "width": 2048 },
    "iPad Air (2019) 2020  Portrait": { "offset": "+110+114", "width": 1640 },
    "iPad Air (2019) 2020 Sky  Portrait": { "offset": "+110+114", "width": 1640 },
    "Test Phone": { "offset": "+30+40", "width": 240 }
  }
}
"""

let fixtureFilesJSON = """
[
  "Apple iPhone 17 Pro Silver.png",
  "Apple iPhone 17 Pro Deep Blue.png",
  "Apple iPhone 17 Pro Max Silver.png",
  "Apple Test Phone Gray.png",
  "Google Pixel 5 Just Black.png"
]
"""

@Suite struct FrameResolverTests {
    let offsets = try! FrameManifest.parseOffsets(Data(fixtureOffsetsJSON.utf8))

    @Test(arguments: [
        ("Apple iPhone 16 Pro Max Black Titanium.png", "Black Titanium", "iPhone 16 Pro Max"),
        ("Apple iPhone 13 Mini Midnight.png", "Midnight", "iPhone 13 Mini Midnight"),
        ("Apple iPhone 13 Mini Blue.png", "Blue", "iPhone 13 Mini"),
        ("Apple iPhone 12 Pro Pacific Blue.png", "Pacific Blue", "iPhone 12 Pro Pacific"),
        ("Apple iPhone 12 Pro Gold.png", "Gold", "iPhone 12 Pro"),
        ("Apple iPhone 13 Pro Sierra Blue.png", "Sierra Blue", "iPhone 13 Pro Sierra"),
        ("Apple iPad Pro (11-inch) Silver.png", "Silver", "iPad Pro (11 inch)"),
        ("Apple iPad Pro (12.9-inch) (4th generation) Space Gray.png", "Space Gray", "iPad Pro (12.9 inch) (4th generation)"),
        ("Apple iPad Air (2019) 2020 Silver Portrait.png", "Silver", "iPad Air (2019) 2020  Portrait"),
        ("Apple iPad Air (2019) 2020 Sky Blue Portrait.png", "Sky Blue", "iPad Air (2019) 2020 Sky  Portrait"),
    ])
    func resolvesKey(_ filename: String, _ color: String, _ expectedKey: String) {
        let candidates = FrameResolver.offsetsKeyCandidates(filename: filename, color: color)
        let match = candidates.first { offsets[$0] != nil }
        #expect(match == expectedKey, "candidates: \(candidates)")
        #expect(FrameResolver.offset(filename: filename, color: color, offsets: offsets) == offsets[expectedKey])
    }

    @Test func missingIsNil() {
        #expect(FrameResolver.offset(filename: "Apple iPhone 99 Red.png", color: "Red", offsets: offsets) == nil)
    }

    @Test func parsesManifests() throws {
        let files = try FrameManifest.parseFiles(Data(fixtureFilesJSON.utf8))
        #expect(files.contains("Apple Test Phone Gray.png"))
        #expect(offsets["Test Phone"] == FrameOffset(x: 30, y: 40, width: 240))
        #expect(throws: FramerError.self) { try FrameManifest.parseOffsets(Data("nope".utf8)) }
    }
}

/// NSLock-guarded box (Mutex needs macOS 15).
final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

/// In-memory HTTP stand-in.
final class FakeServer: Sendable {
    private let responses: Locked<[String: Data]>
    private let counter = Locked<[String]>([])

    init(_ files: [String: Data]) {
        responses = Locked(files)
    }

    var fetch: FrameStore.Fetcher {
        { url in
            let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            self.counter.withLock { $0.append(name) }
            guard let data = self.responses.withLock({ $0[name] }) else {
                throw FramerError.download(url, status: 404)
            }
            return data
        }
    }

    var requests: [String] { counter.withLock { $0 } }
}

@Suite struct FrameStoreTests {
    static func makeServer(version: String = "1772014847") -> FakeServer {
        FakeServer([
            "version.txt": Data("\(version)\n".utf8),
            "files.json": Data(fixtureFilesJSON.utf8),
            "offsets.json": Data(fixtureOffsetsJSON.utf8),
            "Apple Test Phone Gray.png": Data("PNG".utf8),
            "Apple iPhone 17 Pro Silver.png": Data("PNG2".utf8),
        ])
    }

    static func makeStore(_ server: FakeServer, dir: URL, offline: Bool = false) -> FrameStore {
        FrameStore(cacheRoot: dir, baseURL: URL(string: "https://example.test/latest/")!, offline: offline, fetch: server.fetch)
    }

    @Test func manifestIsFetchedOnceThenCached() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Self.makeServer()

        let first = try await Self.makeStore(server, dir: dir).manifest()
        #expect(first.version == "1772014847")
        #expect(first.files.count == 5)
        #expect(server.requests == ["version.txt", "files.json", "offsets.json"])

        let second = try await Self.makeStore(server, dir: dir).manifest()
        #expect(second.version == first.version)
        #expect(server.requests.count == 3, "cached manifest must not hit the network")

        _ = try await Self.makeStore(server, dir: dir).manifest(refresh: true)
        #expect(server.requests.count == 6)
    }

    @Test func frameDownloadsOnceAndResolvesOffset() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Self.makeServer()
        let store = Self.makeStore(server, dir: dir)
        let manifest = try await store.manifest()

        let frame = try await store.frame(for: Synthetic.device, color: nil, manifest: manifest)
        #expect(frame.filename == "Apple Test Phone Gray.png")
        #expect(frame.color == "Gray")
        #expect(frame.offset == FrameOffset(x: 30, y: 40, width: 240))
        #expect(try Data(contentsOf: frame.fileURL) == Data("PNG".utf8))
        #expect(server.requests.filter { $0 == "Apple Test Phone Gray.png" }.count == 1)

        _ = try await store.frame(for: Synthetic.device, color: nil, manifest: manifest)
        #expect(server.requests.filter { $0 == "Apple Test Phone Gray.png" }.count == 1, "second call uses the cache")
    }

    @Test func unknownColourFallsBackToDefault() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Self.makeServer()
        let store = Self.makeStore(server, dir: dir)
        let manifest = try await store.manifest()

        let device = DeviceCatalog.named("iPhone 17 Pro")!
        let frame = try await store.frame(for: device, color: "Nope", manifest: manifest)
        #expect(frame.color == "Silver")
        #expect(frame.filename == "Apple iPhone 17 Pro Silver.png")
    }

    @Test func missingFrameThrowsAfterOneRefresh() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Self.makeServer()
        let store = Self.makeStore(server, dir: dir)
        let manifest = try await store.manifest()

        let device = DeviceCatalog.named("iPhone 5c")!
        await #expect(throws: FramerError.self) {
            try await store.frame(for: device, color: nil, manifest: manifest)
        }
        #expect(server.requests.filter { $0 == "version.txt" }.count == 2, "one refresh attempt")
    }

    @Test func offlineWithEmptyCacheThrows() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Self.makeServer()
        let store = Self.makeStore(server, dir: dir, offline: true)
        await #expect(throws: FramerError.self) { try await store.manifest() }
        #expect(server.requests.isEmpty)
    }

    @Test func offlineUsesCacheAndRefusesDownloads() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = Self.makeServer()
        let manifest = try await Self.makeStore(server, dir: dir).manifest()

        let offline = Self.makeStore(server, dir: dir, offline: true)
        let cached = try await offline.manifest()
        #expect(cached.version == manifest.version)
        await #expect(throws: FramerError.self) {
            try await offline.frame(for: Synthetic.device, color: nil, manifest: cached)
        }
    }

    @Test func networkFailureFallsBackToCache() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await Self.makeStore(Self.makeServer(), dir: dir).manifest()

        let dead = FakeServer([:])
        let manifest = try await Self.makeStore(dead, dir: dir).manifest(refresh: true)
        #expect(manifest.version == "1772014847")
    }

    @Test func downloadAllFetchesOnlyAppleFramesNotCached() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = FakeServer([
            "version.txt": Data("1".utf8),
            "files.json": Data(fixtureFilesJSON.utf8),
            "offsets.json": Data(fixtureOffsetsJSON.utf8),
            "Apple Test Phone Gray.png": Data("a".utf8),
            "Apple iPhone 17 Pro Silver.png": Data("b".utf8),
            "Apple iPhone 17 Pro Deep Blue.png": Data("c".utf8),
            "Apple iPhone 17 Pro Max Silver.png": Data("d".utf8),
        ])
        let store = Self.makeStore(server, dir: dir)
        let manifest = try await store.manifest()
        _ = try await store.frame(for: Synthetic.device, color: nil, manifest: manifest)

        let done = Locked<[String]>([])
        try await store.downloadAll(manifest: manifest, maxConcurrent: 2) { name in done.withLock { $0.append(name) } }
        #expect(Set(done.withLock { $0 }) == ["Apple iPhone 17 Pro Silver.png", "Apple iPhone 17 Pro Deep Blue.png", "Apple iPhone 17 Pro Max Silver.png"])
        #expect(!server.requests.contains("Google Pixel 5 Just Black.png"))
        #expect(FileManager.default.fileExists(atPath: manifest.directory.appendingPathComponent("Apple iPhone 17 Pro Max Silver.png").path))
    }
}

@Suite struct ConfigTests {
    @Test func decodesSample() throws {
        let config = try ConfigLoader.decode(Data(ConfigLoader.sampleJSON.utf8))
        #expect(config.mode == .inset)
        #expect(config.output.width == 1290 && config.output.height == 2796)
        #expect(config.background?.colors.count == 2)
        #expect(config.background?.angle == 160)
        #expect(config.text.title.weight == .bold)
        #expect(config.text.subtitle.color.alpha < 1)
        #expect(config.padding == 96)
        #expect(config.screenshots.count == 2)
        #expect(config.screenshots[1].device == "iPhone 17 Pro")
        #expect(config.screenshots[1].output == "02-detail")
    }

    @Test func minimalConfigUsesDefaults() throws {
        let config = try ConfigLoader.decode(Data(#"{ "screenshots": [{ "path": "a.png" }] }"#.utf8))
        #expect(config.mode == .simple)
        #expect(config.outputDirectory == "framed")
        #expect(config.output.format == .png)
        #expect(config.landscapeSide == .left)
        #expect(config.text.position == .top)
        #expect(config.text.resolvedSpacing == 22)
        #expect(config.deviceScale == 1)
    }

    @Test func jobsResolveRelativePathsAgainstConfigDirectory() throws {
        let config = try ConfigLoader.decode(Data(#"""
        {
          "mode": "inset",
          "outputDirectory": "out",
          "background": { "colors": ["#000"] },
          "screenshots": [
            { "path": "raw/a.png", "title": "A" },
            { "path": "/abs/b.png", "output": "bee", "device": "iPhone 17", "background": { "colors": ["#fff", "#000"], "angle": 90 } }
          ]
        }
        """#.utf8))
        let base = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let jobs = try ConfigLoader.jobs(from: config, baseDirectory: base)
        #expect(jobs.count == 2)
        #expect(jobs[0].input.path == "/tmp/project/raw/a.png")
        #expect(jobs[0].outputURL.path == "/tmp/project/out/a.png")
        #expect(jobs[0].inset?.title == "A")
        #expect(jobs[0].background?.colors.count == 1)
        #expect(jobs[1].input.path == "/abs/b.png")
        #expect(jobs[1].outputURL.path == "/tmp/project/out/bee.png")
        #expect(jobs[1].deviceName == "iPhone 17")
        #expect(jobs[1].background?.angleDegrees == 90)

        let overridden = try ConfigLoader.jobs(from: config, baseDirectory: base, outputDirectoryOverride: URL(fileURLWithPath: "/elsewhere"))
        #expect(overridden[0].outputURL.path == "/elsewhere/a.png")
    }

    @Test func errorsAreReadable() {
        #expect(throws: FramerError.self) { try ConfigLoader.decode(Data(#"{ "screenshots": [{ "title": "no path" }] }"#.utf8)) }
        #expect(throws: FramerError.self) { try ConfigLoader.decode(Data(#"{ "mode": "fancy", "screenshots": [] }"#.utf8)) }
        #expect(throws: FramerError.self) { try ConfigLoader.jobs(from: FramerConfig(), baseDirectory: URL(fileURLWithPath: "/")) }
        #expect(throws: FramerError.self) {
            try ConfigLoader.jobs(
                from: FramerConfig(background: BackgroundConfig(colors: [.white, .black], locations: [0]), screenshots: [ScreenshotEntry(path: "a.png")]),
                baseDirectory: URL(fileURLWithPath: "/")
            )
        }
    }
}

@Suite struct RendererTests {
    @Test func endToEndWithSyntheticFrame() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Real PNG bytes for the fake frame so ImageLoader can read it.
        let framePNG = dir.appendingPathComponent("frame.png")
        try ImageWriter.write(Synthetic.frame(), to: framePNG, format: .png)
        let shot = dir.appendingPathComponent("shot.png")
        try ImageWriter.write(Synthetic.screenshot(size: PixelSize(1206, 2622)), to: shot, format: .png)

        // Serve the synthetic frame under the iPhone 17 Pro name with matching offsets.
        let offsets = """
        { "portrait": { "iPhone 17 Pro": { "offset": "+30+40", "width": 240 } } }
        """
        let server = FakeServer([
            "version.txt": Data("7".utf8),
            "files.json": Data(#"["Apple iPhone 17 Pro Silver.png"]"#.utf8),
            "offsets.json": Data(offsets.utf8),
            "Apple iPhone 17 Pro Silver.png": try Data(contentsOf: framePNG),
        ])
        let store = FrameStore(cacheRoot: dir.appendingPathComponent("cache"), baseURL: URL(string: "https://example.test/")!, fetch: server.fetch)
        let renderer = Renderer(store: store)

        let job = RenderJob(
            input: shot,
            outputBase: dir.appendingPathComponent("out/shot"),
            mode: .inset,
            requestedWidth: 600,
            background: GradientSpec(solid: RGBAColor(red: 0, green: 0, blue: 1)),
            inset: RenderJob.InsetSettings(
                title: "Hi", subtitle: "",
                titleStyle: TextStyle(font: FontSpec(size: 40, weight: .bold), color: .white),
                subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
                position: .top, spacing: 8, padding: 30, gap: 30, deviceScale: 1
            )
        )
        let (outcomes, failures) = await renderer.run([job])
        #expect(failures.isEmpty, "\(failures.map { "\($0.1)" })")
        let outcome = try #require(outcomes.first)
        #expect(outcome.device.name == "iPhone 17 Pro")
        // width 600 -> height follows the framed aspect (300x600 frame => 1200), capped at native 2622.
        #expect(outcome.size == PixelSize(600, 1200))
        let bitmap = Bitmap(try ImageLoader.load(outcome.output))
        bitmap.expect(2, 2, .blue)
        #expect(bitmap[300, 1200 - 30 - 15].isClose(to: .gray, tolerance: 40)) // body is inset 5px × scale from the device edge
    }

    @Test func unknownSizeFailsWithHelpfulError() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let shot = dir.appendingPathComponent("odd.png")
        try ImageWriter.write(Synthetic.screenshot(size: PixelSize(123, 456)), to: shot, format: .png)
        let server = FakeServer([
            "version.txt": Data("7".utf8),
            "files.json": Data("[]".utf8),
            "offsets.json": Data(#"{ "portrait": {} }"#.utf8),
        ])
        let store = FrameStore(cacheRoot: dir.appendingPathComponent("cache"), baseURL: URL(string: "https://example.test/")!, fetch: server.fetch)
        let (outcomes, failures) = await Renderer(store: store).run([RenderJob(input: shot, outputBase: dir.appendingPathComponent("x"))])
        #expect(outcomes.isEmpty)
        #expect(failures.count == 1)
        #expect("\(failures[0].1)".contains("--device"))
    }
}
