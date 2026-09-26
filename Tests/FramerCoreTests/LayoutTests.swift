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

@Suite struct BleedLayoutTests {
    func input(position: TextPosition, deviceScale: Double = 1) -> InsetLayout.Input {
        InsetLayout.Input(
            canvas: PixelSize(1000, 2000), padding: 50, gap: 50, spacing: 20,
            titleHeight: 300, subtitleHeight: 0,
            framedSize: PixelSize(500, 1000), position: position, deviceScale: deviceScale, bleed: true
        )
    }

    @Test func textOnTopPinsDeviceUnderTextAndRunsOffBottom() throws {
        let layout = try InsetLayout.compute(input(position: .top))
        // Sized by the text column width (900), not the leftover height.
        #expect(layout.deviceRect == CGRect(x: 50, y: 400, width: 900, height: 1800))
        #expect(layout.deviceRect.maxY > 2000)
    }

    @Test func textOnBottomPinsDeviceAboveTextAndRunsOffTop() throws {
        let layout = try InsetLayout.compute(input(position: .bottom))
        #expect(layout.deviceRect.maxY == 1600)
        #expect(layout.deviceRect.minY < 0)
    }

    @Test func deviceScaleMultipliesWidth() throws {
        let layout = try InsetLayout.compute(input(position: .top, deviceScale: 0.5))
        #expect(layout.deviceRect.width == 450)
        #expect(layout.deviceRect.minY == 400)
        #expect(abs(layout.deviceRect.midX - 500) <= 1)
    }
}

@Suite struct TextBlockTests {
    @Test func offsetsByPageOrigin() {
        let block = InsetLayout.textBlock(
            canvas: PixelSize(1000, 2000), padding: 50, spacing: 20,
            titleHeight: 100, subtitleHeight: 40, position: .bottom, originX: 2000
        )
        #expect(block.height == 160)
        #expect(block.titleRect == CGRect(x: 2050, y: 1790, width: 900, height: 100))
        #expect(block.subtitleRect == CGRect(x: 2050, y: 1910, width: 900, height: 40))
    }

    @Test func shiftMovesTowardsTheMiddle() {
        func titleY(_ position: TextPosition) -> Double {
            InsetLayout.textBlock(
                canvas: PixelSize(1000, 2000), padding: 50, spacing: 0,
                titleHeight: 100, subtitleHeight: 0, position: position, shift: 30
            ).titleRect.minY
        }
        #expect(titleY(.top) == 80)
        #expect(titleY(.bottom) == 2000 - 50 - 100 - 30)
    }
}

@Suite struct TextFitLayoutTests {
    let canvas = PixelSize(1000, 2000)

    @Test func rotationFollowsTheNearestContentUnderTheCentre() {
        func rotation(_ content: [PlacedRect], position: TextPosition = .top) -> Double {
            InsetLayout.textRotation(canvas: canvas, position: position, content: content, maxRotation: 4)
        }
        let high = PlacedRect(rect: CGRect(x: 300, y: 800, width: 400, height: 800), rotation: 6)
        let low = PlacedRect(rect: CGRect(x: 300, y: 1000, width: 400, height: 800), rotation: -2)
        let aside = PlacedRect(rect: CGRect(x: 0, y: 300, width: 300, height: 600), rotation: 20)  // misses x = 500
        #expect(rotation([low, high, aside]) == 3)                  // half of 6
        #expect(rotation([low, high], position: .bottom) == -1)     // lowest bottom is `low`
        #expect(rotation([aside]) == 0)
        #expect(rotation([PlacedRect(rect: high.rect, rotation: -16)]) == -4)
        #expect(rotation([PlacedRect(rect: high.rect, rotation: 92)]) == 1)   // 2° off sideways
    }

    @Test func footprintStartsPaddingFromItsEdge() {
        let level = InsetLayout.textFootprint(size: CGSize(width: 600, height: 200), rotation: 0, canvas: canvas, padding: 50, position: .top, originX: 1000)
        #expect(level.rect == CGRect(x: 1200, y: 50, width: 600, height: 200))
        let tilted = InsetLayout.textFootprint(size: CGSize(width: 600, height: 200), rotation: 5, canvas: canvas, padding: 50, position: .bottom)
        #expect(abs(tilted.bounds.maxY - 1950) < 0.001)
        #expect(tilted.center.x == 500)
    }

    @Test func travelStopsGapShortOfTheContent() throws {
        let text = PlacedRect(rect: CGRect(x: 300, y: 50, width: 400, height: 100))
        let device = PlacedRect(rect: CGRect(x: 200, y: 600, width: 600, height: 1200))
        #expect(InsetLayout.textTravel(text, gap: 40, position: .top, content: [device]) == 410)   // 600 - 40 - 150
        #expect(InsetLayout.textTravel(text, gap: 40, position: .top, content: []) == nil)
        // A device reaching past the text's edge is on the wrong side: it can't move at all.
        let behind = PlacedRect(rect: CGRect(x: 200, y: 0, width: 600, height: 120))
        let travel = try #require(InsetLayout.textTravel(text, gap: 40, position: .top, content: [behind]))
        #expect(travel < 0)
    }
}

@Suite struct PlacementTests {
    @Test func resolvesInPageUnits() {
        let placed = DevicePlacement(x: 0.5, y: 0.25, width: 0.5, rotation: 12)
            .resolve(page: PixelSize(1000, 2000), contentSize: PixelSize(300, 600))
        #expect(placed.rect == CGRect(x: 250, y: 0, width: 500, height: 1000))
        #expect(placed.rotation == 12)
    }

    @Test func xBeyondOneReachesLaterPages() {
        let placed = DevicePlacement(x: 1.5, y: 0.5, width: 0.2).resolve(page: PixelSize(1000, 1000), contentSize: PixelSize(100, 100))
        #expect(placed.center == CGPoint(x: 1500, y: 500))
    }

    @Test func unrotatedTransformMapsContentOntoRect() {
        let t = PlacedRect(rect: CGRect(x: 100, y: 200, width: 60, height: 120)).transform(from: CGSize(width: 30, height: 60))
        #expect(CGPoint(x: 0, y: 0).applying(t) == CGPoint(x: 100, y: 200))
        #expect(CGPoint(x: 30, y: 60).applying(t) == CGPoint(x: 160, y: 320))
    }

    @Test func verticalExtentFollowsTheRotatedEdges() throws {
        // A 100x100 square turned 45° about (50, 50): corners at (50, -20.7), (120.7, 50), (50, 120.7), (-20.7, 50).
        let diamond = PlacedRect(rect: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 45)
        let whole = try #require(diamond.verticalExtent(within: 0...100))
        #expect(abs(whole.lowerBound - (50 - 50 * 2.0.squareRoot())) < 0.001)
        // Only the right-hand slope crosses x = 90...100.
        let slice = try #require(diamond.verticalExtent(within: 90...100))
        #expect(abs(slice.lowerBound - 19.289) < 0.01)
        #expect(abs(slice.upperBound - 80.711) < 0.01)
        #expect(diamond.verticalExtent(within: 200...300) == nil)
        #expect(PlacedRect(rect: CGRect(x: 10, y: 20, width: 30, height: 40)).verticalExtent(within: 0...15) == 20...60)
    }

    @Test func clearanceBetweenRotatedRects() throws {
        let box = PlacedRect(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        let below = PlacedRect(rect: CGRect(x: 50, y: 300, width: 100, height: 100))
        #expect(box.verticalClearance(to: below, downward: true) == 200)
        #expect(below.verticalClearance(to: box, downward: false) == 200)
        #expect(box.verticalClearance(to: PlacedRect(rect: CGRect(x: 200, y: 300, width: 10, height: 10)), downward: true) == nil)
        // Turned 45°, `below`'s top corner is 50·√2 above its centre (100, 350).
        let diamond = PlacedRect(rect: below.rect, rotation: 45)
        let clearance = try #require(box.verticalClearance(to: diamond, downward: true))
        #expect(abs(clearance - (350 - 50 * 2.0.squareRoot() - 100)) < 0.001)
    }

    @Test func positiveRotationIsClockwise() {
        let t = PlacedRect(rect: CGRect(x: 0, y: 0, width: 100, height: 200), rotation: 90).transform(from: CGSize(width: 100, height: 200))
        // Top-centre of the content ends up on the right of the centre (50, 100).
        let top = CGPoint(x: 50, y: 0).applying(t)
        #expect(abs(top.x - 150) < 0.001 && abs(top.y - 100) < 0.001)
    }
}

@Suite struct CalloutLayoutTests {
    let device = PlacedRect(rect: CGRect(x: 100, y: 100, width: 150, height: 300))
    let framedSize = PixelSize(300, 600)
    let page = PixelSize(1000, 1000)

    @Test func framedRegionFollowsTheScreenshotFill() {
        let region = CalloutLayout.framedRegion(
            CGRect(x: 10, y: 20, width: 100, height: 50),
            screenshotFill: (rect: CGRect(x: 30, y: 40, width: 240, height: 520), scale: 0.5)
        )
        #expect(region == CGRect(x: 35, y: 50, width: 50, height: 25))
    }

    @Test func defaultCardSitsOverTheSource() {
        let spec = CalloutSpec(region: .zero, scale: 2)
        let result = CalloutLayout.compute(spec, region: CGRect(x: 100, y: 200, width: 40, height: 20), device: device, framedSize: framedSize, page: page)
        // Device is drawn at half size: region -> (150, 200) 20x10.
        #expect(result.source.rect == CGRect(x: 150, y: 200, width: 20, height: 10))
        #expect(result.card.rect == CGRect(x: 140, y: 195, width: 40, height: 20))
        #expect(result.card.rotation == 0)
    }

    @Test func explicitPositionAndRotation() {
        let spec = CalloutSpec(region: .zero, x: 0.5, y: 0.25, scale: 1, rotation: -5)
        let result = CalloutLayout.compute(spec, region: CGRect(x: 100, y: 200, width: 40, height: 20), device: device, framedSize: framedSize, page: page)
        #expect(result.card.center == CGPoint(x: 500, y: 250))
        #expect(result.card.rotation == -5)
    }

    @Test func inheritsDeviceRotation() {
        var rotated = device
        rotated.rotation = 90
        let spec = CalloutSpec(region: .zero, scale: 1)
        // Region at the top-centre of the device swings to the right of the device centre (175, 250).
        let result = CalloutLayout.compute(spec, region: CGRect(x: 140, y: 0, width: 20, height: 20), device: rotated, framedSize: framedSize, page: page)
        #expect(abs(result.source.center.x - (175 + 145)) < 0.001)
        #expect(abs(result.source.center.y - 250) < 0.001)
        #expect(result.source.rotation == 90)
        #expect(result.card.rotation == 90)
    }
}
