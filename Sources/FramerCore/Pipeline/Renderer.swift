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

    /// One screenshot with its detected device and resolved frame.
    public struct Screen: Sendable {
        public var input: URL
        public var device: Device
        public var orientation: Orientation
        public var landscapeSide: LandscapeSide
        public var screenshotSize: PixelSize
        public var frame: FrameStore.ResolvedFrame
    }

    public struct Prepared: Sendable {
        public var job: RenderJob
        /// One per device, in drawing order. The first is the primary screenshot.
        public var screens: [Screen]

        public var device: Device { screens[0].device }
        public var orientation: Orientation { screens[0].orientation }
        public var screenshotSize: PixelSize { screens[0].screenshotSize }
        public var frame: FrameStore.ResolvedFrame { screens[0].frame }
    }

    public struct Outcome: Sendable {
        public var job: RenderJob
        /// One file per page.
        public var outputs: [URL]
        public var screens: [Screen]
        /// Size of each page.
        public var size: PixelSize

        public var output: URL { outputs[0] }
        public var device: Device { screens[0].device }
        public var frameColor: String { screens[0].frame.color }
    }

    /// Resolves the devices and frames for a job, downloading frames if needed.
    public func prepare(_ job: RenderJob, manifest: FrameManifest) async throws -> Prepared {
        var screens: [Screen] = []
        for source in job.sources {
            screens.append(try await prepareScreen(source, manifest: manifest))
        }
        for (index, callout) in (job.inset?.callouts ?? []).enumerated() where job.mode == .inset {
            try validate(callout, index: index, screens: screens)
        }
        return Prepared(job: job, screens: screens)
    }

    private func prepareScreen(_ source: RenderJob.Source, manifest: FrameManifest) async throws -> Screen {
        let size = try ImageLoader.size(of: source.input)

        let device: Device
        let orientation: Orientation
        if let name = source.deviceName {
            guard let forced = DeviceCatalog.named(name) else { throw FramerError.unknownDeviceName(name) }
            device = forced
            orientation = size.isLandscape ? .landscape : .portrait
            if size != device.screenSize && size != device.screenSize.swapped {
                Log.warn("\(source.input.lastPathComponent) is \(size), not \(device.name)'s \(device.screenSize); screenshot will be scaled to fill the frame")
            }
        } else {
            guard let detected = DeviceCatalog.detect(size) else {
                throw FramerError.unknownDevice(size, path: source.input.path)
            }
            (device, orientation) = detected
        }

        if device.usesBorrowedFrame, verbose {
            Log.info("\(device.name) has no dedicated frame; using \(device.framePrefix) frame")
        }

        let frame = try await store.frame(for: device, color: source.frameColor, manifest: manifest)
        return Screen(
            input: source.input,
            device: device,
            orientation: orientation,
            landscapeSide: source.landscapeSide,
            screenshotSize: size,
            frame: frame
        )
    }

    private func validate(_ callout: CalloutSpec, index: Int, screens: [Screen]) throws {
        guard screens.indices.contains(callout.device) else {
            throw FramerError.config("callouts[\(index)] refers to device \(callout.device), but there are only \(screens.count)")
        }
        let size = screens[callout.device].screenshotSize
        let bounds = CGRect(origin: .zero, size: size.cgSize)
        guard !callout.region.isEmpty, bounds.contains(callout.region) else {
            let r = callout.region
            throw FramerError.config("callouts[\(index)] region \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)) is not inside the \(size) screenshot")
        }
        guard callout.scale > 0 else {
            throw FramerError.config("callouts[\(index)] scale must be greater than 0")
        }
    }

    /// A screenshot composited into its frame, plus what callouts need to find regions of it.
    private struct FramedScreen {
        var framed: CGImage
        var screenshot: CGImage
        var fill: (rect: CGRect, scale: Double)
    }

    private func frame(_ screen: Screen) throws -> FramedScreen {
        let screenshot = try ImageLoader.load(screen.input)
        let frameImage = try ImageLoader.load(screen.frame.fileURL)

        let cutout = FrameGeometry.portraitCutout(offset: screen.frame.offset, frameScreenSize: screen.device.effectiveFrameScreenSize)
        try FrameGeometry.validate(cutout: cutout, frameSize: frameImage.pixelSize, filename: screen.frame.filename)
        let geometry = FrameGeometry.oriented(
            frameSize: frameImage.pixelSize,
            cutout: cutout,
            orientation: screen.orientation,
            side: screen.landscapeSide
        )

        let framed = FrameCompositor.composite(FrameCompositor.Input(
            screenshot: screenshot,
            frame: frameImage,
            geometry: geometry,
            cornerRadius: screen.device.cornerRadius
        ))
        let fill = FrameGeometry.aspectFill(content: screenshot.pixelSize, into: geometry.cutout)
        return FramedScreen(framed: framed, screenshot: screenshot, fill: fill)
    }

    /// Renders and writes the output image(s).
    public func render(_ prepared: Prepared) throws -> Outcome {
        let job = prepared.job
        let screens = try prepared.screens.map(frame)
        let primary = screens[0]

        let sizing = OutputSizing.resolve(
            requestedWidth: job.requestedWidth,
            requestedHeight: job.requestedHeight,
            native: primary.screenshot.pixelSize,
            framedSize: primary.framed.pixelSize
        )
        if sizing.clamped {
            Log.warn("requested output exceeds native \(primary.screenshot.pixelSize) for \(job.input.lastPathComponent); clamped to \(sizing.size)")
        }
        let canvas = sizing.size

        let results: [CGImage]
        switch job.mode {
        case .simple:
            var background = job.background
            if background == nil, job.format == .jpeg {
                background = GradientSpec(solid: .white)
            }
            try background?.validate()
            results = [SimpleRenderer.render(framed: primary.framed, canvas: canvas, background: background)]

        case .inset:
            guard let inset = job.inset else {
                throw FramerError.config("inset mode requires text settings")
            }
            let background = job.background ?? GradientSpec(solid: .white)
            try background.validate()
            let pages = inset.resolvedPages
            if pages.allSatisfy({ $0.title.isEmpty && $0.subtitle.isEmpty }) {
                Log.warn("\(job.input.lastPathComponent): inset mode with no title or subtitle")
            }

            let layers = inset.devices.isEmpty
                ? [InsetRenderer.Layer(framed: primary.framed)]
                : zip(screens, inset.devices).map { InsetRenderer.Layer(framed: $0.framed, placement: $1.placement) }
            let callouts = try inset.callouts.map { spec -> InsetRenderer.Callout in
                let screen = screens[spec.device]
                guard let crop = screen.screenshot.cropping(to: spec.region) else {
                    throw FramerError.config("callout region is not inside the screenshot")
                }
                return InsetRenderer.Callout(
                    spec: spec,
                    image: crop,
                    region: CalloutLayout.framedRegion(spec.region, screenshotFill: screen.fill)
                )
            }

            let padding = inset.padding ?? (Double(canvas.width) * 0.05).rounded()
            results = try InsetRenderer.render(
                layers: layers,
                callouts: callouts,
                canvas: canvas,
                background: background,
                pages: pages.map { page in
                    InsetRenderer.Text(
                        title: page.title,
                        subtitle: page.subtitle,
                        titleStyle: inset.titleStyle,
                        subtitleStyle: inset.subtitleStyle,
                        position: inset.position,
                        spacing: inset.spacing
                    )
                },
                style: InsetRenderer.Style(
                    padding: padding,
                    gap: inset.gap ?? padding,
                    deviceScale: inset.deviceScale,
                    bleed: inset.bleed,
                    shadow: inset.shadow,
                    textScale: inset.textScale,
                    maxTextRotation: inset.maxTextRotation
                )
            )
        }

        let outputs = job.outputURLs
        for (image, url) in zip(results, outputs) {
            try ImageWriter.write(image, to: url, format: job.format, jpegQuality: job.jpegQuality)
        }
        return Outcome(job: job, outputs: outputs, screens: prepared.screens, size: canvas)
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
