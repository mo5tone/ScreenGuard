//
//  DemoDetectionProbeView.swift
//  ScreenGuardDemo
//
//  Capability 1 and 2 — detection. Starts `ScreenGuardMonitor` and records exactly what it observes.
//
//  WHAT IS AND IS NOT CHECKABLE ON SIMULATOR
//  -----------------------------------------
//  * **Capture-state detection** is partly checkable here: on iOS 17+ the monitor registers for
//    `UITraitSceneCaptureState` and the registration delivers an initial value, so the probe can
//    assert that a concrete state arrived through the real signal rather than defaulting.
//  * **A real screenshot event is NOT checkable on Simulator.** An iOS screenshot is side button +
//    volume-up; sim-use exposes no volume button and there is no key-combo path, so
//    `UIApplication.userDidTakeScreenshotNotification` cannot be fired by the system
//    (`docs/TOOLING.md` §2). The script must report that as device-required.
//  * **Observer wiring IS checkable**, and this probe checks it with a deliberately synthetic post of
//    the notification. That proves the observer is registered, on the right queue, and reaches the
//    delegate — a real class of bug. It does **not** prove iOS posts that notification after a real
//    screenshot, and the log says so in as many words. The script labels the check
//    `WIRING-ONLY (synthetic)` and never reports it as a detection pass.
//

import UIKit
import ScreenGuard

/// Runs the detection probe.
@MainActor
final class DemoDetectionProbeView: UIView, ScreenGuardDelegate {

    private let runID: String
    private let monitor: ScreenGuardMonitor
    private let stateLabel = UILabel()
    private let logLabel = UILabel()

    /// Every event the monitor delivered, in order.
    private var events: [ScreenGuardEvent] = []

    /// Creates the probe.
    ///
    /// - Parameter runID: The host script's run identifier.
    init(runID: String) {
        self.runID = runID
        self.monitor = ScreenGuardMonitor()
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        build()
        monitor.delegate = self
        monitor.onEvent = { [weak self] event in
            self?.events.append(event)
            self?.render()
        }
    }

    /// Unavailable. Use `init(runID:)`.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DemoDetectionProbeView must be created programmatically") }

    // MARK: - Layout

    private func build() {
        stateLabel.font = .monospacedSystemFont(ofSize: 14, weight: .bold)
        stateLabel.numberOfLines = 0

        logLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logLabel.numberOfLines = 0
        logLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [stateLabel, logLabel])
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

    /// Renders the live state.
    ///
    /// Every enum is rendered through `.rawValue`. Bare interpolation of a non-`String` in a
    /// `LocalizedStringKey` is a deprecation error at an iOS 15 deployment target
    /// (`docs/api-contract.md` §6.9) — the same rule applies to the SwiftUI screens in this demo.
    private func render() {
        let state = monitor.state
        stateLabel.text = [
            "isMonitoring=\(state.isMonitoring ? "ON" : "OFF")",
            "captureState=\(state.captureState.rawValue)",
            "detectionSource=\(state.detectionSource?.rawValue ?? "none")",
            "lastScreenshotAt=\(state.lastScreenshotAt.map { Self.formatter.string(from: $0) } ?? "none")",
            "events=\(events.count)",
        ].joined(separator: "\n")

        logLabel.text = events.suffix(12).map { event in
            "\(Self.formatter.string(from: event.timestamp)) \(Self.describe(event.kind)) "
                + "state=\(event.captureState.rawValue) src=\(event.detectionSource.rawValue)"
        }.joined(separator: "\n")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func describe(_ kind: ScreenGuardEvent.Kind) -> String {
        switch kind {
        case .screenshotTaken:                     return "screenshotTaken"
        case .captureBegan:                        return "captureBegan"
        case .captureEnded:                        return "captureEnded"
        case .protectionDegraded(let reason):      return "protectionDegraded(\(reason.rawValue))"
        }
    }

    // MARK: - Delegate

    func screenGuard(_ monitor: ScreenGuardMonitor, didDetect event: ScreenGuardEvent) {
        // The delegate seam is the second delivery path; it is recorded separately so a broken
        // delegate wiring cannot hide behind a working closure.
        DemoLog.shared.log("DELEGATE event kind=\(Self.describe(event.kind)) "
            + "state=\(event.captureState.rawValue) source=\(event.detectionSource.rawValue)")
    }

    // MARK: - Probe

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasRun else { return }
        hasRun = true

        let log = DemoLog.shared
        log.log("=== ScreenGuardDemo detection probe \(runID) ===")
        log.log("METHOD environment device=\(UIDevice.current.model) system=\(UIDevice.current.systemName) "
            + "\(UIDevice.current.systemVersion) package=ScreenGuard \(ScreenGuard.version)")
        log.log("METHOD monitor configuration: screenshotDetection="
            + "\(monitor.configuration.isScreenshotDetectionEnabled) captureStateDetection="
            + "\(monitor.configuration.isCaptureStateDetectionEnabled) appSwitcherShield="
            + "\(monitor.configuration.isAppSwitcherShieldEnabled) noLeakStrategy="
            + "\(monitor.configuration.noLeakStrategy.rawValue)")

        monitor.start()
        log.log("START isMonitoring=\(monitor.isMonitoring)")

        // Let the trait registration deliver its initial value.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.recordInitialState()
        }
        // Deliberately synthetic. See this file's header: this is a WIRING check, not a detection
        // check, and both the log and the script label it that way.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.postSyntheticScreenshot()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.finish()
        }
    }

    private var hasRun = false

    /// The state recorded BEFORE the synthetic screenshot post, so the capture-state signal can be
    /// graded independently of it.
    ///
    /// This exists because the synthetic post overwrites the monitor's `detectionSource` with
    /// `screenshotNotification`. Reading the source only at the end would let the wiring check's own
    /// side effect stand in for "a capture-state signal arrived", which is a different claim and is
    /// exactly the kind of accidental pass this verification must not produce.
    private var initialState: (state: ScreenGuardCaptureState, source: String)?

    private func recordInitialState() {
        render()
        let state = monitor.state
        let source = state.detectionSource?.rawValue
        initialState = (state.captureState, source ?? "none")
        DemoLog.shared.log("STATE initial isMonitoring=\(state.isMonitoring) "
            + "captureState=\(state.captureState.rawValue) "
            + "detectionSource=\(source ?? "none") "
            + "events=\(events.count)")
    }

    /// Posts the screenshot notification by hand.
    ///
    /// This is the ONLY way to exercise the observer chain without a physical device, and it is
    /// explicitly NOT a screenshot. Both the log line and the script's verdict say so.
    private func postSyntheticScreenshot() {
        let log = DemoLog.shared
        log.log("SYNTHETIC-POST begin — posting UIApplication.userDidTakeScreenshotNotification "
            + "by hand. This validates the OBSERVER WIRING only. It is NOT a screenshot and it does "
            + "NOT validate that iOS posts this notification after a real one (docs/TOOLING.md §2).")
        NotificationCenter.default.post(
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            log.log("SYNTHETIC-POST after events=\(self.events.count) "
                + "lastScreenshotAt=\(self.monitor.state.lastScreenshotAt != nil ? "set" : "nil")")
        }
    }

    private func finish() {
        let log = DemoLog.shared
        let state = monitor.state
        log.log("STATE final isMonitoring=\(state.isMonitoring) "
            + "captureState=\(state.captureState.rawValue) "
            + "detectionSource=\(state.detectionSource?.rawValue ?? "none") "
            + "events=\(events.count)")
        for event in events {
            log.log("EVENT \(Self.describe(event.kind)) state=\(event.captureState.rawValue) "
                + "source=\(event.detectionSource.rawValue) at="
                + "\(Self.formatter.string(from: event.timestamp))")
        }

        let object: [String: Any] = [
            "runID": runID,
            "packageVersion": ScreenGuard.version,
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "isMonitoring": state.isMonitoring,
            "captureState": state.captureState.rawValue,
            "detectionSource": state.detectionSource?.rawValue ?? NSNull(),
            // Graded in preference to the two keys above: they are read at `finish()`, which runs
            // AFTER the synthetic screenshot post, so they describe the synthetic event rather than
            // the capture-state signal. See `initialState`.
            "initialCaptureState": initialState.map { $0.state.rawValue } ?? NSNull(),
            "initialDetectionSource": initialState.map { $0.source } ?? NSNull(),
            "lastScreenshotAt": state.lastScreenshotAt.map { ISO8601DateFormatter().string(from: $0) }
                ?? NSNull(),
            "syntheticScreenshotPostPerformed": true,
            "syntheticPostIsARealScreenshot": false,
            "events": events.map { event in
                [
                    "kind": Self.describe(event.kind),
                    "captureState": event.captureState.rawValue,
                    "detectionSource": event.detectionSource.rawValue,
                    "timestamp": ISO8601DateFormatter().string(from: event.timestamp),
                ] as [String: Any]
            },
        ]
        log.writeJSON(object, named: "detection-\(runID).json")
        log.writeLog(named: "detection-\(runID).log")
        log.log("WROTE detection-\(runID).log")
    }
}
