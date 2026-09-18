public enum OutputSizing {
    public struct Result: Sendable, Equatable {
        public var size: PixelSize
        /// True when the requested size exceeded the native screenshot size and was clamped.
        public var clamped: Bool
    }

    /// Resolves the output canvas size.
    /// - Both dims given: used as-is. One dim: the other follows the framed image's aspect. None: native screenshot size.
    /// - Never exceeds the native screenshot size in either dimension.
    public static func resolve(
        requestedWidth: Int?,
        requestedHeight: Int?,
        native: PixelSize,
        framedSize: PixelSize
    ) -> Result {
        let aspect = Double(framedSize.height) / Double(framedSize.width)
        var size: PixelSize
        switch (requestedWidth, requestedHeight) {
        case let (w?, h?):
            size = PixelSize(w, h)
        case let (w?, nil):
            size = PixelSize(w, Int((Double(w) * aspect).rounded()))
        case let (nil, h?):
            size = PixelSize(Int((Double(h) / aspect).rounded()), h)
        case (nil, nil):
            size = native
        }

        var clamped = false
        if size.width > native.width {
            size.width = native.width
            clamped = true
        }
        if size.height > native.height {
            size.height = native.height
            clamped = true
        }
        size.width = max(size.width, 1)
        size.height = max(size.height, 1)
        return Result(size: size, clamped: clamped)
    }
}
