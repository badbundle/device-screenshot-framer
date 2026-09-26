import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import FramerCore

@Suite struct FrameCompositorTests {
    @Test func portraitComposite() {
        let framed = Bitmap(Synthetic.framed())
        #expect(framed.width == 300 && framed.height == 600)
        framed.expect(150, 300, .red)                 // screen centre shows the screenshot
        framed.expect(15, 300, .gray)                 // bezel
        framed.expect(150, 58, .black)                // island drawn on top of the screenshot
        framed.expect(1, 1, .clear)                   // outside the body
        framed.expect(30, 40, .clear)                 // exact cutout corner: rounded clip removes it
        framed.expect(45, 55, .red)                   // just inside the corner radius
        // Orientation marker: green square sits at the top-centre of the screen.
        framed.expect(150, 45, .green)
    }

    @Test func landscapeLeftPutsTopOnLeft() {
        let framed = Bitmap(Synthetic.framed(orientation: .landscape, side: .left))
        #expect(framed.width == 600 && framed.height == 300)
        framed.expect(300, 150, .red)
        framed.expect(58, 150, .black)                // island now on the left
        framed.expect(300, 35, .green)                // landscape screenshot's own top edge stays on top
        framed.expect(300, 15, .gray)
    }

    @Test func landscapeRightPutsTopOnRight() {
        let framed = Bitmap(Synthetic.framed(orientation: .landscape, side: .right))
        framed.expect(541, 150, .black)               // island on the right
        framed.expect(300, 35, .green)
        framed.expect(300, 150, .red)
        framed.expect(58, 150, .red)                  // nothing on the left
    }

    @Test func mismatchedScreenshotIsAspectFilled() {
        // Slightly taller screenshot than the cutout: still fully covered, no gaps at the edges.
        let framed = Bitmap(Synthetic.framed(screenshotSize: PixelSize(240, 540)))
        framed.expect(150, 300, .red)
        framed.expect(150, 300 + 250, .red)
        framed.expect(150, 300 - 225, .red)
    }
}

@Suite struct SimpleRendererTests {
    @Test func fitsAndCentresWithTransparentPadding() {
        let out = Bitmap(SimpleRenderer.render(framed: Synthetic.framed(), canvas: PixelSize(300, 800), background: nil))
        #expect(out.width == 300 && out.height == 800)
        out.expect(150, 50, .clear)                   // padding above
        out.expect(150, 750, .clear)                  // padding below
        out.expect(150, 400, .red)                    // centre
        out.expect(15, 400, .gray)
    }

    @Test func backgroundFillsPadding() {
        let bg = GradientSpec(solid: RGBAColor(red: 0, green: 0, blue: 1))
        let out = Bitmap(SimpleRenderer.render(framed: Synthetic.framed(), canvas: PixelSize(300, 800), background: bg))
        out.expect(150, 50, .blue)
        out.expect(1, 1, .blue)
        out.expect(150, 400, .red)
    }

    @Test func downscalesToSmallerCanvas() {
        let out = Bitmap(SimpleRenderer.render(framed: Synthetic.framed(), canvas: PixelSize(150, 300), background: nil))
        #expect(out.width == 150 && out.height == 300)
        out.expect(75, 150, .red)
    }
}

@Suite struct TextRendererTests {
    let style = TextStyle(font: FontSpec(size: 40, weight: .bold), color: .white)

    @Test func systemBoldHasBoldTrait() {
        let regular = TextRenderer.makeFont(FontSpec(size: 40))
        let bold = TextRenderer.makeFont(FontSpec(size: 40, weight: .bold))
        let traits = CTFontCopyTraits(bold) as! [CFString: Any]
        let weight = traits[kCTFontWeightTrait] as! Double
        #expect(weight >= 0.3)
        #expect(CTFontCopyPostScriptName(regular) as String != CTFontCopyPostScriptName(bold) as String)
    }

    @Test func unknownFontFallsBackToSystem() {
        let font = TextRenderer.makeFont(FontSpec(name: "Definitely Not A Font", size: 20))
        let system = TextRenderer.makeFont(FontSpec(size: 20))
        #expect(CTFontCopyFamilyName(font) as String == CTFontCopyFamilyName(system) as String)
    }

    @Test func namedFontIsUsed() {
        let font = TextRenderer.makeFont(FontSpec(name: "Helvetica", size: 20))
        #expect((CTFontCopyFamilyName(font) as String) == "Helvetica")
    }

    @Test func measureHeightWraps() {
        let one = TextRenderer.measureHeight("Hello", style: style, width: 2000)
        #expect(one > 40 && one < 70)
        let many = TextRenderer.measureHeight("Hello wrapped text that is quite long indeed", style: style, width: 200)
        #expect(many >= one * 2)
        #expect(TextRenderer.measureHeight("", style: style, width: 200) == 0)
        let newline = TextRenderer.measureHeight("a\nb", style: style, width: 2000)
        #expect(newline >= one * 1.8)
    }

    @Test func drawsCentred() {
        let ctx = CGContext.makeCanvas(size: PixelSize(400, 100))
        TextRenderer.draw("II", style: style, in: CGRect(x: 0, y: 0, width: 400, height: 100), ctx: ctx)
        let bitmap = Bitmap(ctx.makeImage()!)
        func inkColumns(_ range: Range<Int>) -> Int {
            range.filter { x in (0..<100).contains { y in bitmap[x, y].a > 0 } }.count
        }
        #expect(inkColumns(0..<150) == 0, "no ink far left")
        #expect(inkColumns(250..<400) == 0, "no ink far right")
        #expect(inkColumns(150..<250) > 0, "ink in the middle")
        // Text starts at the top of the rect.
        #expect((0..<400).contains { x in bitmap[x, 10].a > 0 })
        #expect(!(0..<400).contains { x in bitmap[x, 90].a > 0 })
    }
}

@Suite struct InsetRendererTests {
    let text = InsetRenderer.Text(
        title: "Title",
        subtitle: "Sub",
        titleStyle: TextStyle(font: FontSpec(size: 30, weight: .bold), color: .white),
        subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
        position: .top,
        spacing: 8
    )
    let background = GradientSpec(colors: [RGBAColor(red: 0, green: 0, blue: 1), RGBAColor(red: 0, green: 1, blue: 0)], angleDegrees: 180)

    @Test func textTopDevicePinnedBottom() throws {
        let canvas = PixelSize(400, 1000)
        let out = Bitmap(try InsetRenderer.render(
            framed: Synthetic.framed(), canvas: canvas, background: background, text: text,
            style: InsetRenderer.Style(padding: 20, gap: 20)
        ))
        #expect(out.width == 400 && out.height == 1000)
        out.expect(2, 2, .blue, tolerance: 8)                       // gradient start, outside text
        // Device bottom edge = canvas height - padding. The synthetic body is inset 5px (x scale) from the
        // frame edge, so probe 12px inside; just outside the edge must be background.
        #expect(out[200, 1000 - 20 - 12].isClose(to: .gray, tolerance: 40))
        #expect(!out[200, 1000 - 20 + 2].isClose(to: .gray, tolerance: 40))
        // Screen shows the screenshot.
        let hasRed = (400..<980).contains { y in out[200, y].isClose(to: .red, tolerance: 10) }
        #expect(hasRed)
        // Title ink exists near the top.
        let inkTop = (20..<60).contains { y in (0..<400).contains { x in out[x, y].isClose(to: .white, tolerance: 40) } }
        #expect(inkTop)
    }

    @Test func textBottomDevicePinnedTop() throws {
        var bottomText = text
        bottomText.position = .bottom
        let out = Bitmap(try InsetRenderer.render(
            framed: Synthetic.framed(), canvas: PixelSize(400, 1000), background: background, text: bottomText,
            style: InsetRenderer.Style(padding: 20, gap: 20)
        ))
        #expect(out[200, 20 + 12].isClose(to: .gray, tolerance: 40))  // device top edge at padding
        #expect(!out[200, 18].isClose(to: .gray, tolerance: 40))
    }

    @Test func tooMuchTextThrows() {
        var huge = text
        huge.titleStyle.font.size = 900
        #expect(throws: FramerError.self) {
            try InsetRenderer.render(
                framed: Synthetic.framed(), canvas: PixelSize(400, 1000), background: background, text: huge,
                style: InsetRenderer.Style(padding: 20, gap: 20)
            )
        }
    }
}

@Suite struct ImageIOTests {
    @Test func pngRoundTripKeepsAlpha() throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/out.png")
        try ImageWriter.write(Synthetic.framed(), to: url, format: .png)
        let loaded = try ImageLoader.load(url)
        #expect(loaded.pixelSize == PixelSize(300, 600))
        #expect(try ImageLoader.size(of: url) == PixelSize(300, 600))
        let bitmap = Bitmap(loaded)
        bitmap.expect(1, 1, .clear)
        bitmap.expect(150, 300, .red)
    }

    @Test func jpegIsFlattenedOntoWhite() throws {
        let dir = try Synthetic.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("out.jpg")
        try ImageWriter.write(Synthetic.framed(), to: url, format: .jpeg)
        let bitmap = Bitmap(try ImageLoader.load(url))
        bitmap.expect(1, 1, .white, tolerance: 8)
        bitmap.expect(150, 300, .red, tolerance: 12)
    }

    @Test func unreadableFileThrows() {
        #expect(throws: FramerError.self) { try ImageLoader.load(URL(fileURLWithPath: "/nonexistent.png")) }
    }
}

@Suite struct PlacedRenderTests {
    let blue = GradientSpec(solid: RGBAColor(red: 0, green: 0, blue: 1))
    let noText = InsetRenderer.Text(
        title: "",
        titleStyle: TextStyle(font: FontSpec(size: 30), color: .white),
        subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
        position: .top,
        spacing: 8
    )

    func render(
        _ layers: [InsetRenderer.Layer],
        callouts: [InsetRenderer.Callout] = [],
        canvas: PixelSize,
        background: GradientSpec? = nil,
        pages: Int = 1,
        style: InsetRenderer.Style = InsetRenderer.Style(padding: 20, gap: 20)
    ) throws -> [Bitmap] {
        try InsetRenderer.render(
            layers: layers, callouts: callouts, canvas: canvas, background: background ?? blue,
            pages: Array(repeating: noText, count: pages), style: style
        ).map(Bitmap.init)
    }

    @Test func rotatesClockwiseAboutTheCentre() throws {
        let placement = DevicePlacement(x: 0.5, y: 0.5, width: 0.3, rotation: 90)
        let out = try render([InsetRenderer.Layer(framed: Synthetic.framed(), placement: placement)], canvas: PixelSize(1000, 1000))[0]
        out.expect(500, 250, .blue)                   // would be device if upright
        #expect(!out[250, 500].isClose(to: .blue, tolerance: 40))
        #expect(!out[750, 500].isClose(to: .blue, tolerance: 40))
        out.expect(742, 500, .black, tolerance: 10)   // island swung to the right
    }

    @Test func bleedRunsOffTheFarEdge() throws {
        let text = InsetRenderer.Text(
            title: "Title", subtitle: "Sub",
            titleStyle: TextStyle(font: FontSpec(size: 30, weight: .bold), color: .white),
            subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
            position: .top, spacing: 8
        )
        let out = Bitmap(try InsetRenderer.render(
            framed: Synthetic.framed(), canvas: PixelSize(400, 700), background: blue, text: text,
            style: InsetRenderer.Style(padding: 20, gap: 20, bleed: true)
        ))
        out.expect(200, 699, .red)                    // screen reaches the bottom edge
        out.expect(2, 699, .blue)                     // sides keep the padding
    }

    @Test func panoramaSplitsOneCanvasIntoPages() throws {
        let placement = DevicePlacement(x: 1, y: 0.5, width: 0.5)
        let pages = try render([InsetRenderer.Layer(framed: Synthetic.framed(), placement: placement)], canvas: PixelSize(400, 400), pages: 2)
        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.width == 400 && $0.height == 400 })
        #expect(!pages[0][395, 200].isClose(to: .blue, tolerance: 40))
        #expect(!pages[1][5, 200].isClose(to: .blue, tolerance: 40))
        pages[0].expect(100, 200, .blue)
        pages[1].expect(300, 200, .blue)
    }

    @Test func gradientSpansAllPages() throws {
        let gradient = GradientSpec(colors: [.black, .white], angleDegrees: 90)
        let pages = try render([], canvas: PixelSize(100, 100), background: gradient, pages: 2)
        pages[0].expect(0, 50, .black, tolerance: 8)
        pages[1].expect(99, 50, .white, tolerance: 8)
        #expect(pages[0][99, 50].r > 100 && pages[0][99, 50].r < 156)
    }

    @Test func shadowFallsBelowTheDevice() throws {
        let white = GradientSpec(solid: .white)
        let layer = InsetRenderer.Layer(framed: Synthetic.framed(), placement: DevicePlacement(x: 0.5, y: 0.5, width: 0.5))
        // Device 300x600 at (150, 200); synthetic body bottom edge at y = 795.
        let plain = try render([layer], canvas: PixelSize(600, 1000), background: white)[0]
        plain.expect(300, 805, .white)
        let shadow = ShadowSpec(color: .black, radius: 0, offsetY: 20)
        let shaded = try render([layer], canvas: PixelSize(600, 1000), background: white, style: InsetRenderer.Style(padding: 20, gap: 20, shadow: shadow))[0]
        shaded.expect(300, 805, .black, tolerance: 10)
        shaded.expect(300, 500, .red)
    }

    @Test func calloutMagnifiesTheRegionWithBorderAndHighlight() throws {
        let layer = InsetRenderer.Layer(framed: Synthetic.framed(), placement: DevicePlacement(x: 0.5, y: 0.5, width: 0.5))
        // The green marker at the top-centre of the 240x520 screenshot; the device is drawn at scale 1 at (150, 300).
        let region = CGRect(x: 110, y: 0, width: 20, height: 20)
        let spec = CalloutSpec(region: region, x: 0.2, y: 0.2, scale: 3, cornerRadius: 0, borderWidth: 4)
        let callout = InsetRenderer.Callout(
            spec: spec,
            image: Synthetic.screenshot(size: Synthetic.device.screenSize).cropping(to: region)!,
            region: CalloutLayout.framedRegion(region, screenshotFill: (rect: Synthetic.cutout, scale: 1))
        )
        let out = try render([layer], callouts: [callout], canvas: PixelSize(600, 1200))[0]
        // Card: 60x60 centred on (120, 240).
        out.expect(120, 240, .green)
        out.expect(92, 240, .white)
        out.expect(80, 240, .blue)
        // Source region on the device is (290, 340) 20x20; the outline sits just outside it.
        out.expect(288, 350, .white, tolerance: 40)
    }

    @Test func severalUnplacedDevicesThrow() {
        #expect(throws: FramerError.self) {
            try render([InsetRenderer.Layer(framed: Synthetic.framed()), InsetRenderer.Layer(framed: Synthetic.framed())], canvas: PixelSize(400, 800))
        }
        #expect(throws: FramerError.self) {
            try render([InsetRenderer.Layer(framed: Synthetic.framed())], canvas: PixelSize(400, 800), pages: 2)
        }
    }

    @Test func calloutForMissingDeviceThrows() {
        let callout = InsetRenderer.Callout(spec: CalloutSpec(device: 1, region: CGRect(x: 0, y: 0, width: 10, height: 10)), image: Synthetic.framed(), region: .zero)
        #expect(throws: FramerError.self) {
            try render([InsetRenderer.Layer(framed: Synthetic.framed())], callouts: [callout], canvas: PixelSize(400, 800))
        }
    }
}

@Suite struct TextFitTests {
    let canvas = PixelSize(400, 1000)
    let style = InsetRenderer.Style(padding: 20, gap: 20)

    func text(_ title: String, subtitle: String = "", position: TextPosition = .top) -> InsetRenderer.Text {
        InsetRenderer.Text(
            title: title,
            subtitle: subtitle,
            titleStyle: TextStyle(font: FontSpec(size: 30, weight: .bold), color: .white),
            subtitleStyle: TextStyle(font: FontSpec(size: 20), color: .white),
            position: position,
            spacing: 8
        )
    }

    /// A 200x400 device in the middle of the page starting at `originX`.
    func device(top: Double, originX: Double = 0, rotation: Double = 0) -> PlacedRect {
        PlacedRect(rect: CGRect(x: originX + 100, y: top, width: 200, height: 400), rotation: rotation)
    }

    func fit(_ pages: [InsetRenderer.Text], around content: [PlacedRect], style: InsetRenderer.Style? = nil) -> [InsetRenderer.FittedText]? {
        InsetRenderer.fitText(pages, around: content, canvas: canvas, style: style ?? self.style)
    }

    @Test func growsToTheCapAndSitsGapAboveTheDevice() throws {
        let fitted = try #require(fit([text("Title", subtitle: "Sub")], around: [device(top: 500)]))[0]
        #expect(fitted.text.titleStyle.font.size == 45)
        #expect(fitted.text.subtitleStyle.font.size == 30)
        #expect(fitted.text.spacing == 12)
        #expect(fitted.rotation == 0)
        // 500 - gap.
        #expect(fitted.block.subtitleRect.maxY <= 480 && fitted.block.subtitleRect.maxY > 479)
    }

    @Test func bottomTextSitsGapBelowTheDevice() throws {
        let fitted = try #require(fit([text("Title", position: .bottom)], around: [device(top: 100)]))[0]
        #expect(fitted.block.titleRect.minY >= 520 && fitted.block.titleRect.minY < 521)
    }

    @Test func growsOnlyAsFarAsTheRoomAllows() throws {
        let fitted = try #require(fit([text("Title")], around: [device(top: 90)]))[0]
        let size = fitted.text.titleStyle.font.size
        #expect(size > 30 && size < 45)
        #expect(fitted.block.height <= 90 - 20 - 20)
    }

    @Test func shrinksWhenADeviceCrowdsIt() throws {
        let base = text("Title").block(canvas: canvas, padding: 20).height
        let fitted = try #require(fit([text("Title")], around: [device(top: 20 + base * 0.85 + 20)]))[0]
        let size = fitted.text.titleStyle.font.size
        #expect(size >= 22.5 && size < 30)
        // Below `minScale` it gives up and leaves the text alone.
        #expect(fit([text("Title")], around: [device(top: 20 + base * 0.6 + 20)]) == nil)
    }

    @Test func neverWrapsOntoMoreLines() throws {
        let title = text("A wide title, wider")
        try #require(title.lineWidths(width: 360).map(\.count) == [1, 0])
        try #require(title.scaled(by: 1.5).lineWidths(width: 360).map(\.count) == [2, 0])
        let fitted = try #require(fit([title], around: [device(top: 500)]))[0]
        let size = fitted.text.titleStyle.font.size
        #expect(size > 30 && size < 45)
        #expect(fitted.text.lineWidths(width: 360).map(\.count) == [1, 0])
    }

    @Test func fixedScaleOnlyMovesTheText() throws {
        var fixed = style
        fixed.textScale = 1...1
        let fitted = try #require(fit([text("Title")], around: [device(top: 500)], style: fixed))[0]
        #expect(fitted.text == text("Title"))
        #expect(fitted.block.titleRect.minY > 400)
    }

    @Test func tiltsWithTheDeviceAndKeepsTheGap() throws {
        let tilted = device(top: 500, rotation: -16)
        let fitted = try #require(fit([text("Title", subtitle: "Sub")], around: [tilted]))[0]
        #expect(fitted.rotation == -4)
        // The turned block, grown by `gap`, only just clears the device.
        let footprint = PlacedRect(rect: fitted.block.titleRect.union(fitted.block.subtitleRect), rotation: fitted.rotation)
        let clearance = try #require(footprint.verticalClearance(to: tilted, downward: true))
        #expect(clearance >= 20 && clearance < 30)

        var level = style
        level.maxTextRotation = 0
        #expect(try #require(fit([text("Title")], around: [tilted], style: level))[0].rotation == 0)
    }

    @Test func leavesTheTextAloneWhenThereIsNothingToFit() {
        // Nothing in the way.
        let aside = PlacedRect(rect: CGRect(x: -300, y: 200, width: 310, height: 400))
        #expect(fit([text("Title")], around: [aside]) == nil)
        // No text.
        #expect(fit([text("")], around: [device(top: 500)]) == nil)
    }

    @Test func panoramaPagesShareScaleAndTravel() throws {
        // Page 3 has nothing in the way.
        let fitted = try #require(fit(
            [text("One"), text("Two"), text("Three")],
            around: [device(top: 600), device(top: 300, originX: 400)]
        ))
        #expect(Set(fitted.map(\.text.titleStyle.font.size)) == [45])
        #expect(Set(fitted.map(\.block.titleRect.minY)).count == 1)
        // The higher device, on page 2, decides how far every page moves.
        #expect(fitted[1].block.titleRect.maxY <= 280 && fitted[1].block.titleRect.maxY > 279)
    }

    @Test func rendersTheTextJustAboveAPlacedDevice() throws {
        // Device 200x400 at (100, 500).
        let layer = InsetRenderer.Layer(framed: Synthetic.framed(), placement: DevicePlacement(x: 0.5, y: 0.7, width: 0.5))
        let out = Bitmap(try InsetRenderer.render(
            layers: [layer], canvas: canvas, background: GradientSpec(solid: RGBAColor(red: 0, green: 0, blue: 1)),
            pages: [text("Title")], style: style
        )[0])
        func hasInk(_ rows: Range<Int>) -> Bool {
            rows.contains { y in (0..<400).contains { x in out[x, y].isClose(to: .white, tolerance: 60) } }
        }
        #expect(!hasInk(0..<400))
        #expect(hasInk(420..<480))
        #expect(!hasInk(481..<500))
    }

    @Test func rendersTiltedText() throws {
        let tilted = InsetRenderer.Layer(framed: Synthetic.framed(), placement: DevicePlacement(x: 0.5, y: 0.7, width: 0.5, rotation: 8))
        let out = Bitmap(try InsetRenderer.render(
            layers: [tilted], canvas: canvas, background: GradientSpec(solid: RGBAColor(red: 0, green: 0, blue: 1)),
            pages: [text("—————")], style: style
        )[0])
        // A clockwise tilt puts the right end of the line lower than the left.
        func inkRows(_ columns: Range<Int>) -> [Int] {
            (0..<500).filter { y in columns.contains { x in out[x, y].isClose(to: .white, tolerance: 60) } }
        }
        let left = try #require(inkRows(110..<140).first)
        let right = try #require(inkRows(260..<290).first)
        #expect(right > left + 5)
    }
}
