import CoreGraphics
import Foundation
import Testing
@testable import FramerCore

@Suite struct UnclampedOutputTests {
    let native = PixelSize(1206, 2622)
    let framed = PixelSize(1350, 2760)

    @Test func keepsASizeBeyondTheNative() {
        let r = OutputSizing.resolve(requestedWidth: 3840, requestedHeight: 1646, native: native, framedSize: framed, clamp: false)
        #expect(r == OutputSizing.Result(size: PixelSize(3840, 1646), clamped: false))
    }

    @Test func oneDimensionStillFollowsTheFramedAspect() {
        let r = OutputSizing.resolve(requestedWidth: 2700, requestedHeight: nil, native: native, framedSize: framed, clamp: false)
        #expect(r.size == PixelSize(2700, 5520))
        #expect(!r.clamped)
    }

    @Test func clampsByDefault() {
        let r = OutputSizing.resolve(requestedWidth: 3840, requestedHeight: 1646, native: native, framedSize: framed)
        #expect(r.size == PixelSize(1206, 1646))
        #expect(r.clamped)
    }
}

@Suite struct OpaqueOutputTests {
    @Test func opaquePNGHasNoAlphaAndIsFlattenedOntoWhite() throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("out.png")
        try ImageWriter.write(Synthetic.framed(), to: url, format: .png, opaque: true)
        let loaded = try ImageLoader.load(url)
        #expect([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(loaded.alphaInfo))
        let bitmap = Bitmap(loaded)
        bitmap.expect(1, 1, .white)
        bitmap.expect(150, 300, .red)
    }

    @Test func pngKeepsAlphaByDefault() throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("out.png")
        try ImageWriter.write(Synthetic.framed(), to: url, format: .png)
        Bitmap(try ImageLoader.load(url)).expect(1, 1, .clear)
    }
}

@Suite struct OutputConfigTests {
    func job(_ json: String) throws -> RenderJob {
        try ConfigLoader.jobs(from: ConfigLoader.decode(Data(json.utf8)), baseDirectory: URL(fileURLWithPath: "/tmp/project"))[0]
    }

    @Test func defaultsClampAndKeepAlpha() throws {
        let job = try job(#"{ "screenshots": [{ "path": "a.png" }] }"#)
        #expect(job.clampsSize)
        #expect(!job.opaque)
    }

    @Test func clampAndOpaqueReachTheJob() throws {
        let job = try job(#"{ "output": { "width": 3840, "height": 1646, "clamp": false, "opaque": true }, "screenshots": [{ "path": "a.png" }] }"#)
        #expect(!job.clampsSize)
        #expect(job.opaque)
    }

    @Test func rendersACanvasLargerThanTheScreenshot() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (renderer, shot) = try RendererTests.syntheticSetup(in: dir)
        let job = RenderJob(
            input: shot,
            outputBase: dir.appendingPathComponent("out/wide"),
            mode: .inset,
            requestedWidth: 3000,
            requestedHeight: 1500,
            clampsSize: false,
            opaque: true,
            background: GradientSpec(solid: RGBAColor(red: 0, green: 0, blue: 1)),
            inset: RenderJob.InsetSettings(
                title: "Wide", subtitle: "",
                titleStyle: TextStyle(font: FontSpec(size: 40, weight: .bold), color: .white),
                subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
                position: .top, spacing: 8, padding: 30, gap: 30, deviceScale: 1
            )
        )
        let (outcomes, failures) = await renderer.run([job])
        #expect(failures.isEmpty, "\(failures.map { "\($0.1)" })")
        let outcome = try #require(outcomes.first)
        #expect(outcome.size == PixelSize(3000, 1500))
        let image = try ImageLoader.load(outcome.output)
        #expect(image.pixelSize == PixelSize(3000, 1500))
        #expect([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))
        Bitmap(image).expect(2, 2, .blue)
    }
}
