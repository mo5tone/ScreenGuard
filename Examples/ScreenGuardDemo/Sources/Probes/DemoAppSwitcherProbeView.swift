//
//  DemoAppSwitcherProbeView.swift
//  ScreenGuardDemo
//
//  Capability 4 — app-switcher snapshot protection.
//
//  WHAT THIS CAN AND CANNOT ESTABLISH ON SIMULATOR
//  ----------------------------------------------
//  * **CAN**: that the cover is installed on the window, and that it engages **synchronously** when
//    the scene deactivates. The host script backgrounds the app with `sim-use button home`, which is
//    the only reliable headless way to do it (`docs/TOOLING.md` §2), and then reads back the
//    timestamps this probe writes.
//  * **CANNOT**: that the *snapshot pixels* are redacted. The system writes the snapshot to
//    `data/Library/SplashBoard/Snapshots/**/*.ktx` in Apple's proprietary `AAPL`-magic KTX variant,
//    which neither ImageMagick nor ffmpeg can decode (`docs/TOOLING.md` §4). This capability is
//    **device-validated only**, and the script reports it that way.
//
//  The synchrony check is worth having on its own: `docs/api-contract.md` §6.7 makes a deferred
//  cover a defect, because the system snapshots immediately after
//  `UIScene.willDeactivateNotification`. This probe measures the interval between the notification
//  and the cover being visible, and fails the check if the cover is not already engaged inside the
//  notification handler.
//

import UIKit
import ScreenGuard

/// Runs the app-switcher probe.
@MainActor
final class DemoAppSwitcherProbeView: UIView {

    private let runID: String
    private let shield = ScreenGuardAppSwitcherShield(style: .blur(style: .systemMaterial))
    private let stateLabel = UILabel()

    /// One observed lifecycle transition.
    private struct Transition {
        let name: String
        /// Seconds since the probe started, from `CACurrentMediaTime()`.
        let at: Double
        /// Whether the shield was already covering at this instant.
        let isCovering: Bool
        /// Whether the shield was hidden at this instant.
        let isHidden: Bool
        /// The cover's alpha.
        let alpha: CGFloat
    }

    private var transitions: [Transition] = []

    /// Whether the shield was covering when the last deactivation notification arrived.
    ///
    /// This is the whole synchrony assertion: the notification handler runs on the main queue, so if
    /// the shield's own handler ran before this probe's handler, `isCovering` is `true` here.
    private var wasCoveringAtDeactivate = false

    /// The probe's start time, for relative timestamps.
    private let startedAt = CACurrentMediaTime()

    /// Creates the probe.
    ///
    /// - Parameter runID: The host script's run identifier.
    init(runID: String) {
        self.runID = runID
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        build()
    }

    /// Unavailable. Use `init(runID:)`.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DemoAppSwitcherProbeView must be created programmatically") }

    private func build() {
        let title = UILabel()
        title.text = "App-switcher snapshot protection"
        title.font = .preferredFont(forTextStyle: .title3)
        title.numberOfLines = 0

        let note = UILabel()
        note.text = """
            This page covers the app while the scene is inactive, so the system's app-switcher \
            snapshot does not contain app content.

            The snapshot's PIXELS cannot be verified on Simulator — the system writes them in a \
            proprietary format neither ImageMagick nor ffmpeg can decode. That check requires a \
            physical device.
            """
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0

        stateLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        stateLabel.numberOfLines = 0
        stateLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [title, note, stateLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    // MARK: - Probe

    private var hasRun = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, !hasRun else { return }
        hasRun = true

        let log = DemoLog.shared
        log.log("=== ScreenGuardDemo app-switcher probe \(runID) ===")
        log.log("METHOD environment device=\(UIDevice.current.model) system=\(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion) package=ScreenGuard \(ScreenGuard.version)")
        log.log("METHOD snapshot PIXELS are not decodable on Simulator (docs/TOOLING.md §4); this "
            + "probe measures cover INSTALLATION and SYNCHRONY only.")

        shield.install(on: window)
        log.log("INSTALL isInstalled=\(shield.isInstalled) covering=\(isCovering)")

        // Observe the same notifications the shield does, on the same queue, so the ordering
        // between the two handlers is the thing being measured. A probe handler registered AFTER
        // the shield's handler sees the post-cover state if the cover is synchronous.
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIScene.willDeactivateNotification, object: window.windowScene, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.wasCoveringAtDeactivate = self.isCovering
                self.record("UIScene.willDeactivate")
            }
        }
        center.addObserver(
            forName: UIScene.didActivateNotification, object: window.windowScene, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("UIScene.didActivate") }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("UIApplication.didEnterBackground") }
        }
        center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("UIApplication.willEnterForeground") }
        }

        // Re-write the artifact periodically: the interesting transitions happen after the host
        // backgrounds the app, which is long after launch.
        for delay in stride(from: 3.0, through: 27.0, by: 3.0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.writeArtifacts(final: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            self?.writeArtifacts(final: true)
        }
    }

    /// Whether the shield is currently showing its cover.
    private var isCovering: Bool { !shield.isHidden && shield.alpha > 0 }

    /// Records one lifecycle transition.
    private func record(_ name: String) {
        let transition = Transition(
            name: name,
            at: CACurrentMediaTime() - startedAt,
            isCovering: isCovering,
            isHidden: shield.isHidden,
            alpha: shield.alpha
        )
        transitions.append(transition)
        DemoLog.shared.log("LIFECYCLE \(name) t=\(String(format: "%.3f", transition.at))s "
            + "covering=\(transition.isCovering) isHidden=\(transition.isHidden) "
            + "alpha=\(String(format: "%.2f", transition.alpha))")
        render()
        // PERSIST IMMEDIATELY, before returning from the notification handler.
        //
        // The periodic writes further down are NOT enough. Verified on this Simulator: after
        // `UIScene.willDeactivateNotification` the app is suspended within ~0.7 s
        // (`UIApplication.didEnterBackground` at t=4.885 s, one second after willDeactivate at
        // t=4.210 s), so the next timer write never runs and the artifact the host script collects
        // is a stale snapshot from before the app was backgrounded. That produced a false
        // "no UIScene.willDeactivate was observed" failure even though the transition had happened
        // and the cover was already engaged. Writing here is what makes the observation durable;
        // the file is a couple of kilobytes, so the synchronous write is not a concern.
        writeArtifacts(final: false)
    }

    private func render() {
        stateLabel.text = [
            "isInstalled=\(shield.isInstalled)",
            "covering=\(isCovering)",
            "wasCoveringAtDeactivate=\(wasCoveringAtDeactivate)",
            "transitions=\(transitions.count)",
        ].joined(separator: "\n")
    }

    /// Writes the machine-readable summary.
    ///
    /// - Parameter final: Whether this is the last write of the run.
    private func writeArtifacts(final: Bool) {
        render()
        let log = DemoLog.shared
        let suffix = final ? "-final" : ""

        let object: [String: Any] = [
            "runID": runID,
            "packageVersion": ScreenGuard.version,
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "isInstalled": shield.isInstalled,
            "isCovering": isCovering,
            "wasCoveringAtDeactivate": wasCoveringAtDeactivate,
            "snapshotPixelsVerifiableOnSimulator": false,
            "transitions": transitions.map { transition in
                [
                    "name": transition.name,
                    "atSeconds": transition.at,
                    "isCovering": transition.isCovering,
                    "isHidden": transition.isHidden,
                    "alpha": Double(transition.alpha),
                ] as [String: Any]
            },
        ]
        log.writeJSON(object, named: "appswitcher-\(runID)\(suffix).json")
        log.writeLog(named: "appswitcher-\(runID)\(suffix).log")
    }
}
