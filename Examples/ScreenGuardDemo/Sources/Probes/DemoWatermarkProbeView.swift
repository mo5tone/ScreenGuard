//
//  DemoWatermarkProbeView.swift
//  ScreenGuardDemo
//
//  The scripted watermark page. Two matched bands of the same flat colour: one wearing the tiled
//  forensic watermark, one without it. Both are read back through the app-side render path, and the
//  numbers are written to Documents for `Scripts/verify_capture.sh`.
//
//  WHAT THIS CHECK IS, AND WHAT IT IS NOT
//  -------------------------------------
//  A watermark is a **deterrent and forensic** measure (`docs/api-contract.md` §3.3). It removes
//  **no pixels** from any capture, so it must never be graded as a no-leak control — and it is not.
//  The two things this page can honestly establish are:
//
//    * `watermarkMarked`  — the mark really IS drawn into the app-side capture (the band is not
//      flat). "Present in the capture" is the correct expectation for a watermark and the opposite
//      of the shield's.
//    * `watermarkControl` — the identical band without the mark reads a flat colour. That is the
//      calibration: without it, "the marked band is not flat" could just mean the read path shows
//      noise, and the first result would prove nothing.
//
//  The page additionally emits its tile geometry (tile size, bounds, origins, count) so the host
//  script can check, independently of the app, that the mark tiles cover the whole view.
//

import ScreenGuard
import UIKit

/// The scripted watermark page.
@MainActor
final class DemoWatermarkProbeView: UIView {
    private let runID: String

    /// The band that wears the watermark.
    private let watermarkedCard = UIView()

    /// The matched band with no watermark.
    private let controlCard = UIView()

    /// The watermark itself, held so its laid-out bounds can be reported as geometry.
    private let watermarkView = ScreenGuardWatermarkView(
        configuration: DemoGeometry.watermarkConfiguration
    )

    /// Each band's outer container paired with the normalised rect it must occupy.
    private var regionLayouts: [(UIView, CGRect)] = []

    /// How many read-and-write passes have run.
    private var pass = 0

    /// Creates the probe.
    ///
    /// - Parameter runID: The host script's run identifier.
    init(runID: String) {
        self.runID = runID
        super.init(frame: .zero)
        // A dark page background, so the two blue bands are separated by something that cannot be
        // confused with either the card colour or the mark.
        backgroundColor = .black
        build()
    }

    /// Unavailable. Use `init(runID:)`.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("DemoWatermarkProbeView must be created programmatically")
    }

    // MARK: - Construction

    private func build() {
        let marked = regionContainer()
        watermarkedCard.backgroundColor = DemoGeometry.sensitiveColour
        marked.addSubview(watermarkedCard)
        pin(watermarkedCard, to: marked)
        watermarkView.translatesAutoresizingMaskIntoConstraints = false
        marked.addSubview(watermarkView)
        pin(watermarkView, to: marked)

        let control = regionContainer()
        controlCard.backgroundColor = DemoGeometry.sensitiveColour
        control.addSubview(controlCard)
        pin(controlCard, to: control)

        for (region, geometry) in zip([marked, control], DemoGeometry.watermarkProbeRegions) {
            addSubview(region)
            regionLayouts.append((region, geometry.normalizedRect))
        }
    }

    /// A bare band container. Deliberately has no label: the sampled body rect must contain nothing
    /// but the card and (for the marked band) the watermark.
    private func regionContainer() -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        return container
    }

    /// Positions each band from its normalised rect, using the same rects the script samples.
    override func layoutSubviews() {
        super.layoutSubviews()
        for (view, rect) in regionLayouts {
            view.frame = DemoGeometry.absolute(rect, in: bounds.size)
        }
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    // MARK: - Probe

    /// Runs the probe once the view is in a window.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, pass == 0 else {
            return
        }

        let log = DemoLog.shared
        log.log("=== ScreenGuardDemo watermark probe \(runID) ===")
        log.log("METHOD read-path window.drawHierarchy(in:afterScreenUpdates:false) — the app-side "
            + "screenshot-like read (docs/TOOLING.md §5 keeps afterScreenUpdates false).")
        log.log("METHOD environment device=\(UIDevice.current.model) system=\(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion) package=ScreenGuard \(ScreenGuard.version)")
        log.log("METHOD A WATERMARK IS A DETERRENT, NOT A PROTECTION: it removes no pixels from any "
            + "capture and prevents nothing (docs/api-contract.md §3.3). No no-leak claim is made "
            + "from this page.")
        log.log("METHOD the check is two-sided: the marked band must NOT be flat, and the matched "
            + "un-marked control band MUST be flat. Without the control the first result would only "
            + "prove that the read path shows noise.")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.readAndWrite()
        }
        // The second pass writes the `-final` artifacts the script grades. The watermark is static,
        // so this is belt-and-braces against a first-pass layout that has not settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.readAndWrite()
        }
    }

    /// Reads the window, samples both bands, and writes the artifacts.
    private func readAndWrite() {
        pass += 1
        let log = DemoLog.shared
        let suffix = pass >= 2 ? "-final" : ""

        guard let window else {
            log.log("PROBE pass \(pass): no window; nothing read")
            return
        }
        window.layoutIfNeeded()
        layoutIfNeeded()

        guard let image = AppSideReadback.appRender(window: window),
              let bitmap = AppSideReadback.Bitmap(image: image)
        else {
            log.log("PROBE pass \(pass): the app-side read produced no readable bitmap")
            return
        }

        var readings: [String: [String: Any]] = [:]
        for region in DemoGeometry.watermarkProbeRegions {
            let result = AppSideReadback.deviationFraction(
                bitmap,
                region: region,
                from: DemoGeometry.sensitiveColour,
                threshold: DemoGeometry.watermarkDeviationThreshold
            )
            let reading = AppSideReadback.read(bitmap, region: region)
            log.log("SAMPLE app-render(drawHierarchy) | region \(region.name) | "
                + "meanRGB=\(reading.meanString) maxChannel=\(reading.maxChannel) "
                + "samples=\(result.samples) deviationFraction="
                + String(format: "%.4f", result.fraction))
            readings[region.name] = [
                "meanRGB": [reading.mean.r, reading.mean.g, reading.mean.b],
                "maxChannel": reading.maxChannel,
                "samples": result.samples,
                "deviationFraction": result.fraction,
                "normalizedRect": DemoGeometry.describe(region.normalizedRect),
                "bodyRect": DemoGeometry.describe(region.bodyRect),
                "purpose": region.purpose,
            ]
        }

        log.writePNG(image, named: "watermark-app-render\(suffix).png")
        writeJSON(readings: readings, suffix: suffix)
        log.writeLog(named: "watermark-\(runID)\(suffix).log")
        log.log("WROTE watermark-\(runID)\(suffix).log and watermark-app-render\(suffix).png")
    }

    /// Writes the machine-readable summary the host script grades.
    private func writeJSON(readings: [String: [String: Any]], suffix: String) {
        let configuration = DemoGeometry.watermarkConfiguration
        let bounds = watermarkView.bounds
        let origins = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: configuration.tileSize)

        let object: [String: Any] = [
            "runID": runID,
            "pass": pass,
            "readPath": "window.drawHierarchy(in:afterScreenUpdates:false)",
            "packageVersion": ScreenGuard.version,
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "regions": readings,
            "sensitiveRGB": DemoGeometry.describe(DemoGeometry.sensitiveColour),
            // Geometry, emitted so the host script can check coverage without re-using the app's code.
            "tileSize": DemoGeometry.describe(configuration.tileSize),
            "bounds": DemoGeometry.describe(bounds),
            "tileCount": ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: configuration.tileSize),
            "tileOrigins": origins.map { DemoGeometry.describe($0) },
            "opacity": Double(configuration.opacity),
            "angle": Double(configuration.angle),
            "text": configuration.text,
            "secondaryText": configuration.secondaryText ?? "",
            "markColourRGB": DemoGeometry.describe(configuration.color),
            "deviationThresholdPerChannel": DemoGeometry.watermarkDeviationThreshold,
            // The honesty flag, read back by the script. This capability must never be presented as
            // protection: it removes no pixels from any capture (docs/api-contract.md §3.3).
            "isASecurityControl": false,
            "removesPixelsFromCaptures": false,
        ]
        DemoLog.shared.writeJSON(object, named: "watermark-\(runID)\(suffix).json")
    }
}
