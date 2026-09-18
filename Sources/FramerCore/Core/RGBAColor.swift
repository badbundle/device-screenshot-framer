import CoreGraphics
import Foundation

/// An sRGB colour with components in 0...1. Encoded in JSON as a hex string
/// (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`; leading `#` optional).
public struct RGBAColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex input: String) throws {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else {
            throw FramerError.config("invalid color '\(input)': expected hex like #RRGGBB")
        }

        let digits: [Character]
        switch hex.count {
        case 3, 4:
            // Nibble expansion: F -> FF
            digits = hex.flatMap { [$0, $0] }
        case 6, 8:
            digits = Array(hex)
        default:
            throw FramerError.config("invalid color '\(input)': expected 3, 4, 6 or 8 hex digits")
        }

        func component(_ i: Int) -> Double {
            let pair = String(digits[i * 2 ..< i * 2 + 2])
            return Double(UInt8(pair, radix: 16)!) / 255
        }

        red = component(0)
        green = component(1)
        blue = component(2)
        alpha = digits.count == 8 ? component(3) : 1
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace.sRGBSpace, components: [red, green, blue, alpha])!
    }

    /// `#RRGGBB` or `#RRGGBBAA` when alpha < 1.
    public var hexString: String {
        func byte(_ v: Double) -> String {
            String(format: "%02X", Int((v * 255).rounded()))
        }
        var s = "#" + byte(red) + byte(green) + byte(blue)
        if alpha < 1 { s += byte(alpha) }
        return s
    }
}

extension RGBAColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        do {
            try self.init(hex: string)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(error)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

extension RGBAColor: CustomStringConvertible {
    public var description: String { hexString }
}

extension CGColorSpace {
    /// Computed rather than stored: CGColorSpace is not Sendable, so a static let would be rejected under strict concurrency.
    static var sRGBSpace: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
}
