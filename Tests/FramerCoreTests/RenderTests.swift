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
