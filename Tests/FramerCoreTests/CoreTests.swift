import Foundation
import Testing
@testable import FramerCore

@Suite struct RGBAColorTests {
    @Test func shortHexExpands() throws {
        let short = try RGBAColor(hex: "#F0A")
        let long = try RGBAColor(hex: "FF00AA")
        #expect(short == long)
        #expect(short.hexString == "#FF00AA")
    }

    @Test func alphaParses() throws {
        let c = try RGBAColor(hex: "#FF00AA80")
        #expect(abs(c.alpha - 128.0 / 255.0) < 0.001)
        #expect(c.hexString == "#FF00AA80")
        let short = try RGBAColor(hex: "#F0A8")
        #expect(short.hexString == "#FF00AA88")
    }

    @Test(arguments: ["", "#", "#12345", "#GGGGGG", "red", "#1234567"])
    func invalidHexThrows(_ hex: String) {
        #expect(throws: FramerError.self) { try RGBAColor(hex: hex) }
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode([RGBAColor.white, try RGBAColor(hex: "#12345678")])
        let decoded = try JSONDecoder().decode([RGBAColor].self, from: data)
        #expect(decoded[0] == .white)
        #expect(decoded[1].hexString == "#12345678")
    }

    @Test func badJSONColorGivesReadableError() {
        let json = Data(##"{"colors": ["#zz"]}"##.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(BackgroundConfig.self, from: json) }
    }
}

@Suite struct PixelSizeTests {
    @Test func basics() {
        let s = PixelSize(1206, 2622)
        #expect(s.swapped == PixelSize(2622, 1206))
        #expect(!s.isLandscape && s.swapped.isLandscape)
        #expect(s.description == "1206x2622")
    }
}

@Suite struct FrameOffsetTests {
    @Test func parsesFrameitFormat() throws {
        let o = try FrameOffset(offsetString: "+72+69", width: 1206)
        #expect(o == FrameOffset(x: 72, y: 69, width: 1206))
    }

    @Test(arguments: ["72+69", "+72", "+a+b", ""])
    func rejectsMalformed(_ s: String) {
        #expect(throws: FramerError.self) { try FrameOffset(offsetString: s, width: 1) }
    }
}
