import Foundation

/// Maps a frame filename to its `offsets.json` key.
///
/// frameit's generator builds keys by stripping "Apple", ".png" and any *known* colour words from the
/// filename, so keys sometimes keep colour fragments ("iPhone 12 Pro Pacific" from "Pacific Blue") and a
/// few devices have colour-specific offsets ("iPhone 13 Mini Midnight"). Filenames say "(11-inch)" but
/// keys say "(11 inch)". Rather than replicate the colour list, we try candidates from most to least
/// specific: the full name, then with 1..n trailing colour words removed.
public enum FrameResolver {
    /// Candidate offsets keys, most specific first.
    public static func offsetsKeyCandidates(filename: String, color: String) -> [String] {
        var body = filename
        if body.hasPrefix("Apple ") { body.removeFirst("Apple ".count) }
        if body.hasSuffix(".png") { body.removeLast(".png".count) }
        body = body.replacingOccurrences(of: "-inch)", with: " inch)")

        let words = color.split(separator: " ").map(String.init)
        guard !words.isEmpty, let colorRange = body.range(of: color) else {
            return [body.trimmingCharacters(in: .whitespaces)]
        }

        // Drop trailing colour words but keep the surrounding spaces, exactly as the generator does:
        // "… 2020 Sky Blue Portrait" minus "Blue" is "… 2020 Sky  Portrait" (double space).
        var candidates: [String] = []
        for dropCount in 0...words.count {
            let dropped = words.suffix(dropCount).joined(separator: " ")
            var candidate = body
            if !dropped.isEmpty {
                let start = body.index(colorRange.upperBound, offsetBy: -dropped.count)
                candidate.replaceSubrange(start..<colorRange.upperBound, with: "")
            }
            candidates.append(candidate.trimmingCharacters(in: .whitespaces))
        }
        return candidates
    }

    /// First candidate present in `offsets`, or nil.
    public static func offset(filename: String, color: String, offsets: [String: FrameOffset]) -> FrameOffset? {
        for key in offsetsKeyCandidates(filename: filename, color: color) {
            if let found = offsets[key] { return found }
        }
        return nil
    }
}
