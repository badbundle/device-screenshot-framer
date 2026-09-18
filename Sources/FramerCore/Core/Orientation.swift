public enum Orientation: String, Sendable, Codable {
    case portrait
    case landscape
}

/// Which side of a landscape frame the top of the device (notch / Dynamic Island) ends up on.
public enum LandscapeSide: String, Sendable, Codable, CaseIterable {
    /// Device rotated 90° counter-clockwise: top edge becomes the left edge.
    case left
    /// Device rotated 90° clockwise: top edge becomes the right edge.
    case right
}
