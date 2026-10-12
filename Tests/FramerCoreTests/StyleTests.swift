import CoreGraphics
import Foundation
import Testing
@testable import FramerCore

@Suite struct BackdropTests {
    let black = GradientSpec(solid: .black)
    let noText = InsetRenderer.Text(
        title: "",
        titleStyle: TextStyle(font: FontSpec(size: 30), color: .white),
        subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
        position: .top,
        spacing: 8
    )

    func render(_ backdrop: InsetRenderer.Backdrop, canvas: PixelSize = PixelSize(400, 400), pages: Int = 1) throws -> [Bitmap] {
        try InsetRenderer.render(
            layers: [], canvas: canvas, background: black, backdrop: backdrop,
            pages: Array(repeating: noText, count: pages), style: InsetRenderer.Style(padding: 20, gap: 20)
        ).map(Bitmap.init)
    }

    @Test func falloffIsLevelAtBothEnds() {
        #expect(GlowSpec.falloff(0) == 1)
        #expect(GlowSpec.falloff(1) == 0)
        #expect(GlowSpec.falloff(0.05) > 0.99)
        #expect(GlowSpec.falloff(0.95) < 0.01)
        #expect(GlowSpec.falloff(0.5) > GlowSpec.falloff(0.6))
    }

    @Test func glowFadesOutAtItsRadius() throws {
        // Centre (100, 300), radius 100 px.
        let glow = GlowSpec(x: 0.25, y: 0.75, radius: 0.25, color: RGBAColor(red: 0, green: 0, blue: 1))
        let out = try render(InsetRenderer.Backdrop(glows: [glow]))[0]
        out.expect(100, 300, .blue, tolerance: 6)
        #expect(out[150, 300].b > 80 && out[150, 300].b < 220)
        out.expect(205, 300, .black)
        out.expect(300, 100, .black)
    }

    @Test func glowsCountAcrossPanoramaPages() throws {
        let glow = GlowSpec(x: 1.5, y: 0.5, radius: 0.2, color: .white)
        let pages = try render(InsetRenderer.Backdrop(glows: [glow]), pages: 2)
        pages[0].expect(200, 200, .black)
        pages[1].expect(200, 200, .white, tolerance: 6)
    }

    @Test func imageIsPlacedWithItsOpacity() throws {
        let image = Synthetic.screenshot(size: PixelSize(100, 100), fill: .white)
        // 200x200 at (100, 100), half opaque.
        let backdrop = InsetRenderer.Backdrop(images: [.init(image: image, placement: DevicePlacement(x: 0.5, y: 0.5, width: 0.5), opacity: 0.5)])
        let out = try render(backdrop)[0]
        out.expect(200, 200, RGBA(r: 128, g: 128, b: 128, a: 255), tolerance: 3)
        out.expect(90, 200, .black)
        out.expect(310, 200, .black)
    }

    @Test func emptyBackdropChangesNothing() throws {
        let plain = try InsetRenderer.render(
            layers: [], canvas: PixelSize(100, 100), background: black, pages: [noText], style: InsetRenderer.Style(padding: 20, gap: 20)
        )[0]
        let withEmpty = try render(InsetRenderer.Backdrop(), canvas: PixelSize(100, 100))[0]
        #expect(Bitmap(plain)[50, 50] == withEmpty[50, 50])
    }
}

@Suite struct AccentTests {
    let style = TextStyle(font: FontSpec(size: 60, weight: .bold), color: .white)
    let blue = RGBAColor(red: 0, green: 0, blue: 1)

    /// Colours of the ink in the left and right halves of `text` drawn with `accent`.
    func inkHalves(_ text: String, accent: TextAccent?) -> (left: Set<String>, right: Set<String>) {
        let ctx = CGContext.makeCanvas(size: PixelSize(400, 100))
        TextRenderer.draw(text, style: style, accent: accent, in: CGRect(x: 0, y: 0, width: 400, height: 100), ctx: ctx)
        let bitmap = Bitmap(ctx.makeImage()!)
        func colours(_ columns: Range<Int>) -> Set<String> {
            Set(columns.flatMap { x in (0..<100).map { y in bitmap[x, y] } }.filter { $0.a == 255 }.map { "\($0.r),\($0.g),\($0.b)" })
        }
        return (colours(0..<200), colours(200..<400))
    }

    @Test func recoloursOnlyTheAccent() {
        let (left, right) = inkHalves("II II", accent: TextAccent(text: "II", color: blue))
        #expect(left.contains("0,0,255"))
        #expect(!left.contains("255,255,255"))
        #expect(right.contains("255,255,255"))
        #expect(!right.contains("0,0,255"))
    }

    @Test func missingAccentDrawsPlainText() {
        let (left, right) = inkHalves("II II", accent: TextAccent(text: "nope", color: blue))
        #expect(!left.union(right).contains("0,0,255"))
    }

    @Test func accentLeavesTheMetricsAlone() {
        let plain = TextRenderer.attributedString("Every secret", style: style)
        let accented = TextRenderer.attributedString("Every secret", style: style, accent: TextAccent(text: "secret", color: blue))
        #expect(CFAttributedStringGetLength(plain) == CFAttributedStringGetLength(accented))
        #expect(TextRenderer.lineWidths("Every secret", style: style, width: 2000) == TextRenderer.lineWidths("Every secret", style: style, width: 2000))
    }
}

@Suite struct TextAnchorTests {
    let canvas = PixelSize(400, 1000)

    func text(_ title: String) -> InsetRenderer.Text {
        InsetRenderer.Text(
            title: title,
            titleStyle: TextStyle(font: FontSpec(size: 30, weight: .bold), color: .white),
            subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
            position: .top,
            spacing: 8
        )
    }

    let device = PlacedRect(rect: CGRect(x: 100, y: 500, width: 200, height: 400))

    @Test func edgeKeepsTheGrownTextAtThePadding() throws {
        let style = InsetRenderer.Style(padding: 20, gap: 20, textAnchor: .edge)
        let fitted = try #require(InsetRenderer.fitText([text("Title")], around: [device], canvas: canvas, style: style))[0]
        #expect(fitted.text.titleStyle.font.size == 45)
        #expect(fitted.block.titleRect.minY == 20)
    }

    @Test func edgeStillShrinksForACrowdingDevice() throws {
        let style = InsetRenderer.Style(padding: 20, gap: 20, textAnchor: .edge)
        let base = text("Title").block(canvas: canvas, padding: 20).height
        let crowding = PlacedRect(rect: CGRect(x: 100, y: 20 + base * 0.85 + 20, width: 200, height: 400))
        let fitted = try #require(InsetRenderer.fitText([text("Title")], around: [crowding], canvas: canvas, style: style))[0]
        #expect(fitted.text.titleStyle.font.size < 30)
        #expect(fitted.block.titleRect.minY == 20)
    }

    @Test func devicesMovesTheTextDown() throws {
        let fitted = try #require(InsetRenderer.fitText([text("Title")], around: [device], canvas: canvas, style: InsetRenderer.Style(padding: 20, gap: 20)))[0]
        #expect(fitted.block.titleRect.minY > 400)
    }
}

@Suite struct CalloutShadowTests {
    let white = GradientSpec(solid: .white)
    let noText = InsetRenderer.Text(
        title: "",
        titleStyle: TextStyle(font: FontSpec(size: 30), color: .white),
        subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
        position: .top,
        spacing: 8
    )
    let region = CGRect(x: 110, y: 0, width: 20, height: 20)

    /// A 60x60 card centred on (120, 240), with the devices' shadow falling 20 px below everything.
    func render(_ shadow: CalloutShadow) throws -> Bitmap {
        let layer = InsetRenderer.Layer(framed: Synthetic.framed(), placement: DevicePlacement(x: 0.5, y: 0.5, width: 0.5))
        let spec = CalloutSpec(region: region, x: 0.2, y: 0.2, scale: 3, cornerRadius: 0, borderWidth: 0, highlight: false, shadow: shadow)
        let callout = InsetRenderer.Callout(
            spec: spec,
            image: Synthetic.screenshot(size: Synthetic.device.screenSize).cropping(to: region)!,
            region: CalloutLayout.framedRegion(region, screenshotFill: (rect: Synthetic.cutout, scale: 1))
        )
        let inherited = ShadowSpec(color: .black, radius: 0, offsetY: 20)
        return Bitmap(try InsetRenderer.render(
            layers: [layer], callouts: [callout], canvas: PixelSize(600, 1200), background: white,
            pages: [noText], style: InsetRenderer.Style(padding: 20, gap: 20, shadow: inherited)
        )[0])
    }

    @Test func inheritsTheDevicesShadowByDefault() throws {
        try render(.inherit).expect(120, 280, .black, tolerance: 10)
    }

    @Test func noneDropsIt() throws {
        let out = try render(.none)
        out.expect(120, 280, .white)
        out.expect(120, 240, .green)
    }

    @Test func customReplacesIt() throws {
        let glow = ShadowSpec(color: RGBAColor(red: 0, green: 0, blue: 1), radius: 0, offsetX: 0, offsetY: -40)
        let out = try render(.custom(glow))
        out.expect(120, 280, .white)
        out.expect(120, 195, .blue, tolerance: 10)
    }
}

@Suite struct StyleConfigTests {
    let base = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

    func jobs(_ json: String) throws -> [RenderJob] {
        try ConfigLoader.jobs(from: ConfigLoader.decode(Data(json.utf8)), baseDirectory: base)
    }

    func expectConfigError(_ json: String, containing fragment: String, sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            _ = try jobs(json)
            Issue.record("expected a config error containing '\(fragment)'", sourceLocation: sourceLocation)
        } catch {
            #expect("\(error)".contains(fragment), "\(error)", sourceLocation: sourceLocation)
        }
    }

    @Test func defaultsLeaveEverythingOff() throws {
        let inset = try #require(try jobs(##"{ "mode": "inset", "background": { "colors": ["#000"] }, "screenshots": [{ "path": "a.png", "title": "A" }] }"##)[0].inset)
        #expect(inset.glows.isEmpty)
        #expect(inset.backgroundImages.isEmpty)
        #expect(inset.accent == "")
        #expect(inset.textAnchor == .devices)
        #expect(inset.accentColor == TextConfig.defaultAccentColor)
    }

    @Test func backgroundLayersReachTheJob() throws {
        let jobs = try jobs(##"""
        {
          "mode": "inset",
          "background": {
            "colors": ["#000"],
            "glows": [{ "x": 0.2, "y": 0.8, "radius": 0.6, "color": "#3E7BFA80" }, { "color": "#FFF" }],
            "images": [{ "path": "art/glyph.png", "x": 0.1, "width": 1.2, "rotation": -12, "opacity": 0.06 }]
          },
          "screenshots": [
            { "path": "a.png", "title": "A" },
            { "path": "b.png", "title": "B", "background": { "colors": ["#111"] } }
          ]
        }
        """##)
        let inset = try #require(jobs[0].inset)
        #expect(inset.glows == [
            GlowSpec(x: 0.2, y: 0.8, radius: 0.6, color: try RGBAColor(hex: "#3E7BFA80")),
            GlowSpec(color: .white),
        ])
        #expect(inset.backgroundImages == [
            BackgroundImageSpec(input: URL(fileURLWithPath: "/tmp/project/art/glyph.png"), placement: DevicePlacement(x: 0.1, y: 0.5, width: 1.2, rotation: -12), opacity: 0.06),
        ])
        // An entry's background replaces the top-level one, layers and all.
        #expect(jobs[1].inset?.glows == [])
        #expect(jobs[1].inset?.backgroundImages == [])
    }

    @Test func backgroundLayersAreValidated() {
        expectConfigError(##"{ "mode": "inset", "background": { "colors": ["#000"], "glows": [{ "color": "#FFF", "radius": 0 }] }, "screenshots": [{ "path": "a.png" }] }"##, containing: "background.glows[0]: 'radius'")
        expectConfigError(##"{ "mode": "inset", "screenshots": [{ "path": "a.png", "background": { "colors": ["#000"], "images": [{ "path": "g.png", "opacity": 2 }] } }] }"##, containing: "screenshots[0].background.images[0]: 'opacity'")
        expectConfigError(##"{ "mode": "inset", "background": { "colors": ["#000"], "images": [{ "path": "g.png", "width": 0 }] }, "screenshots": [{ "path": "a.png" }] }"##, containing: "'width'")
        expectConfigError(##"{ "background": { "colors": ["#000"], "glows": [{ "color": "#FFF" }] }, "screenshots": [{ "path": "a.png" }] }"##, containing: "'background.glows' needs \"mode\": \"inset\"")
        expectConfigError(##"{ "background": { "colors": ["#000"], "images": [{ "path": "g.png" }] }, "screenshots": [{ "path": "a.png" }] }"##, containing: "'background.images' needs \"mode\": \"inset\"")
    }

    @Test func accentsReachTheJobAndPages() throws {
        let jobs = try jobs(##"""
        {
          "mode": "inset",
          "text": { "accentColor": "#FF9F0A", "anchor": "edge" },
          "screenshots": [
            { "path": "a.png", "title": "Every secret", "accent": "secret" },
            { "output": "tour", "devices": [{ "path": "b.png" }], "pages": [{ "title": "One", "accent": "One" }, { "title": "Two" }] }
          ]
        }
        """##)
        #expect(jobs[0].inset?.accent == "secret")
        #expect(jobs[0].inset?.accentColor == (try RGBAColor(hex: "#FF9F0A")))
        #expect(jobs[0].inset?.textAnchor == .edge)
        #expect(jobs[0].inset?.resolvedPages == [RenderJob.Page(title: "Every secret", accent: "secret")])
        #expect(jobs[1].inset?.pages == [RenderJob.Page(title: "One", accent: "One"), RenderJob.Page(title: "Two")])
    }

    @Test func accentMustBeInTheTitle() {
        expectConfigError(#"{ "mode": "inset", "screenshots": [{ "path": "a.png", "title": "Every code", "accent": "secret" }] }"#, containing: "screenshots[0]: 'accent' \"secret\" is not part of the title")
        expectConfigError(#"{ "mode": "inset", "screenshots": [{ "path": "a.png", "subtitle": "secret", "accent": "secret" }] }"#, containing: "is not part of the title")
        expectConfigError(#"{ "mode": "inset", "screenshots": [{ "devices": [{ "path": "a.png" }], "pages": [{ "title": "One" }, { "title": "Two", "accent": "One" }] }] }"#, containing: "screenshots[0].pages[1]: 'accent'")
        expectConfigError(#"{ "mode": "inset", "screenshots": [{ "accent": "One", "devices": [{ "path": "a.png" }], "pages": [{ "title": "One" }, { "title": "Two" }] }] }"#, containing: "put each 'accent' in its page instead")
    }

    @Test func calloutShadowAcceptsTrueFalseOrObject() throws {
        let jobs = try jobs(##"""
        {
          "mode": "inset",
          "screenshots": [{
            "path": "a.png",
            "callouts": [
              { "region": { "x": 0, "y": 0, "width": 1, "height": 1 } },
              { "region": { "x": 0, "y": 0, "width": 1, "height": 1 }, "shadow": false },
              { "region": { "x": 0, "y": 0, "width": 1, "height": 1 }, "shadow": true },
              { "region": { "x": 0, "y": 0, "width": 1, "height": 1 }, "shadow": { "color": "#3E7BFA", "radius": 90, "offsetY": 0 } }
            ]
          }]
        }
        """##)
        let shadows = try #require(jobs[0].inset?.callouts.map(\.shadow))
        #expect(shadows == [
            .inherit,
            .none,
            .custom(ShadowSpec()),
            .custom(ShadowSpec(color: try RGBAColor(hex: "#3E7BFA"), radius: 90, offsetY: 0)),
        ])
    }
}

@Suite struct CalloutOffsetTests {
    let device = PlacedRect(rect: CGRect(x: 100, y: 100, width: 150, height: 300))
    let framedSize = PixelSize(300, 600)
    let page = PixelSize(1000, 1000)
    let region = CGRect(x: 100, y: 200, width: 40, height: 20)

    @Test func movesTheCardInTheDevicesPixels() {
        // Device is drawn at half size, so 20 framed pixels down is 10 on the canvas.
        let spec = CalloutSpec(region: .zero, offsetX: -8, offsetY: 20, scale: 2)
        let result = CalloutLayout.compute(spec, region: region, offset: CGSize(width: -8, height: 20), device: device, framedSize: framedSize, page: page)
        #expect(result.card.center == CGPoint(x: 160 - 4, y: 205 + 10))
        #expect(result.source.center == CGPoint(x: 160, y: 205))
    }

    @Test func followsTheDevicesTilt() {
        var rotated = device
        rotated.rotation = 90
        let spec = CalloutSpec(region: .zero, scale: 1)
        let plain = CalloutLayout.compute(spec, region: region, device: rotated, framedSize: framedSize, page: page)
        let moved = CalloutLayout.compute(spec, region: region, offset: CGSize(width: 0, height: 20), device: rotated, framedSize: framedSize, page: page)
        // The device's "down" points left once it's turned 90° clockwise.
        #expect(abs(moved.card.center.x - (plain.card.center.x - 10)) < 0.001)
        #expect(abs(moved.card.center.y - plain.card.center.y) < 0.001)
    }

    @Test func movesAnExplicitPositionToo() {
        let spec = CalloutSpec(region: .zero, x: 0.5, y: 0.25, scale: 1)
        let result = CalloutLayout.compute(spec, region: region, offset: CGSize(width: 40, height: 0), device: device, framedSize: framedSize, page: page)
        #expect(result.card.center == CGPoint(x: 520, y: 250))
    }

    @Test func offsetIsInScreenshotPixels() {
        let spec = CalloutSpec(region: .zero, offsetX: 10, offsetY: -4)
        #expect(CalloutLayout.framedOffset(spec, screenshotFill: (rect: .zero, scale: 0.5)) == CGSize(width: 5, height: -2))
    }

    @Test func configReachesTheSpec() throws {
        let jobs = try ConfigLoader.jobs(from: ConfigLoader.decode(Data(#"""
        { "mode": "inset", "screenshots": [{ "path": "a.png", "callouts": [
          { "region": { "x": 0, "y": 0, "width": 1, "height": 1 }, "offsetY": 34 },
          { "region": { "x": 0, "y": 0, "width": 1, "height": 1 } }
        ] }] }
        """#.utf8)), baseDirectory: URL(fileURLWithPath: "/tmp"))
        let callouts = try #require(jobs[0].inset?.callouts)
        #expect(callouts[0].offsetX == 0 && callouts[0].offsetY == 34)
        #expect(callouts[1].offsetX == 0 && callouts[1].offsetY == 0)
    }
}
