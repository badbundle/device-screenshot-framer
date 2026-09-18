import Foundation

/// Stateless stderr logging. Verbose output is opt-in per call site so there is no global mutable state.
public enum Log {
    public static func warn(_ message: String) {
        write("warning: \(message)")
    }

    public static func info(_ message: String) {
        write(message)
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
