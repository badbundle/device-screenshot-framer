import Foundation

public enum FramerError: Error, Sendable {
    case unsupportedImage(URL)
    case unknownDevice(PixelSize, path: String)
    case unknownDeviceName(String)
    case noFrame(device: String, filename: String)
    case download(URL, status: Int?)
    case offline(String)
    case offsetsMissing(filename: String)
    case inconsistentFrame(filename: String, detail: String)
    case textTooTall
    case config(String)
    case write(URL)
}

extension FramerError: CustomStringConvertible, LocalizedError {
    public var description: String {
        switch self {
        case .unsupportedImage(let url):
            return "could not read image at '\(url.path)'"
        case .unknownDevice(let size, let path):
            return "unsupported screenshot size \(size) for '\(path)'. Pass --device to force a frame; see `framer list-devices`."
        case .unknownDeviceName(let name):
            return "unknown device '\(name)'. See `framer list-devices`."
        case .noFrame(let device, let filename):
            return "no frame available for \(device) (looked for '\(filename)'). Run `framer download-frames` or check the frame colour."
        case .download(let url, let status):
            if let status {
                return "download failed (HTTP \(status)): \(url.absoluteString)"
            }
            return "download failed: \(url.absoluteString)"
        case .offline(let what):
            return "offline and '\(what)' is not cached"
        case .offsetsMissing(let filename):
            return "no offset information for frame '\(filename)' in offsets.json"
        case .inconsistentFrame(let filename, let detail):
            return "frame '\(filename)' is inconsistent with its offsets: \(detail)"
        case .textTooTall:
            return "title/subtitle block leaves no room for the device; reduce font sizes or padding"
        case .config(let message):
            return "config error: \(message)"
        case .write(let url):
            return "could not write '\(url.path)'"
        }
    }

    public var errorDescription: String? { description }
}
