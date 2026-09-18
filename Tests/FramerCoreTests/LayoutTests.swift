import CoreGraphics
import Testing
@testable import FramerCore

@Suite struct FrameGeometryTests {
    @Test func cutoutHeightFollowsFrameDeviceAspect() {
        let cutout = FrameGeometry.portraitCutout(offset: FrameOffset(x: 72, y: 69, width: 1206), frameScreenSize: PixelSize(1206, 2622))
        #expect(cutout == CGRect(x: 72, y: 69, width: 1206, height: 2622))
    }

    @Test func validateRejectsCutoutOutsideFrame() {
        let cutout = CGRect(x: 72, y: 69, width: 1206, height: 2622)
        #expect(throws: Never.self) { try FrameGeometry.validate(cutout: cutout, frameSize: PixelSize(1350, 2760), filename: "f") }
        #expect(throws: FramerError.self) { try FrameGeometry.validate(cutout: cutout, frameSize: PixelSize(1200, 2760), filename: "f") }
    }

    @Test func aspectFillCoversTarget() {
        // iPhone Air into the iPhone 17 cutout.
        let cutout = CGRect(x: 72, y: 69, width: 1206, height: 2622)
        let fill = FrameGeometry.aspectFill(content: PixelSize(1260, 2736), into: cutout)
        #expect(abs(fill.scale - 0.9583) < 0.001)
        #expect(fill.rect.contains(cutout))
        #expect(fill.rect.width <= cutout.width + 2)
        // Exact device: identity.
        let exact = FrameGeometry.aspectFill(content: PixelSize(1206, 2622), into: cutout)
        #expect(exact.scale == 1)
        #expect(exact.rect == cutout)
    }

    @Test func aspectFitCentres() {
        let fit = FrameGeometry.aspectFit(content: PixelSize(1350, 2760), into: CGRect(x: 0, y: 0, width: 1206, height: 2622))
        #expect(fit.rect.width == 1206)
        #expect(fit.rect.minX == 0)
        #expect(abs(fit.rect.midY - 1311) <= 1)
    }

    @Test func portraitIsIdentity() {
        let g = FrameGeometry.oriented(frameSize: Synthetic.frameSize, cutout: Synthetic.cutout, orientation: .portrait, side: .left)
        #expect(g.canvasSize == Synthetic.frameSize)
        #expect(g.cutout == Synthetic.cutout)
        #expect(g.frameTransform == .identity)
    }

    @Test func landscapeLeftRotatesCounterClockwise() {
        let g = FrameGeometry.oriented(frameSize: Synthetic.frameSize, cutout: Synthetic.cutout, orientation: .landscape, side: .left)
        #expect(g.canvasSize == PixelSize(600, 300))
        // (30,40,240,520) -> x = 40, y = 300 - 30 - 240 = 30, 520x240
        #expect(g.cutout == CGRect(x: 40, y: 30, width: 520, height: 240))
        // Portrait top-left in CG coords is (0, 600); it must land at landscape bottom-left (0, 0).
        let topLeft = CGPoint(x: 0, y: 600).applying(g.frameTransform)
        #expect(abs(topLeft.x) < 0.001 && abs(topLeft.y) < 0.001)
        // Portrait top-right (300, 600) -> landscape top-left (0, 300).
        let topRight = CGPoint(x: 300, y: 600).applying(g.frameTransform)
        #expect(abs(topRight.x) < 0.001 && abs(topRight.y - 300) < 0.001)
    }

    @Test func landscapeRightRotatesClockwise() {
        let g = FrameGeometry.oriented(frameSize: Synthetic.frameSize, cutout: Synthetic.cutout, orientation: .landscape, side: .right)
        #expect(g.canvasSize == PixelSize(600, 300))
        // x = 600 - 40 - 520 = 40, y = 30
        #expect(g.cutout == CGRect(x: 40, y: 30, width: 520, height: 240))
        // Portrait top-left (0, 600) -> landscape top-right (600, 300).
        let topLeft = CGPoint(x: 0, y: 600).applying(g.frameTransform)
        #expect(abs(topLeft.x - 600) < 0.001 && abs(topLeft.y - 300) < 0.001)
    }

    @Test func flippedRect() {
        #expect(CGRect(x: 10, y: 20, width: 30, height: 40).flipped(in: 100) == CGRect(x: 10, y: 40, width: 30, height: 40))
    }
}

@Suite struct OutputSizingTests {
    let native = PixelSize(1206, 2622)
    let framed = PixelSize(1350, 2760)

    @Test func defaultsToNative() {
        let r = OutputSizing.resolve(requestedWidth: nil, requestedHeight: nil, native: native, framedSize: framed)
        #expect(r == OutputSizing.Result(size: native, clamped: false))
    }

    @Test func widthOnlyFollowsFramedAspect() {
        let r = OutputSizing.resolve(requestedWidth: 800, requestedHeight: nil, native: native, framedSize: framed)
        #expect(r.size == PixelSize(800, 1636))
        #expect(!r.clamped)
    }

    @Test func heightOnlyFollowsFramedAspect() {
        let r = OutputSizing.resolve(requestedWidth: nil, requestedHeight: 1380, native: native, framedSize: framed)
        #expect(r.size == PixelSize(675, 1380))
    }

    @Test func clampsToNative() {
        let r = OutputSizing.resolve(requestedWidth: 5000, requestedHeight: 100, native: native, framedSize: framed)
        #expect(r.size == PixelSize(1206, 100))
        #expect(r.clamped)
    }

    @Test func landscapeNative() {
        let r = OutputSizing.resolve(requestedWidth: nil, requestedHeight: nil, native: native.swapped, framedSize: framed.swapped)
        #expect(r.size == PixelSize(2622, 1206))
    }
}

@Suite struct InsetLayoutTests {
    func input(position: TextPosition, titleHeight: Double = 300, subtitleHeight: Double = 0, deviceScale: Double = 1) -> InsetLayout.Input {
        InsetLayout.Input(
            canvas: PixelSize(1000, 2000), padding: 50, gap: 50, spacing: 20,
            titleHeight: titleHeight, subtitleHeight: subtitleHeight,
            framedSize: PixelSize(500, 1000), position: position, deviceScale: deviceScale
        )
    }

    @Test func textOnTopPinsDeviceToBottom() throws {
        let layout = try InsetLayout.compute(input(position: .top))
        #expect(layout.titleRect == CGRect(x: 50, y: 50, width: 900, height: 300))
        // area = (50, 400, 900, 1550); device fits height: 775x1550, x centred = 50 + 450 - 387.5 -> 112 or 113
        #expect(layout.deviceRect.height == 1550)
        #expect(layout.deviceRect.width == 775)
        #expect(abs(layout.deviceRect.midX - 500) <= 1)
        #expect(layout.deviceRect.maxY == 1950)
    }

    @Test func textOnBottomPinsDeviceToTop() throws {
        let layout = try InsetLayout.compute(input(position: .bottom))
        #expect(layout.titleRect == CGRect(x: 50, y: 1650, width: 900, height: 300))
        #expect(layout.deviceRect.minY == 50)
        #expect(layout.deviceRect.height == 1550)
    }

    @Test func subtitleStacksBelowTitleWithSpacing() throws {
        let layout = try InsetLayout.compute(input(position: .top, subtitleHeight: 100))
        #expect(layout.subtitleRect == CGRect(x: 50, y: 370, width: 900, height: 100))
        // text block 420, gap 50 -> area starts at 520, height 1430
        #expect(layout.deviceRect.height == 1430)
        #expect(layout.deviceRect.maxY == 1950)
    }

    @Test func noTextMeansNoGap() throws {
        let layout = try InsetLayout.compute(input(position: .top, titleHeight: 0))
        // area = (50, 50, 900, 1900); width-limited: 900x1800, pinned to the bottom of the area.
        #expect(layout.deviceRect.width == 900)
        #expect(layout.deviceRect.height == 1800)
        #expect(layout.deviceRect.maxY == 1950)
    }

    @Test func deviceScaleShrinksButKeepsPin() throws {
        let layout = try InsetLayout.compute(input(position: .top, deviceScale: 0.5))
        #expect(layout.deviceRect.height == 775)
        #expect(layout.deviceRect.maxY == 1950)
    }

    @Test func textTooTallThrows() {
        #expect(throws: FramerError.self) { try InsetLayout.compute(input(position: .top, titleHeight: 1900)) }
    }
}

@Suite struct GradientTests {
    @Test func endpointsFollowCSSAngles() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 200)
        let down = GradientSpec(colors: [.black, .white], angleDegrees: 180).endpoints(in: rect)
        #expect(abs(down.start.y - 200) < 0.001 && abs(down.end.y) < 0.001) // CG y-up: start at top
        let up = GradientSpec(colors: [.black, .white], angleDegrees: 0).endpoints(in: rect)
        #expect(abs(up.start.y) < 0.001 && abs(up.end.y - 200) < 0.001)
        let right = GradientSpec(colors: [.black, .white], angleDegrees: 90).endpoints(in: rect)
        #expect(abs(right.start.x) < 0.001 && abs(right.end.x - 100) < 0.001)
        let diagonal = GradientSpec(colors: [.black, .white], angleDegrees: 45).endpoints(in: rect)
        #expect(diagonal.end.x > diagonal.start.x && diagonal.end.y > diagonal.start.y)
    }

    @Test func rendersTopToBottom() {
        let ctx = CGContext.makeCanvas(size: PixelSize(50, 100))
        GradientSpec(colors: [.black, .white], angleDegrees: 180).fill(ctx, rectTL: CGRect(x: 0, y: 0, width: 50, height: 100))
        let bitmap = Bitmap(ctx.makeImage()!)
        bitmap.expect(25, 0, .black, tolerance: 6)
        bitmap.expect(25, 99, .white, tolerance: 6)
        #expect(bitmap[25, 50].r > 100 && bitmap[25, 50].r < 160)
    }

    @Test func solidFill() {
        let ctx = CGContext.makeCanvas(size: PixelSize(10, 10))
        GradientSpec(solid: RGBAColor(red: 1, green: 0, blue: 0)).fill(ctx, rectTL: CGRect(x: 0, y: 0, width: 10, height: 10))
        let bitmap = Bitmap(ctx.makeImage()!)
        bitmap.expect(0, 0, .red)
        bitmap.expect(9, 9, .red)
    }

    @Test func validation() {
        #expect(throws: FramerError.self) { try GradientSpec(colors: []).validate() }
        #expect(throws: FramerError.self) { try GradientSpec(colors: [.black, .white], locations: [0]).validate() }
        #expect(throws: FramerError.self) { try GradientSpec(colors: [.black, .white], locations: [0, 2]).validate() }
        #expect(throws: Never.self) { try GradientSpec(colors: [.black, .white], locations: [0, 1]).validate() }
    }
}
