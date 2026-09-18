import CoreGraphics
import CoreText
import Foundation

public enum FontWeight: String, Sendable, Codable, CaseIterable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    /// CoreText weight trait (same scale as UIFont.Weight).
    var traitValue: Double {
        switch self {
        case .ultraLight: return -0.8
        case .thin: return -0.6
        case .light: return -0.4
        case .regular: return 0
        case .medium: return 0.23
        case .semibold: return 0.3
        case .bold: return 0.4
        case .heavy: return 0.56
        case .black: return 0.62
        }
    }
}

public struct FontSpec: Sendable, Hashable {
    /// `nil` or "system" = the system UI font (SF). Otherwise a PostScript, full or family name.
    public var name: String?
    public var size: Double
    public var weight: FontWeight?

    public init(name: String? = nil, size: Double, weight: FontWeight? = nil) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    var isSystem: Bool {
        guard let name else { return true }
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return n.isEmpty || n == "system" || n == "sf" || n == "sf pro"
    }
}

public struct TextStyle: Sendable, Hashable {
    public var font: FontSpec
    public var color: RGBAColor

    public init(font: FontSpec, color: RGBAColor) {
        self.font = font
        self.color = color
    }
}

public enum TextRenderer {
    /// Resolves a CTFont. Unknown font names fall back to the system font with a warning
    /// (CoreText would otherwise silently substitute Helvetica).
    static func makeFont(_ spec: FontSpec) -> CTFont {
        let size = CGFloat(spec.size)
        var base: CTFont
        if spec.isSystem {
            base = systemFont(size: size)
        } else {
            let requested = spec.name!.trimmingCharacters(in: .whitespaces)
            let candidate = CTFontCreateWithName(requested as CFString, size, nil)
            if fontMatches(candidate, name: requested) {
                base = candidate
            } else {
                Log.warn("font '\(requested)' not found; using the system font")
                base = systemFont(size: size)
            }
        }

        guard let weight = spec.weight else { return base }
        let traits: [CFString: Any] = [kCTFontWeightTrait: weight.traitValue]
        let attributes: [CFString: Any] = [kCTFontTraitsAttribute: traits]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
    }

    private static func systemFont(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func fontMatches(_ font: CTFont, name: String) -> Bool {
        let needle = name.lowercased()
        let names = [
            CTFontCopyPostScriptName(font) as String,
            CTFontCopyFullName(font) as String,
            CTFontCopyFamilyName(font) as String,
            CTFontCopyDisplayName(font) as String,
        ]
        return names.contains { $0.lowercased() == needle }
    }

    static func attributedString(_ text: String, style: TextStyle) -> CFAttributedString {
        let font = makeFont(style.font)
        let paragraph = centeredParagraphStyle()
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: style.color.cgColor,
            kCTParagraphStyleAttributeName: paragraph,
        ]
        return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    }

    private static func centeredParagraphStyle() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        var lineBreak = CTLineBreakMode.byWordWrapping
        return withUnsafePointer(to: &alignment) { alignmentPtr in
            withUnsafePointer(to: &lineBreak) { lineBreakPtr in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: UnsafeRawPointer(alignmentPtr)
                    ),
                    CTParagraphStyleSetting(
                        spec: .lineBreakMode,
                        valueSize: MemoryLayout<CTLineBreakMode>.size,
                        value: UnsafeRawPointer(lineBreakPtr)
                    ),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    /// Height needed to lay out `text` wrapped to `width`. 0 for empty text.
    public static func measureHeight(_ text: String, style: TextStyle, width: Double) -> Double {
        guard !text.isEmpty, width > 0 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(text, style: style))
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraint, nil)
        // +1 guards against CoreText dropping the last line on exact-fit rounding.
        return size.height.rounded(.up) + 1
    }

    /// Draws `text` centred inside `rectTL` (top-left coordinates), lines flowing from the top.
    static func draw(_ text: String, style: TextStyle, in rectTL: CGRect, ctx: CGContext) {
        guard !text.isEmpty, rectTL.width > 0, rectTL.height > 0 else { return }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString(text, style: style))
        let path = CGPath(rect: rectTL.flipped(in: Double(ctx.height)), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
}
