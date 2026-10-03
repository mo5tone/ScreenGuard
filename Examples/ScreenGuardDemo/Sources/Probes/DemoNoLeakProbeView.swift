//
//  DemoNoLeakProbeView.swift
//  ScreenGuardDemo
//
//  The scripted no-leak page. Three regions over one sentinel background, read back through the
//  app-side render path, with every number written to Documents for the host script.
//
//  THE THREE REGIONS, AND WHAT EACH ONE IS FOR
//  -------------------------------------------
//    control       — the sensitive card with NO protection. It must read SENSITIVE in the capture.
//                    Without it, "the protected regions are blank" could mean "this read path cannot
//                    image anything", which is exactly the false positive that a calibration band
//                    exists to rule out (`docs/evidence/capability-matrix.md` §3 row 7).
//    publicShield  — `AVSampleBufferDisplayLayer.preventsCapture = true` over an opaque black shield.
//                    ⚠️ On Simulator this layer paints NOTHING AT ALL, on screen included, so its
//                    capture reading is UNEARNED and is reported as device-required
//                    (`docs/TOOLING.md` §7.1).
//    privateShield — the opt-in private secure-layer swap. Measured to blank arbitrary content in the
//                    app-side render path while still painting on the display
//                    (`docs/evidence/capability-matrix.md` §3 rows 4 and 6). ⚠️ PRIVATE API.
//
//  THE HOST-SIDE SCREENSHOT THE SCRIPT ALSO TAKES IS NOT EVIDENCE. `xcrun simctl io screenshot` reads
//  the simulator's display surface from the host and bypasses capture protection by construction
//  (`docs/TOOLING.md` §2). It is collected only as a contrast, and `Scripts/verify_capture.sh` never
//  lets it decide a verdict.
//

import UIKit
import ScreenGuard

/// The scripted three-region no-leak page.
@MainActor
final class DemoNoLeakProbeView: UIView {

    private let runID: String
    private let privateOptIn: Bool

    /// The sensitive card inside the unshielded control region.
    private let controlCard = DemoSensitiveCard()

    /// The public-path shield container.
    private var publicContainer: DemoShieldContainer?

    /// The private-path shield container.
    private var privateContainer: DemoShieldContainer?

    /// The most recent readings, kept so the summary can be re-written after the retries settle.
    private var lastReadings: [AppSideReadback.Reading] = []

    /// How many read-and-write passes have run. The second pass re-writes the artifacts with a
    /// `-final` suffix, because the private path can take a layout pass or two to engage.
    private var pass = 0

    /// Creates the probe page.
    ///
    /// - Parameters:
    ///   - runID: The host script's run identifier, used in artifact names.
    ///   - privateOptIn: Whether the private-API opt-in is granted. Off unless the caller asked.
    init(runID: String, privateOptIn: Bool) {
        self.runID = runID
        self.privateOptIn = privateOptIn
        super.init(frame: .zero)
        // The sentinel behind every region. This is what makes "the region is blank" interpretable:
        // reading the sentinel means the region's pixels were excluded, reading black means an opaque
        // backing was captured instead, and the two are different outcomes.
        backgroundColor = DemoGeometry.sentinelColour
        build()
    }

    /// Unavailable. Use `init(runID:privateOptIn:)`.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DemoNoLeakProbeView must be created programmatically") }

    // MARK: - Construction

    private func build() {
        let control = regionContainer(
            DemoGeometry.control,
            title: "1 CONTROL — unshielded",
            detail: "must read SENSITIVE in the capture"
        )
        control.addSubview(controlCard)
        pin(controlCard, to: control)

        let publicContainer = DemoShieldContainer(
            strategy: .publicPreventsCaptureLayer,
            content: DemoSensitiveCard()
        )
        self.publicContainer = publicContainer
        let publicRegion = regionContainer(
            DemoGeometry.publicShield,
            title: "2 PUBLIC preventsCapture layer",
            detail: "DEVICE-REQUIRED on Simulator"
        )
        publicRegion.addSubview(publicContainer)
        pin(publicContainer, to: publicRegion)

        let privateContainer = DemoShieldContainer(
            strategy: privateOptIn ? .privateSecureLayer : .disabled,
            content: DemoSensitiveCard()
        )
        self.privateContainer = privateContainer
        let privateRegion = regionContainer(
            DemoGeometry.privateShield,
            title: "3 PRIVATE secure-layer swap (opt-in)",
            detail: privateOptIn ? "opt-in GRANTED" : "opt-in NOT granted — falls back, unprotected"
        )
        privateRegion.addSubview(privateContainer)
        pin(privateContainer, to: privateRegion)

        // The regions are positioned in `layoutSubviews` from the same normalised rects the host
        // script samples, so the two cannot disagree about where a region is. A constraint constant
        // cannot express "12% of the container height", and a layout guide per region would be more
        // machinery than this page needs.
        for (region, geometry) in zip(
            [control, publicRegion, privateRegion], DemoGeometry.probeRegions
        ) {
            addSubview(region)
            regionLayouts.append((region, geometry.normalizedRect))
        }
    }

    /// Region views paired with the normalised rect they must occupy.
    private var regionLayouts: [(UIView, CGRect)] = []

    /// Positions each region from its normalised rect.
    ///
    /// Positioning happens here rather than in constraints because a constraint constant cannot be
    /// expressed as a fraction of the container, and a `UILayoutGuide` per region would be more
    /// machinery than the page needs.
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

    /// Builds one labelled region container.
    private func regionContainer(
        _ region: DemoGeometry.Region,
        title: String,
        detail: String
    ) -> UIView {
        let container = UIView()
        container.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
        ])

        stack.addArrangedSubview(DemoLabelFactory.chip(title))
        stack.addArrangedSubview(DemoLabelFactory.chip(detail, colour: UIColor(white: 0.85, alpha: 1)))
        return container
    }

    // MARK: - Probe

    /// Runs the probe once the view is in a window.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, pass == 0 else { return }

        let log = DemoLog.shared
        log.log("=== ScreenGuardDemo no-leak probe \(runID) ===")
        log.log("METHOD read-path window.drawHierarchy(in:afterScreenUpdates:false) — the app-side "
            + "screenshot-like read. afterScreenUpdates MUST be false (SIGABRT otherwise, "
            + "docs/TOOLING.md §5).")
        log.log("METHOD colour-space normalised to sRGB before sampling AND before writing PNG "
            + "(docs/TOOLING.md §7.4).")
        log.log("METHOD environment device=\(UIDevice.current.model) system=\(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion) package=ScreenGuard \(ScreenGuard.version)")
        log.log("METHOD private-API compiled in = \(ScreenGuard.PrivateAPI.isCompiledIn); "
            + "runtime opt-in = \(privateOptIn)")
        for region in DemoGeometry.probeRegions {
            log.log("METHOD region \(region.name) rect=\(DemoGeometry.describe(region.normalizedRect)) "
                + "bodyRect=\(DemoGeometry.describe(region.bodyRect)) — \(region.purpose)")
        }
        log.log("METHOD reference sensitiveRGB=\(DemoGeometry.describe(DemoGeometry.sensitiveColour)) "
            + "sentinelRGB=\(DemoGeometry.describe(DemoGeometry.sentinelColour))")
        log.log("METHOD host-side screenshots are CONTRAST ONLY, never evidence (docs/TOOLING.md §2).")

        // Let the window, the shields and the private canvas settle before the first read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.readAndWrite()
        }
        // The private path can need a layout pass to find its canvas. Re-read, and write the `-final`
        // artifacts that the script actually grades.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            self?.readAndWrite()
        }
    }

    /// Reads the window, samples every region, and writes the artifacts.
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
              let bitmap = AppSideReadback.Bitmap(image: image) else {
            log.log("PROBE pass \(pass): the app-side read produced no readable bitmap")
            return
        }

        log.log("PROBE pass \(pass) read=\(image.width)x\(image.height) "
            + "bitsPerComponent=\(image.bitsPerComponent)")

        let readings = DemoGeometry.probeRegions.map {
            AppSideReadback.read(bitmap, region: $0)
        }
        lastReadings = readings
        for reading in readings {
            log.log("SAMPLE app-render(drawHierarchy) | region \(reading.region) | "
                + "meanRGB=\(reading.meanString) medianRGB=\(reading.medianString) "
                + "maxChannel=\(reading.maxChannel) samples=\(reading.samples) "
                + "-> \(reading.verdict.rawValue)")
        }
        logShieldState()

        log.writePNG(image, named: "capture-app-render\(suffix).png")
        writeJSON(readings: readings, suffix: suffix)
        log.writeLog(named: "noleak-\(runID)\(suffix).log")
        log.log("WROTE noleak-\(runID)\(suffix).log and capture-app-render\(suffix).png")
    }

    /// Records what each shield is actually doing, as opposed to what it was asked to do.
    private func logShieldState() {
        let log = DemoLog.shared
        for (name, container) in [("publicShield", publicContainer), ("privateShield", privateContainer)] {
            guard let container else { continue }
            let shield = container.shield
            let failure = shield.protectionFailure?.rawValue ?? "none"
            // `requested` comes from the CONTAINER, not from `shield.requestedStrategy`.
            // `DemoShieldContainer` deliberately builds its shield inert (`.disabled`) and then
            // applies the requested strategy once it is in a window, and `requestedStrategy` on the
            // package type is a `let` fixed at init — so reading it here would always print
            // "disabled" and misreport what the demo asked for.
            log.log("SHIELD \(name) | requested=\(container.requestedStrategy.rawValue) "
                + "effective=\(shield.effectiveStrategy.rawValue) mode=\(shield.shieldMode.rawValue) "
                + "isProtecting=\(shield.isProtecting) protectionFailure=\(failure)")
        }
    }

    /// Writes the machine-readable summary the host script grades.
    private func writeJSON(readings: [AppSideReadback.Reading], suffix: String) {
        var regions: [[String: Any]] = []
        for (reading, geometry) in zip(readings, DemoGeometry.probeRegions) {
            regions.append([
                "name": reading.region,
                "purpose": geometry.purpose,
                "normalizedRect": DemoGeometry.describe(geometry.normalizedRect),
                "bodyRect": DemoGeometry.describe(geometry.bodyRect),
                "meanRGB": [reading.mean.r, reading.mean.g, reading.mean.b],
                "medianRGB": [reading.median.r, reading.median.g, reading.median.b],
                "maxChannel": reading.maxChannel,
                "samples": reading.samples,
                "verdict": reading.verdict.rawValue,
            ])
        }

        var shields: [String: Any] = [:]
        for (name, container) in [("publicShield", publicContainer), ("privateShield", privateContainer)] {
            guard let container else { continue }
            let shield = container.shield
            shields[name] = [
                // What the DEMO asked for. Taken from the container: the shield type's own
                // `requestedStrategy` is a `let` fixed at init, and the container intentionally
                // builds its shield inert (`.disabled`) before applying the real strategy.
                "requestedStrategy": container.requestedStrategy.rawValue,
                "effectiveStrategy": shield.effectiveStrategy.rawValue,
                "shieldMode": shield.shieldMode.rawValue,
                "isProtecting": shield.isProtecting,
                "protectionFailure": shield.protectionFailure?.rawValue ?? NSNull(),
            ]
        }

        let object: [String: Any] = [
            "runID": runID,
            "pass": pass,
            "readPath": "window.drawHierarchy(in:afterScreenUpdates:false)",
            "packageVersion": ScreenGuard.version,
            "privateAPICompiledIn": ScreenGuard.PrivateAPI.isCompiledIn,
            "privateAPIOptIn": privateOptIn,
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "sensitiveRGB": DemoGeometry.describe(DemoGeometry.sensitiveColour),
            "sentinelRGB": DemoGeometry.describe(DemoGeometry.sentinelColour),
            "regions": regions,
            "shields": shields,
            "hostSideCaptureIsEvidence": false,
        ]
        DemoLog.shared.writeJSON(object, named: "noleak-\(runID)\(suffix).json")
    }
}
