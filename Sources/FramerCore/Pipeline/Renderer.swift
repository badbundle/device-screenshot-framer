import CoreGraphics
import Foundation

/// Orchestrates one job: detect device → fetch frame (or draw a window) → composite → mode render → write.
/// `prepare` is async (network); `render` is synchronous and keeps every CG/CT object on one task.
public struct Renderer: Sendable {
    public var store: FrameStore
    public var verbose: Bool

    public init(store: FrameStore, verbose: Bool = false) {
        self.store = store
        self.verbose = verbose
    }

    /// One screenshot with its detected device and resolved frame, or shown as a window, which has neither.
    public struct Screen: Sendable {
        public var input: URL
        public var frameStyle: FrameStyle
        public var device: Device?
        public var orientation: Orientation
        public var landscapeSide: LandscapeSide
        public var screenshotSize: PixelSize
        public var frame: FrameStore.ResolvedFrame?
    }

    public struct Prepared: Sendable {
        public var job: RenderJob
        /// One per device, in drawing order. The first is the primary screenshot.
        public var screens: [Screen]

        public var device: Device? { screens[0].device }
        public var orientation: Orientation { screens[0].orientation }
        public var screenshotSize: PixelSize { screens[0].screenshotSize }
        public var frame: FrameStore.ResolvedFrame? { screens[0].frame }
    }

    public struct Outcome: Sendable {
        public var job: RenderJob
        /// One file per page.
        public var outputs: [URL]
        public var screens: [Screen]
        /// Size of each page.
        public var size: PixelSize

        public var output: URL { outputs[0] }
        public var device: Device? { screens[0].device }
        public var frameColor: String? { screens[0].frame?.color }
    }

    /// Resolves the devices and frames for a job, downloading frames if needed. `manifest` may be `nil` only when every
    /// screenshot is shown as a window.
    public func prepare(_ job: RenderJob, manifest: FrameManifest?) async throws -> Prepared {
        var screens: [Screen] = []
        for source in job.sources {
            screens.append(try await prepareScreen(source, manifest: manifest))
        }
        for (index, callout) in (job.inset?.callouts ?? []).enumerated() where job.mode == .inset {
            try validate(callout, index: index, screens: screens)
        }
        return Prepared(job: job, screens: screens)
    }

    private func prepareScreen(_ source: RenderJob.Source, manifest: FrameManifest?) async throws -> Screen {
        let size = try ImageLoader.size(of: source.input)

        if source.frameStyle == .window {
            return Screen(
                input: source.input,
                frameStyle: .window,
                device: nil,
                orientation: size.isLandscape ? .landscape : .portrait,
                landscapeSide: source.landscapeSide,
                screenshotSize: size,
                frame: nil
            )
        }

        let device: Device
        let orientation: Orientation
        if let name = source.deviceName {
            guard let forced = DeviceCatalog.named(name) else { throw FramerError.unknownDeviceName(name) }
            device = forced
            orientation = forced.canRotate ? (size.isLandscape ? .landscape : .portrait) : forced.frameOrientation
            if size != device.screenSize && !(device.canRotate && size == device.screenSize.swapped) {
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

        guard let manifest else { throw FramerError.config("\(device.name) needs the frames manifest") }
        let frame = try await store.frame(for: device, color: source.frameColor, manifest: manifest)
        return Screen(
            input: source.input,
            frameStyle: .device,
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

    private func frame(_ screen: Screen, window: WindowStyle) throws -> FramedScreen {
        let screenshot = try ImageLoader.load(screen.input)
        guard let device = screen.device, let resolved = screen.frame else {
            let framed = WindowCompositor.composite(screenshot, style: window)
            return FramedScreen(framed: framed, screenshot: screenshot, fill: (CGRect(origin: .zero, size: framed.pixelSize.cgSize), 1))
        }
        let frameImage = try ImageLoader.load(resolved.fileURL)

        let cutout = FrameGeometry.portraitCutout(offset: resolved.offset, frameScreenSize: device.effectiveFrameScreenSize)
        try FrameGeometry.validate(cutout: cutout, frameSize: frameImage.pixelSize, filename: resolved.filename)
        let geometry = FrameGeometry.oriented(
            frameSize: frameImage.pixelSize,
            cutout: cutout,
            orientation: screen.orientation,
            side: screen.landscapeSide,
            frameOrientation: device.frameOrientation
        )

        let framed = FrameCompositor.composite(FrameCompositor.Input(
            screenshot: screenshot,
            frame: frameImage,
            geometry: geometry,
            cornerRadius: device.cornerRadius
        ))
        let fill = FrameGeometry.aspectFill(content: screenshot.pixelSize, into: geometry.cutout)
        return FramedScreen(framed: framed, screenshot: screenshot, fill: fill)
    }

    /// Renders and writes the output image(s).
    public func render(_ prepared: Prepared) throws -> Outcome {
        let job = prepared.job
        let screens = try prepared.screens.map { try frame($0, window: job.window) }
        let primary = screens[0]

        // The Mac App Store takes the same sizes from any Mac, so a Mac screenshot's canvas is its largest, not the
        // capture's own size: a window has none, and a MacBook's screen is rarely one of them.
        let isMac = prepared.screens[0].frameStyle == .window || prepared.screens[0].device?.isMac == true
        let sizing = OutputSizing.resolve(
            requestedWidth: job.requestedWidth,
            requestedHeight: job.requestedHeight,
            native: isMac ? DeviceCatalog.macCanvas : primary.screenshot.pixelSize,
            framedSize: isMac ? DeviceCatalog.macCanvas : primary.framed.pixelSize,
            clamp: job.clampsSize
        )
        if sizing.clamped {
            let limit = isMac ? "\(DeviceCatalog.macCanvas), the largest Mac App Store size," : "native \(primary.screenshot.pixelSize)"
            Log.warn("requested output exceeds \(limit) for \(job.input.lastPathComponent); clamped to \(sizing.size)")
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

            let shadows = prepared.screens.map { $0.frameStyle == .window ? ShadowSpec() : nil }
            let layers = inset.devices.isEmpty
                ? [InsetRenderer.Layer(framed: primary.framed, shadow: shadows[0])]
                : zip(screens, inset.devices).enumerated().map { index, pair in
                    InsetRenderer.Layer(framed: pair.0.framed, placement: pair.1.placement, shadow: shadows[index])
                }
            let callouts = try inset.callouts.map { spec -> InsetRenderer.Callout in
                let screen = screens[spec.device]
                guard let crop = screen.screenshot.cropping(to: spec.region) else {
                    throw FramerError.config("callout region is not inside the screenshot")
                }
                return InsetRenderer.Callout(
                    spec: spec,
                    image: crop,
                    region: CalloutLayout.framedRegion(spec.region, screenshotFill: screen.fill),
                    offset: CalloutLayout.framedOffset(spec, screenshotFill: screen.fill)
                )
            }

            let backdrop = InsetRenderer.Backdrop(
                glows: inset.glows,
                images: try inset.backgroundImages.map { spec in
                    InsetRenderer.Backdrop.Image(image: try ImageLoader.load(spec.input), placement: spec.placement, opacity: spec.opacity)
                }
            )

            let padding = inset.padding ?? (canvas.shorterSide * 0.05).rounded()
            results = try InsetRenderer.render(
                layers: layers,
                callouts: callouts,
                canvas: canvas,
                background: background,
                backdrop: backdrop,
                pages: pages.map { page in
                    InsetRenderer.Text(
                        title: page.title,
                        subtitle: page.subtitle,
                        titleStyle: inset.titleStyle,
                        subtitleStyle: inset.subtitleStyle,
                        position: inset.position,
                        spacing: inset.spacing,
                        accent: page.accent.isEmpty ? nil : TextAccent(text: page.accent, color: inset.accentColor)
                    )
                },
                style: InsetRenderer.Style(
                    padding: padding,
                    gap: inset.gap ?? padding,
                    deviceScale: inset.deviceScale,
                    bleed: inset.bleed,
                    shadow: inset.shadow,
                    textScale: inset.textScale,
                    maxTextRotation: inset.maxTextRotation,
                    textAnchor: inset.textAnchor
                )
            )
        }

        let outputs = job.outputURLs
        for (image, url) in zip(results, outputs) {
            try ImageWriter.write(image, to: url, format: job.format, jpegQuality: job.jpegQuality, opaque: job.opaque)
        }
        return Outcome(job: job, outputs: outputs, screens: prepared.screens, size: canvas)
    }

    /// Runs every job, collecting failures instead of stopping at the first.
    public func run(_ jobs: [RenderJob]) async -> (outcomes: [Outcome], failures: [(RenderJob, Error)]) {
        var outcomes: [Outcome] = []
        var failures: [(RenderJob, Error)] = []

        var manifest: FrameManifest?
        if jobs.contains(where: \.needsFrames) {
            do {
                manifest = try await store.manifest()
            } catch {
                return ([], jobs.map { ($0, error) })
            }
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
