import AVFoundation
import SwiftUI
import UIKit

/// Answers the feasibility question the package actually depends on.
///
/// The matrix proves *whether* `preventsCapture` removes pixels. It does not prove the mechanism can
/// carry anything a real app would show - and a solid colour cannot answer that. So this mode puts
/// **real rendered content** (gradient, block, glyphs, 1px detail) into two full-width display
/// layers that differ only in the flag:
///
///   * top    - `preventsCapture = true` over an opaque black shield: the construction the package
///              would ship, where "pixels removed" becomes the literal "region is black".
///   * bottom - `preventsCapture = false`: the fidelity reference. It isolates "does the
///              CMSampleBuffer pipeline preserve the content" from "does the flag blank the layer".
///
/// Measured: does the protected layer paint at all, how faithful is the unprotected one, and what
/// does pushing frames cost. The host screenshot is the ground truth for what the display shows,
/// because it reads the display surface and therefore cannot be fooled by capture protection.
enum FeasibilityProbe {

    @MainActor
    static func run(window: UIWindow) async {
        let log = RunLog.shared
        let runID = Config.runID
        log.log("=== CaptureMatrix feasibility \(runID) ===")
        log.log("FEASIBILITY device=\(UIDevice.current.model) \(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion) screenScale=\(UIScreen.main.scale)")

        guard let reference = findHost(in: window, preventsCapture: false),
              let protected = findHost(in: window, preventsCapture: true) else {
            log.log("FEASIBILITY NOT-MEASURED: could not find both display-layer hosts in the hierarchy")
            return
        }
        log.log("FEASIBILITY protected host bounds=\(Int(protected.bounds.width))x\(Int(protected.bounds.height)) "
            + "| reference host bounds=\(Int(reference.bounds.width))x\(Int(reference.bounds.height))")

        let source = FeasibilityContent.render(size: protected.bounds.size, scale: UIScreen.main.scale)
        guard let sourceImage = source.cgImage else {
            log.log("FEASIBILITY NOT-MEASURED: could not render source content")
            return
        }
        log.log("FEASIBILITY source \(sourceImage.width)x\(sourceImage.height) "
            + "(UIGraphicsImageRenderer over a real view hierarchy: gradient + block + glyphs + 1px grid)")
        if let url = log.writePNG(sourceImage, name: "feasibility-source.png") {
            log.log("FEASIBILITY WROTE \(url.path)")
        }

        // --- 1. Push the same content into both layers -------------------------
        protected.contentProvider = nil
        reference.contentProvider = nil
        let protectedAccepted = protected.display(sourceImage)
        let referenceAccepted = reference.display(sourceImage)
        log.log("FEASIBILITY enqueue protected accepted=\(protectedAccepted) status=\(protected.rendererStatus) "
            + "ready=\(protected.isReadyForMoreMediaData)")
        log.log("FEASIBILITY enqueue reference accepted=\(referenceAccepted) status=\(reference.rendererStatus) "
            + "ready=\(reference.isReadyForMoreMediaData)")

        // Hold so the host script can screenshot the real display.
        let hold = Double(Config.value(for: "-Hold") ?? "12") ?? 12
        log.log("FEASIBILITY holding \(Int(hold))s so the host can screenshot the display")
        try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))

        // --- 2. What each readback path actually sees --------------------------
        //
        // `CALayer.render(in:)` is deliberately NOT used for the display-layer readback here.
        // Measured: it cannot see `AVSampleBufferDisplayLayer` content at all - the layer is
        // render-server backed, so the tree walk yields the backing colour instead of the frames.
        // In the matrix run that made the `capture=OFF` band read sentinel while `drawHierarchy`
        // read its real colour on the same screen. `drawHierarchy` DOES see the enqueued frames, so
        // it is the only public app-side readback that can measure fidelity.
        let render = CapturePaths.appRender(window: window)
        guard let renderImage = render.image else {
            log.log("FEASIBILITY NOT-MEASURED: app-render produced no image")
            return
        }
        if let url = log.writePNG(renderImage, name: "feasibility-app-render.png") {
            log.log("FEASIBILITY WROTE \(url.path)")
        }

        // Reference half (bottom): fidelity of arbitrary content through the CMSampleBuffer pipeline.
        measureFidelity(source: sourceImage, captured: renderImage,
                        windowRegion: CGRect(x: 0.06, y: 0.58, width: 0.88, height: 0.37),
                        sourceHalf: 1, label: "reference-layer(capture=OFF)")

        // Protected half (top): does the protected layer contribute any pixels at all?
        reportRegion(renderImage, region: CGRect(x: 0.06, y: 0.10, width: 0.88, height: 0.37),
                     label: "protected-layer(capture=ON)")

        // --- 4. Cadence and cost ------------------------------------------------
        await measureThroughput(host: protected, source: sourceImage, label: "protected")
        await measureThroughput(host: reference, source: sourceImage, label: "reference")

        let summaryURL = log.writeJSON([
            "runID": runID,
            "mode": "feasibility",
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "protectedBounds": [protected.bounds.width, protected.bounds.height],
            "sourceSize": [sourceImage.width, sourceImage.height],
        ], name: "feasibility-\(runID).json")
        if let summaryURL { log.log("WROTE \(summaryURL.path)") }
        log.log("WROTE \(log.writeText("feasibility-\(runID).log").path)")
        log.log("=== CaptureMatrix feasibility \(runID) done ===")
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    /// Reads a region of a capture and classifies it, using the sentinel to distinguish
    /// "the black shield is showing" from "the layer contributed nothing at all".
    private static func reportRegion(_ image: CGImage, region: CGRect, label: String) {
        let log = RunLog.shared
        guard let pixels = PixelAnalyzer.withBitmap(image, { bitmap -> [(Int, Int, Int)] in
            PixelAnalyzer.sample(bitmap, normalizedRect: region)
        }), !pixels.isEmpty else {
            log.log("FEASIBILITY region[\(label)] NOT-MEASURED: no samples")
            return
        }
        let count = pixels.count
        let mean = (r: Double(pixels.reduce(0) { $0 + $1.0 }) / Double(count),
                    g: Double(pixels.reduce(0) { $0 + $1.1 }) / Double(count),
                    b: Double(pixels.reduce(0) { $0 + $1.2 }) / Double(count))
        let maxChannel = pixels.map { max($0.0, max($0.1, $0.2)) }.max() ?? 0
        let nonBlack = pixels.filter { max($0.0, max($0.1, $0.2)) >= 32 }.count
        let verdict = maxChannel < 32 ? "NO-LEAK(black)" : "OTHER(not black)"
        log.log("FEASIBILITY region[\(label)] meanRGB="
            + "(\(Int(mean.r.rounded())), \(Int(mean.g.rounded())), \(Int(mean.b.rounded()))) "
            + "maxChannel=\(maxChannel) nonBlackPixels=\(nonBlack)/\(count) -> \(verdict)")
    }

    // MARK: - Fidelity

    /// Mean absolute per-channel error between what was pushed and what the layer shows.
    ///
    /// A display layer goes through a BGRA round-trip and a possible colour-space conversion, so
    /// exact equality is not expected. Both images are sampled over the same normalised region,
    /// which makes the comparison independent of the source being rendered at screen scale and the
    /// readback at 1x.
    private static func measureFidelity(source: CGImage, captured: CGImage,
                                        windowRegion: CGRect, sourceHalf: Int, label: String) {
        let log = RunLog.shared
        guard let sourceBitmap = PixelAnalyzer.bitmap(source) else {
            log.log("FEASIBILITY fidelity[\(label)] NOT-MEASURED: source normalisation failed")
            return
        }
        // The source image is one half of the window, so map the window region into it.
        let sourceRegion = CGRect(x: windowRegion.minX,
                                  y: windowRegion.minY * 2 - Double(sourceHalf),
                                  width: windowRegion.width,
                                  height: windowRegion.height * 2)
        // Fixed-grid sampling: the source is ~3x the readback's linear size, so a pixel-step sample
        // would zip unrelated pixels together. See PixelAnalyzer.sampleGrid.
        let sourcePixels = PixelAnalyzer.sampleGrid(sourceBitmap, normalizedRect: sourceRegion)
        let capturedPixels = PixelAnalyzer.withBitmap(captured) { bitmap -> [(Int, Int, Int)] in
            PixelAnalyzer.sampleGrid(bitmap, normalizedRect: windowRegion)
        } ?? []

        guard !capturedPixels.isEmpty, !sourcePixels.isEmpty else {
            log.log("FEASIBILITY fidelity[\(label)] NOT-MEASURED: empty sample sets "
                + "(source=\(sourcePixels.count) captured=\(capturedPixels.count))")
            return
        }

        let count = min(sourcePixels.count, capturedPixels.count)
        var errorSum = 0.0
        var maxError = 0.0
        for index in 0..<count {
            let a = sourcePixels[index]
            let b = capturedPixels[index]
            let error = (abs(Double(a.0 - b.0)) + abs(Double(a.1 - b.1)) + abs(Double(a.2 - b.2))) / 3
            errorSum += error
            maxError = max(maxError, error)
        }
        let meanError = errorSum / Double(count)
        log.log("FEASIBILITY fidelity[\(label)] windowRegion=\(windowRegion) sourceRegion=\(sourceRegion) "
            + "comparedPixels=\(count) meanAbsChannelError=\(Stats.fmt(meanError)) "
            + "maxAbsChannelError=\(Stats.fmt(maxError)) (0 = identical, 255 = inverted)")
        log.log("FEASIBILITY fidelity[\(label)] sourceSampleRGB=\(sourcePixels[count / 2]) "
            + "capturedSampleRGB=\(capturedPixels[count / 2])")
    }

    // MARK: - Cadence and cost

    private static func measureThroughput(host: SampleBufferHostView, source: CGImage, label: String) async {
        let log = RunLog.shared
        let frames = 60
        var enqueueDurations: [Double] = []
        let cpuBefore = Stats.cpuSeconds()
        let footprintBefore = Stats.footprintMB()
        let wallStart = Stats.now()

        for _ in 0..<frames {
            let start = Stats.now()
            host.display(source)
            enqueueDurations.append(Stats.now() - start)
            // Pace at 60fps so this measures sustained throughput, not a spin loop.
            try? await Task.sleep(nanoseconds: 16_000_000)
        }

        let wall = Stats.now() - wallStart
        let cpu = Stats.cpuSeconds() - cpuBefore
        let footprintDelta = Stats.footprintMB() - footprintBefore
        let sorted = enqueueDurations.sorted()

        log.log("FEASIBILITY throughput[\(label)] frames=\(frames) wall=\(Stats.fmt(wall))s "
            + "achievedFPS=\(Stats.fmt(Double(frames) / wall)) "
            + "enqueue ms median=\(Stats.fmt(Stats.percentile(sorted, 0.5) * 1000)) "
            + "p95=\(Stats.fmt(Stats.percentile(sorted, 0.95) * 1000)) "
            + "max=\(Stats.fmt((sorted.last ?? 0) * 1000))")
        log.log("FEASIBILITY cost[\(label)] cpuSeconds=\(Stats.fmt(cpu, 3)) "
            + "cpuPerFrameMs=\(Stats.fmt(cpu / Double(frames) * 1000, 3)) "
            + "footprintDeltaMB=\(Stats.fmt(footprintDelta)) enqueueCount=\(host.enqueueCount) "
            + "rendererStatus=\(host.rendererStatus)")
    }

    // MARK: - Helpers

    private static func findHost(in window: UIWindow, preventsCapture: Bool) -> SampleBufferHostView? {
        func search(_ view: UIView) -> SampleBufferHostView? {
            if let host = view as? SampleBufferHostView, host.preventsCapture == preventsCapture { return host }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(window)
    }
}

/// Real content for the fidelity test: text, a block, and fine detail - the things a financial app
/// would actually be showing. A solid colour would make fidelity trivially perfect and prove nothing.
enum FeasibilityContent {
    @MainActor
    static func render(size: CGSize, scale: CGFloat) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            let cgContext = context.cgContext
            let colours = [UIColor(red: 0.05, green: 0.10, blue: 0.35, alpha: 1).cgColor,
                           UIColor(red: 0.55, green: 0.10, blue: 0.30, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colours as CFArray, locations: [0, 1]) {
                cgContext.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: bounds.width, y: bounds.height),
                                             options: [])
            }
            UIColor(red: 0.10, green: 0.80, blue: 0.55, alpha: 1).setFill()
            cgContext.fill(CGRect(x: bounds.width * 0.08, y: bounds.height * 0.10,
                                  width: bounds.width * 0.36, height: bounds.height * 0.22))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: max(12, bounds.height * 0.075), weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
            ]
            ("ACCT 4417-8823-0019\nBAL 1,284,930.55\n" as NSString).draw(
                in: CGRect(x: bounds.width * 0.08, y: bounds.height * 0.38,
                           width: bounds.width * 0.84, height: bounds.height * 0.40),
                withAttributes: attributes)
            // Fine detail: a 1px-ish grid, the first thing a scaled layer loses.
            cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            cgContext.setLineWidth(1)
            var x = 0.0
            while x < bounds.width {
                cgContext.move(to: CGPoint(x: x, y: bounds.height * 0.82))
                cgContext.addLine(to: CGPoint(x: x, y: bounds.height * 0.95))
                x += 6
            }
            cgContext.strokePath()
        }
    }
}

/// Two stacked full-width display layers. The top one is the package construction (protected layer
/// over an opaque black shield); the bottom is the unprotected fidelity reference.
struct FeasibilityView: View {
    var body: some View {
        FeasibilityStackRepresentable()
            .ignoresSafeArea()
            .background(ProbeRunner(mode: .feasibility))
    }
}

private struct FeasibilityStackRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 0

        // Protected: opaque black shield, so "pixels removed" reads as literal black.
        let protected = FeasibilityHostView(preventsCapture: true, backing: .black,
                                            label: "PROTECTED  preventsCapture=true over black shield")
        // Reference: sentinel backing, so a non-painting layer is unmistakable here too.
        let reference = FeasibilityHostView(preventsCapture: false, backing: sentinelColor,
                                            label: "REFERENCE  preventsCapture=false (fidelity)")
        stack.addArrangedSubview(protected)
        stack.addArrangedSubview(reference)
        return stack
    }

    func updateUIView(_ uiView: UIStackView, context: Context) {}
}

/// A display-layer host with a label chip, for the feasibility layout.
final class FeasibilityHostView: UIView {
    let host: SampleBufferHostView

    init(preventsCapture: Bool, backing: UIColor, label: String) {
        host = SampleBufferHostView(preventsCapture: preventsCapture)
        super.init(frame: .zero)
        backgroundColor = backing
        isUserInteractionEnabled = false
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let chip = UILabel()
        chip.text = label
        chip.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        chip.textColor = .white
        chip.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        chip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chip)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            chip.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
