//
//  DemoSwiftUIPrivateProbeView.swift
//  ScreenGuardDemo
//
//  The scripted page for the package's OWN SwiftUI entry point on the private strategy:
//  `.screenGuardProtected(strategy: .privateSecureLayer)`.
//
//  WHY A THIRD PROBE PAGE
//  ----------------------
//  The no-leak page measures `ScreenGuardShieldView.protectedContentView` — a caller-supplied LIVE
//  UIView. The SwiftUI modifier cannot supply one: SwiftUI content is not a `UIView`, so
//  `ScreenGuardShieldRepresentable` hands the shield a **render closure** and nothing else. Measured
//  by two independent probes (P10, P9, review round 2), that route then reported
//  `isProtecting = true` / `shieldMode = .privateSecureLayer` / `protectionFailure = nil` while
//  rendering NOTHING — a blank card with a success claim on top. That is finding F-R2-1.
//
//  This page is the end-to-end measurement of the repair, and it is deliberately built the way the
//  package's own docs tell a consumer to build it: the content goes through
//  `.screenGuardProtected(strategy: .privateSecureLayer)`, with no manual `protectedContentView`, no
//  manual engagement order and no demo-side shield container.
//
//  TWO REGIONS, BECAUSE ONE PROVES NOTHING
//  ---------------------------------------
//    swiftUIControl       — the same SwiftUI card, unshielded. MUST read the sensitive colour, or the
//                           read path is not imaging SwiftUI content and the verdict below is vacuous.
//    swiftUIPrivateShield — the shielded one. Must be readable and must NOT read the sensitive colour
//                           in the app-side render, while the host-side contrast still shows the
//                           content (proving exclusion rather than a region that never painted).
//
//  The host-side contrast capture the script takes alongside it is NOT evidence and cannot produce a
//  verdict (`docs/TOOLING.md` §2). It exists only to tell "excluded from the capture" apart from
//  "never painted", which is the same discriminator the no-leak page uses.
//

import ScreenGuard
import SwiftUI
import UIKit

/// The two-region SwiftUI-route page.
@MainActor
final class DemoSwiftUIPrivateProbeView: UIView {
    private let runID: String
    private let privateOptIn: Bool

    /// Retained: a `UIHostingController`'s view alone does not keep its controller alive.
    private var retainedHosts: [UIViewController] = []

    /// The most recent readings, kept so the summary can be re-written after the retries settle.
    private var lastReadings: [AppSideReadback.Reading] = []

    /// How many read-and-write passes have run. The second one writes the `-final` artifacts the
    /// script grades, because the private canvas can take a layout pass to appear.
    private var pass = 0

    /// Region views paired with the normalised rect they must occupy.
    private var regionLayouts: [(UIView, CGRect)] = []

    /// Creates the probe page.
    ///
    /// - Parameters:
    ///   - runID: The host script's run identifier, used in artifact names.
    ///   - privateOptIn: Whether the private-API opt-in is granted. Off unless the caller asked.
    init(runID: String, privateOptIn: Bool) {
        self.runID = runID
        self.privateOptIn = privateOptIn
        super.init(frame: .zero)
        backgroundColor = DemoGeometry.sentinelColour
        build()
    }

    /// Unavailable. Use `init(runID:privateOptIn:)`.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("DemoSwiftUIPrivateProbeView must be created programmatically")
    }

    // MARK: - Construction

    private func build() {
        let control = regionContainer(
            DemoGeometry.swiftUIControl,
            title: "1 CONTROL — SwiftUI, unshielded",
            detail: "must read SENSITIVE in the capture"
        )
        host(DemoSensitiveSwiftUICard(), in: control)

        // ⚠️ PRIVATE API, and that is the point: this is the strategy the finding is about. The
        // opt-in is granted by `-PrivateOptIn 1` in the demo's `init`, before any shield exists.
        let shielded = DemoSensitiveSwiftUICard()
            .screenGuardProtected(strategy: .privateSecureLayer)
        let shieldedRegion = regionContainer(
            DemoGeometry.swiftUIPrivateShield,
            title: "2 screenGuardProtected(.privateSecureLayer)",
            detail: privateOptIn ? "opt-in GRANTED" : "opt-in NOT granted — labelled fallback"
        )
        host(shielded, in: shieldedRegion)

        for (region, geometry) in zip([control, shieldedRegion], DemoGeometry.swiftUIProbeRegions) {
            addSubview(region)
            regionLayouts.append((region, geometry.normalizedRect))
        }
    }

    /// Positions each region from its normalised rect.
    ///
    /// Positioning happens here rather than in constraints because a constraint constant cannot be
    /// expressed as a fraction of the container. Same reason, and same code, as the no-leak page.
    override func layoutSubviews() {
        super.layoutSubviews()
        for (view, rect) in regionLayouts {
            view.frame = DemoGeometry.absolute(rect, in: bounds.size)
        }
    }

    /// Hosts a SwiftUI view inside a UIKit region container.
    private func host(_ view: some View, in container: UIView) {
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = .clear
        retainedHosts.append(controller)
        let hosted = controller.view!
        hosted.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosted.topAnchor.constraint(equalTo: container.topAnchor),
            hosted.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Builds one labelled region container.
    private func regionContainer(
        _: DemoGeometry.Region,
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
        guard window != nil, pass == 0 else {
            return
        }

        let log = DemoLog.shared
        log.log("=== ScreenGuardDemo SwiftUI-private probe \(runID) ===")
        log.log("ROUTE the package's own SwiftUI modifier: .screenGuardProtected(strategy: "
            + ".privateSecureLayer). No protectedContentView, no demo-side shield container.")
        log.log("METHOD read-path window.drawHierarchy(in:afterScreenUpdates:false) — the app-side "
            + "screenshot-like read. afterScreenUpdates MUST be false (SIGABRT otherwise, "
            + "docs/TOOLING.md §5).")
        log.log("METHOD colour-space normalised to sRGB before sampling AND before writing PNG "
            + "(docs/TOOLING.md §7.4).")
        log.log("METHOD environment device=\(UIDevice.current.model) system=\(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion) package=ScreenGuard \(ScreenGuard.version)")
        log.log("METHOD private-API compiled in = \(ScreenGuard.PrivateAPI.isCompiledIn); "
            + "runtime opt-in = \(privateOptIn)")
        for region in DemoGeometry.swiftUIProbeRegions {
            log.log("METHOD region \(region.name) rect=\(DemoGeometry.describe(region.normalizedRect)) "
                + "bodyRect=\(DemoGeometry.describe(region.bodyRect)) — \(region.purpose)")
        }
        log.log("METHOD reference sensitiveRGB=\(DemoGeometry.describe(DemoGeometry.sensitiveColour)) "
            + "sentinelRGB=\(DemoGeometry.describe(DemoGeometry.sentinelColour))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.readAndWrite()
        }
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
              let bitmap = AppSideReadback.Bitmap(image: image)
        else {
            log.log("PROBE pass \(pass): the app-side read produced no readable bitmap")
            return
        }

        log.log("PROBE pass \(pass) read=\(image.width)x\(image.height) "
            + "bitsPerComponent=\(image.bitsPerComponent)")

        let readings = DemoGeometry.swiftUIProbeRegions.map {
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

        log.writePNG(image, named: "capture-swiftui-private\(suffix).png")
        writeJSON(readings: readings, suffix: suffix)
        log.writeLog(named: "swiftui-private-\(runID)\(suffix).log")
        log.log("WROTE swiftui-private-\(runID)\(suffix).log and capture-swiftui-private\(suffix).png")
    }

    /// Every `ScreenGuardShieldView` in the page's hierarchy.
    ///
    /// The SwiftUI modifier builds its shield inside SwiftUI's own container views, so the probe finds
    /// it by walking the tree rather than by holding a reference. That is the honest way round: a
    /// reference the demo kept could outlive the one the user is actually looking at.
    private func shieldsInTheHierarchy() -> [ScreenGuardShieldView] {
        var found: [ScreenGuardShieldView] = []
        func walk(_ view: UIView) {
            if let shield = view as? ScreenGuardShieldView {
                found.append(shield)
            }
            view.subviews.forEach(walk)
        }
        walk(self)
        return found
    }

    /// Whether the shield is hosting a rendered picture the user can see.
    ///
    /// This is the probe's own reading of the F-R2-1 state, taken from the LIVE HIERARCHY rather than
    /// from the shield's self-report: `isProtecting = true` with nothing hosted is exactly the defect,
    /// so the two must be reported side by side and never merged into one boolean.
    private static func hostsRenderedContent(_ shield: ScreenGuardShieldView) -> Bool {
        var found = false
        func walk(_ view: UIView) {
            guard !found else {
                return
            }
            if let imageView = view as? UIImageView, imageView.image != nil, !imageView.isHidden {
                found = true
                return
            }
            view.subviews.forEach(walk)
        }
        shield.subviews.forEach(walk)
        return found
    }

    /// Records what the SwiftUI route's shield is actually doing.
    private func logShieldState() {
        let log = DemoLog.shared
        let shields = shieldsInTheHierarchy()
        guard !shields.isEmpty else {
            log.log("SHIELD swiftUIRoute | NO ScreenGuardShieldView FOUND IN THE HIERARCHY")
            return
        }
        for (index, shield) in shields.enumerated() {
            let failure = shield.protectionFailure?.rawValue ?? "none"
            log.log("SHIELD swiftUIRoute[\(index)] | requested=\(shield.requestedStrategy.rawValue) "
                + "effective=\(shield.effectiveStrategy.rawValue) mode=\(shield.shieldMode.rawValue) "
                + "isProtecting=\(shield.isProtecting) protectionFailure=\(failure) "
                + "hasPushedFrame=\(shield.hasPushedFrame) "
                + "hostsRenderedContent=\(Self.hostsRenderedContent(shield)) "
                + "subviews=\(shield.subviews.map { String(describing: type(of: $0)) })")
        }
    }

    /// Writes the machine-readable summary the host script grades.
    private func writeJSON(readings: [AppSideReadback.Reading], suffix: String) {
        var regions: [[String: Any]] = []
        for (reading, geometry) in zip(readings, DemoGeometry.swiftUIProbeRegions) {
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
        let found = shieldsInTheHierarchy()
        shields["shieldCount"] = found.count
        if let shield = found.first {
            shields["requestedStrategy"] = shield.requestedStrategy.rawValue
            shields["effectiveStrategy"] = shield.effectiveStrategy.rawValue
            shields["shieldMode"] = shield.shieldMode.rawValue
            shields["isProtecting"] = shield.isProtecting
            shields["protectionFailure"] = shield.protectionFailure?.rawValue ?? NSNull()
            shields["hasPushedFrame"] = shield.hasPushedFrame
            shields["hostsRenderedContent"] = Self.hostsRenderedContent(shield)
            shields["subviewClasses"] = shield.subviews.map { String(describing: type(of: $0)) }
        }

        let object: [String: Any] = [
            "runID": runID,
            "pass": pass,
            "route": "screenGuardProtected(strategy: .privateSecureLayer)",
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
        DemoLog.shared.writeJSON(object, named: "swiftui-private-\(runID)\(suffix).json")
    }
}

// MARK: - The SwiftUI content

/// The sensitive card, in SwiftUI.
///
/// Deliberately the same construction as `DemoSensitiveCard`: the sensitive colour, the secret strings
/// at the top, and a **text-free lower half** — which is the part the pixel check samples, because
/// sampling across glyphs produces false blacks (`docs/TOOLING.md` §5).
///
/// `Color(uiColor:)` rather than `Color(red:green:blue:)` so the SwiftUI card and the UIKit card are
/// the *same* colour object; the pixel check compares against one reference value for both regions.
struct DemoSensitiveSwiftUICard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: DemoGeometry.sensitiveColour)
            VStack(alignment: .leading, spacing: 2) {
                Text(DemoGeometry.secretTitle)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(DemoGeometry.secretDetail)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .padding(8)
        }
    }
}
