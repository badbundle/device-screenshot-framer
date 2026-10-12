import CoreGraphics
import Foundation
import Testing
@testable import FramerCore

/// A fake MacBook: a 400x260 gray body drawn landscape, with a square 320x200 screen cut out at (40, 30).
enum SyntheticMac {
    static let frameSize = PixelSize(400, 260)
    static let cutout = CGRect(x: 40, y: 30, width: 320, height: 200)

    static func frame() -> CGImage {
        let ctx = CGContext.makeCanvas(size: frameSize)
        ctx.fill(CGRect(x: 5, y: 5, width: 390, height: 250), color: RGBAColor(red: 0.5, green: 0.5, blue: 0.5))
        ctx.clear(cutout.flipped(in: Double(frameSize.height)))
        return ctx.makeImage()!
    }

    /// A renderer whose store serves the fake frame as the MacBook Air, and that frame's screen at the Air's size.
    static func setup(in dir: URL) throws -> (renderer: Renderer, shot: URL) {
        let framePNG = dir.appendingPathComponent("mac-frame.png")
        try ImageWriter.write(frame(), to: framePNG, format: .png)
        let shot = dir.appendingPathComponent("desktop.png")
        try ImageWriter.write(Synthetic.screenshot(size: PixelSize(2560, 1600)), to: shot, format: .png)
        let server = FakeServer([
            "version.txt": Data("7".utf8),
            "files.json": Data(#"["Apple MacBook Air Space Gray.png"]"#.utf8),
            "offsets.json": Data(#"{ "portrait": { "MacBook Air": { "offset": "+40+30", "width": 320 } } }"#.utf8),
            "Apple MacBook Air Space Gray.png": try Data(contentsOf: framePNG),
        ])
        let store = FrameStore(cacheRoot: dir.appendingPathComponent("cache"), baseURL: URL(string: "https://example.test/")!, fetch: server.fetch)
        return (Renderer(store: store), shot)
    }
}

@Suite struct MacFrameTests {
    @Test func landscapeFrameIsDrawnAsItIs() {
        let geometry = FrameGeometry.oriented(
            frameSize: SyntheticMac.frameSize,
            cutout: SyntheticMac.cutout,
            orientation: .landscape,
            side: .left,
            frameOrientation: .landscape
        )
        #expect(geometry.canvasSize == SyntheticMac.frameSize)
        #expect(geometry.cutout == SyntheticMac.cutout)
        #expect(geometry.frameTransform == .identity)
    }

    @Test func portraitScreenshotTurnsALandscapeFrame() {
        let geometry = FrameGeometry.oriented(
            frameSize: SyntheticMac.frameSize,
            cutout: SyntheticMac.cutout,
            orientation: .portrait,
            side: .left,
            frameOrientation: .landscape
        )
        #expect(geometry.canvasSize == SyntheticMac.frameSize.swapped)
        #expect(geometry.cutout.size == CGSize(width: 200, height: 320))
    }

    @Test func compositesIntoTheLandscapeFrame() {
        let geometry = FrameGeometry.oriented(
            frameSize: SyntheticMac.frameSize, cutout: SyntheticMac.cutout, orientation: .landscape, side: .left, frameOrientation: .landscape
        )
        let framed = Bitmap(FrameCompositor.composite(FrameCompositor.Input(
            screenshot: Synthetic.screenshot(size: PixelSize(320, 200)), frame: SyntheticMac.frame(), geometry: geometry, cornerRadius: 0
        )))
        #expect(framed.width == 400 && framed.height == 260)
        framed.expect(200, 130, .red)
        framed.expect(200, 35, .green)                // the screenshot's top stays on top
        framed.expect(41, 31, .blue)                  // square screen corners
        framed.expect(20, 130, .gray)
        framed.expect(1, 1, .clear)
    }

    @Test func macCanvasDefaultsToTheLargestMacAppStoreSize() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (renderer, shot) = try SyntheticMac.setup(in: dir)
        let (outcomes, _) = await renderer.run([RenderJob(input: shot, outputBase: dir.appendingPathComponent("out/mac"))])
        #expect(try #require(outcomes.first).size == PixelSize(2880, 1800))
    }

    @Test func detectsAndFramesAFullScreenCapture() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (renderer, shot) = try SyntheticMac.setup(in: dir)

        let job = RenderJob(input: shot, outputBase: dir.appendingPathComponent("out/mac"), requestedWidth: 800)
        let (outcomes, failures) = await renderer.run([job])
        #expect(failures.isEmpty, "\(failures.map { "\($0.1)" })")
        let outcome = try #require(outcomes.first)
        #expect(outcome.device?.name == "MacBook Air")
        #expect(outcome.frameColor == "Space Gray")
        #expect(outcome.screens[0].orientation == .landscape)
        #expect(outcome.size == PixelSize(800, 500))   // 16:10, as the Mac App Store's sizes are
        let bitmap = Bitmap(try ImageLoader.load(outcome.output))
        bitmap.expect(400, 250, .red)
        bitmap.expect(1, 250, .clear)
        bitmap.expect(40, 250, .gray, tolerance: 10)
    }
}

@Suite struct WindowTests {
    let style = WindowStyle(cornerRadius: 20, borderWidth: 4, borderColor: RGBAColor(red: 0, green: 1, blue: 0))

    @Test func roundsTheCornersAndDrawsAHairline() {
        let window = Bitmap(WindowCompositor.composite(Synthetic.screenshot(size: PixelSize(200, 100), fill: .white), style: style))
        #expect(window.width == 200 && window.height == 100)
        window.expect(0, 0, .clear)
        window.expect(199, 99, .clear)
        window.expect(50, 50, .white)
        window.expect(50, 1, .green)
        window.expect(1, 50, .green)
        window.expect(50, 6, .white)
    }

    @Test func hairlineStaysOnACaptureWithItsOwnCorners() {
        // A capture whose corners are already cut, further in than the style's radius.
        let ctx = CGContext.makeCanvas(size: PixelSize(200, 100))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 100), cornerWidth: 40, cornerHeight: 40, transform: nil))
        ctx.setFillColor(RGBAColor.white.cgColor)
        ctx.fillPath()
        let window = Bitmap(WindowCompositor.composite(ctx.makeImage()!, style: style))
        window.expect(6, 6, .clear)                   // inside the style's corner, outside the capture's
        window.expect(100, 1, .green)
    }

    @Test func noBorderLeavesTheEdgeAlone() {
        let window = Bitmap(WindowCompositor.composite(
            Synthetic.screenshot(size: PixelSize(200, 100), fill: .white), style: WindowStyle(cornerRadius: 0, borderWidth: 0)
        ))
        window.expect(0, 0, .blue)
        window.expect(50, 1, .white)
    }

    func renderer(in dir: URL) -> Renderer {
        // Offline with an empty cache: a window never needs the frames.
        Renderer(store: FrameStore(cacheRoot: dir.appendingPathComponent("cache"), baseURL: URL(string: "https://example.test/")!, offline: true, fetch: FakeServer([:]).fetch))
    }

    func windowShot(in dir: URL, size: PixelSize = PixelSize(1000, 600)) throws -> URL {
        let shot = dir.appendingPathComponent("window.png")
        try ImageWriter.write(Synthetic.screenshot(size: size), to: shot, format: .png)
        return shot
    }

    @Test func anySizeRendersOnTheLargestMacAppStoreCanvas() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = RenderJob(input: try windowShot(in: dir), outputBase: dir.appendingPathComponent("out/window"), frameStyle: .window, window: style)

        let (outcomes, failures) = await renderer(in: dir).run([job])
        #expect(failures.isEmpty, "\(failures.map { "\($0.1)" })")
        let outcome = try #require(outcomes.first)
        #expect(outcome.device == nil)
        #expect(outcome.frameColor == nil)
        #expect(outcome.screens[0].frameStyle == .window)
        #expect(outcome.size == PixelSize(2880, 1800))
        let bitmap = Bitmap(try ImageLoader.load(outcome.output))
        // 1000x600 aspect-fits at 2.88x: 2880x1728, 36 px from the top.
        bitmap.expect(1440, 900, .red)
        bitmap.expect(720, 40, .green, tolerance: 10)  // the hairline, scaled with the window
        bitmap.expect(720, 30, .clear)
        bitmap.expect(1, 900, .green, tolerance: 10)  // and fills the width
        bitmap.expect(2, 38, .clear)
    }

    static let canvasRequests: [(width: Int?, height: Int?, expected: PixelSize)] = [
        (1440, nil, PixelSize(1440, 900)),
        (nil, 800, PixelSize(1280, 800)),
        (4000, 2500, PixelSize(2880, 1800)),
    ]

    @Test(arguments: canvasRequests)
    func windowCanvasFollowsTheMacAppStore(_ request: (width: Int?, height: Int?, expected: PixelSize)) async throws {
        let (width, height, expected) = request
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let job = RenderJob(
            input: try windowShot(in: dir), outputBase: dir.appendingPathComponent("out/window"), frameStyle: .window,
            requestedWidth: width, requestedHeight: height
        )
        let (outcomes, _) = await renderer(in: dir).run([job])
        #expect(try #require(outcomes.first).size == expected)
    }

    @Test func windowsCastAShadowOfTheirOwnInInsetMode() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let shot = try windowShot(in: dir)
        func render(shadow: ShadowSpec?) async throws -> Bitmap {
            var inset = RendererTests.insetSettings(devices: [
                RenderJob.PlacedDevice(input: shot, frameStyle: .window, placement: DevicePlacement(x: 0.5, y: 0.5, width: 0.5)),
            ])
            inset.title = ""
            inset.shadow = shadow
            let job = RenderJob(
                input: shot, outputBase: dir.appendingPathComponent("out/window"), mode: .inset, frameStyle: .window,
                window: style, requestedWidth: 1600, requestedHeight: 1000,
                background: GradientSpec(solid: .white), inset: inset
            )
            let (outcomes, failures) = await renderer(in: dir).run([job])
            #expect(failures.isEmpty, "\(failures.map { "\($0.1)" })")
            return Bitmap(try ImageLoader.load(try #require(outcomes.first).output))
        }
        // The window is 800x480 at (400, 260): its bottom edge is at y = 740.
        let own = try await render(shadow: nil)
        own.expect(800, 500, .red)
        #expect(own[800, 760].r < 230, "the default shadow darkens the background below: \(own[800, 760])")
        own.expect(800, 990, .white, tolerance: 6)

        let configured = try await render(shadow: ShadowSpec(color: .black, radius: 0, offsetY: 40))
        configured.expect(800, 760, .black, tolerance: 10)
    }

    @Test func callsOutPartOfAWindow() async throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let shot = try windowShot(in: dir)
        var inset = RendererTests.insetSettings(callouts: [
            CalloutSpec(region: CGRect(x: 490, y: 0, width: 20, height: 20), x: 0.25, y: 0.2, scale: 4, borderWidth: 0),
        ])
        inset.title = ""
        let job = RenderJob(
            input: shot, outputBase: dir.appendingPathComponent("out/window"), mode: .inset, frameStyle: .window,
            requestedWidth: 1600, requestedHeight: 1000, background: GradientSpec(solid: .white), inset: inset
        )
        let (outcomes, failures) = await renderer(in: dir).run([job])
        #expect(failures.isEmpty, "\(failures.map { "\($0.1)" })")
        let bitmap = Bitmap(try ImageLoader.load(try #require(outcomes.first).output))
        bitmap.expect(400, 200, .green)               // the green marker at the window's top-centre, enlarged
    }
}

@Suite struct LandscapeLayoutTests {
    @Test func shareOfPageDefaultsUseTheShorterSide() {
        let landscape = PixelSize(2880, 1800)
        let portrait = PixelSize(1320, 2868)
        #expect(landscape.shorterSide == 1800)
        #expect(portrait.shorterSide == 1320)
        let callout = CalloutSpec(region: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(callout.resolvedCornerRadius(page: landscape) == 54)
        #expect(callout.resolvedCornerRadius(page: portrait) == 40)
        #expect(callout.resolvedBorderWidth(page: landscape) == 14)
    }

    @Test func automaticLayoutFitsALandscapeDeviceUnderTheText() throws {
        let layout = try InsetLayout.compute(InsetLayout.Input(
            canvas: PixelSize(1600, 1000), padding: 50, gap: 40, spacing: 0,
            titleHeight: 100, subtitleHeight: 0, framedSize: PixelSize(800, 500), position: .top
        ))
        #expect(layout.titleRect == CGRect(x: 50, y: 50, width: 1500, height: 100))
        // Area below the text: 1500 x 760, so the height limits a 16:10 device.
        #expect(layout.deviceRect == CGRect(x: 192, y: 190, width: 1216, height: 760))
    }

    @Test func textSitsAboveAPlacedLandscapeDeviceOnEveryPage() throws {
        let canvas = PixelSize(1600, 1000)
        let text = InsetRenderer.Text(
            title: "Title",
            titleStyle: TextStyle(font: FontSpec(size: 60, weight: .bold), color: .white),
            subtitleStyle: TextStyle(font: FontSpec(size: 30), color: .white),
            position: .top,
            spacing: 8
        )
        let devices = [
            PlacedRect(rect: CGRect(x: 200, y: 500, width: 1200, height: 750)),
            PlacedRect(rect: CGRect(x: 1800, y: 500, width: 1200, height: 750)),
        ]
        let fitted = try #require(InsetRenderer.fitText([text, text], around: devices, canvas: canvas, style: InsetRenderer.Style(padding: 50, gap: 40)))
        #expect(fitted.count == 2)
        for (index, page) in fitted.enumerated() {
            #expect(abs(page.block.titleRect.minX - (Double(index) * 1600 + 50)) < 0.5)
            #expect(abs(page.block.titleRect.minY + page.block.height - 460) <= 1, "page \(index) ends gap above the device")
        }
    }
}

@Suite struct FrameStyleConfigTests {
    let base = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

    @Test func frameInheritsFromDeviceThenEntryThenTopLevel() throws {
        let config = try ConfigLoader.decode(Data(#"""
        {
          "mode": "inset",
          "frame": "window",
          "window": { "cornerRadius": 24, "borderColor": "#FFFFFF33" },
          "screenshots": [
            { "path": "a.png", "title": "A" },
            { "path": "b.png", "frame": "device", "devices": [{ "x": 0.3 }, { "path": "c.png", "frame": "window" }] }
          ]
        }
        """#.utf8))
        #expect(config.frame == .window)
        #expect(config.window == WindowConfig(cornerRadius: 24, borderColor: try RGBAColor(hex: "#FFFFFF33")))
        let jobs = try ConfigLoader.jobs(from: config, baseDirectory: base)
        #expect(jobs[0].frameStyle == .window)
        #expect(jobs[0].window == WindowStyle(cornerRadius: 24, borderColor: try RGBAColor(hex: "#FFFFFF33")))
        #expect(!jobs[0].needsFrames)
        #expect(jobs[1].frameStyle == .device)
        #expect(jobs[1].inset?.devices.map(\.frameStyle) == [.device, .window])
        #expect(jobs[1].needsFrames)
    }

    @Test func defaultsToDeviceFrames() throws {
        let config = try ConfigLoader.decode(Data(#"{ "screenshots": [{ "path": "a.png" }] }"#.utf8))
        #expect(config.frame == .device)
        #expect(config.window == WindowConfig())
        #expect(try ConfigLoader.jobs(from: config, baseDirectory: base)[0].frameStyle == .device)
        #expect(throws: FramerError.self) { try ConfigLoader.decode(Data(#"{ "frame": "browser", "screenshots": [] }"#.utf8)) }
    }
}
