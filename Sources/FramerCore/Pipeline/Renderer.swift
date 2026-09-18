import CoreGraphics
import Foundation

/// Orchestrates one job: detect device → fetch frame → composite → mode render → write.
/// `prepare` is async (network); `render` is synchronous and keeps every CG/CT object on one task.
public struct Renderer: Sendable {
    public var store: FrameStore
    public var verbose: Bool

    public init(store: FrameStore, verbose: Bool = false) {
        self.store = store
        self.verbose = verbose
    }

    public struct Prepared: Sendable {
        public var job: RenderJob
        public var device: Device
        public var orientation: Orientation
        public var screenshotSize: PixelSize
        public var frame: FrameStore.ResolvedFrame
    }

    public struct Outcome: Sendable {
        public var job: RenderJob
        public var output: URL
        public var device: Device
        public var frameColor: String
        public var size: PixelSize
    }

    /// Resolves the device and frame for a job, downloading the frame if needed.
    public func prepare(_ job: RenderJob, manifest: FrameManifest) async throws -> Prepared {
        let size = try ImageLoader.size(of: job.input)

        let device: Device
        let orientation: Orientation
        if let name = job.deviceName {
            guard let forced = DeviceCatalog.named(name) else { throw FramerError.unknownDeviceName(name) }
            device = forced
            orientation = size.isLandscape ? .landscape : .portrait
            if size != device.screenSize && size != device.screenSize.swapped {
                Log.warn("\(job.input.lastPathComponent) is \(size), not \(device.name)'s \(device.screenSize); screenshot will be scaled to fill the frame")
            }
        } else {
            guard let detected = DeviceCatalog.detect(size) else {
                throw FramerError.unknownDevice(size, path: job.input.path)
            }
            (device, orientation) = detected
        }

        if device.usesBorrowedFrame, verbose {
            Log.info("\(device.name) has no dedicated frame; using \(device.framePrefix) frame")
        }

        let frame = try await store.frame(for: device, color: job.frameColor, manifest: manifest)
        return Prepared(job: job, device: device, orientation: orientation, screenshotSize: size, frame: frame)
    }

    /// Renders and writes the output image.
    public func render(_ prepared: Prepared) throws -> Outcome {
        let job = prepared.job
        let screenshot = try ImageLoader.load(job.input)
        let frameImage = try ImageLoader.load(prepared.frame.fileURL)

        let cutout = FrameGeometry.portraitCutout(offset: prepared.frame.offset, frameScreenSize: prepared.device.effectiveFrameScreenSize)
        try FrameGeometry.validate(cutout: cutout, frameSize: frameImage.pixelSize, filename: prepared.frame.filename)
        let geometry = FrameGeometry.oriented(
            frameSize: frameImage.pixelSize,
            cutout: cutout,
            orientation: prepared.orientation,
            side: job.landscapeSide
        )

        let framed = FrameCompositor.composite(FrameCompositor.Input(
            screenshot: screenshot,
            frame: frameImage,
            geometry: geometry,
            cornerRadius: prepared.device.cornerRadius
        ))

        let sizing = OutputSizing.resolve(
            requestedWidth: job.requestedWidth,
            requestedHeight: job.requestedHeight,
            native: screenshot.pixelSize,
            framedSize: framed.pixelSize
        )
        if sizing.clamped {
            Log.warn("requested output exceeds native \(screenshot.pixelSize) for \(job.input.lastPathComponent); clamped to \(sizing.size)")
        }
        let canvas = sizing.size

        let result: CGImage
        switch job.mode {
        case .simple:
            var background = job.background
            if background == nil, job.format == .jpeg {
                background = GradientSpec(solid: .white)
            }
            try background?.validate()
            result = SimpleRenderer.render(framed: framed, canvas: canvas, background: background)

        case .inset:
            guard let inset = job.inset else {
                throw FramerError.config("inset mode requires text settings")
            }
            let background = job.background ?? GradientSpec(solid: .white)
            try background.validate()
            if inset.title.isEmpty && inset.subtitle.isEmpty {
                Log.warn("\(job.input.lastPathComponent): inset mode with no title or subtitle")
            }
            let padding = inset.padding ?? (Double(canvas.width) * 0.05).rounded()
            result = try InsetRenderer.render(
                framed: framed,
                canvas: canvas,
                background: background,
                text: InsetRenderer.Text(
                    title: inset.title,
                    subtitle: inset.subtitle,
                    titleStyle: inset.titleStyle,
                    subtitleStyle: inset.subtitleStyle,
                    position: inset.position,
                    spacing: inset.spacing
                ),
                style: InsetRenderer.Style(padding: padding, gap: inset.gap ?? padding, deviceScale: inset.deviceScale)
            )
        }

        let output = job.outputURL
        try ImageWriter.write(result, to: output, format: job.format, jpegQuality: job.jpegQuality)
        return Outcome(job: job, output: output, device: prepared.device, frameColor: prepared.frame.color, size: canvas)
    }

    /// Runs every job, collecting failures instead of stopping at the first.
    public func run(_ jobs: [RenderJob]) async -> (outcomes: [Outcome], failures: [(RenderJob, Error)]) {
        var outcomes: [Outcome] = []
        var failures: [(RenderJob, Error)] = []

        let manifest: FrameManifest
        do {
            manifest = try await store.manifest()
        } catch {
            return ([], jobs.map { ($0, error) })
        }

        for job in jobs {
            do {
                let prepared = try await prepare(job, manifest: manifest)
                outcomes.append(try render(prepared))
            } catch {
                failures.append((job, error))
            }
        }
        return (outcomes, failures)
    }
}
