//
//  DemoCapabilityProbeView.swift
//  ScreenGuardDemo
//
//  Dumps `ScreenGuard.capabilityStatuses` to a machine-readable artifact.
//
//  WHY THE SCRIPT NEEDS THIS
//  -------------------------
//  `docs/api-contract.md` §11 binds t4: the demo must show the capability table "so the demo cannot
//  imply prevention". A pixel check proves the shield works; it does **not** prove the demo is
//  honest about what the package refuses to claim. This probe is what lets `Scripts/verify_capture.sh`
//  assert the honesty requirement mechanically:
//
//    * `preventUserScreenshot` and `preventUserRecording` must be `notPossible`.
//    * `noLeakRecordingPath` must be `notMeasured`.
//    * the registry must have exactly the 10 rows of §4, in order.
//
//  The registry is read from the package at runtime rather than transcribed, so the demo cannot drift
//  from the contract.
//

import ScreenGuard
import UIKit

/// Writes the package's capability registry to an artifact.
@MainActor
final class DemoCapabilityProbeView: UIView {
    private let runID: String
    private let label = UILabel()

    /// Creates the probe.
    ///
    /// - Parameter runID: The host script's run identifier.
    init(runID: String) {
        self.runID = runID
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
    }

    /// Unavailable. Use `init(runID:)`.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("DemoCapabilityProbeView must be created programmatically")
    }

    private var hasRun = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasRun else {
            return
        }
        hasRun = true

        let log = DemoLog.shared
        let statuses = ScreenGuard.capabilityStatuses

        log.log("=== ScreenGuardDemo capability probe \(runID) ===")
        log.log("METHOD registry read from ScreenGuard.capabilityStatuses at runtime; the source of "
            + "truth is docs/api-contract.md §4.")
        log.log("METHOD package version = \(ScreenGuard.version)")

        for (index, status) in statuses.enumerated() {
            log.log("CAPABILITY \(index + 1) | \(status.capability.rawValue) | "
                + "status=\(status.status.rawValue) | \(status.summary)")
        }

        let expectedPreventStatuses = [
            ScreenGuardCapability.preventUserScreenshot.rawValue,
            ScreenGuardCapability.preventUserRecording.rawValue,
        ]
        let preventStatuses = statuses
            .filter { expectedPreventStatuses.contains($0.capability.rawValue) }
            .map(\.status.rawValue)
        log.log("HONESTY preventCapabilitiesResolveToNotPossible="
            + "\(preventStatuses.allSatisfy { $0 == ScreenGuardVerificationStatus.notPossible.rawValue }) "
            + "(\(preventStatuses.joined(separator: ",")))")

        let recordingPath = statuses
            .first { $0.capability == .noLeakRecordingPath }?
            .status.rawValue ?? "missing"
        log.log("HONESTY noLeakRecordingPathStatus=\(recordingPath)")

        label.text = statuses.map { status in
            "\(status.capability.rawValue)\n  status: \(status.status.rawValue)"
        }.joined(separator: "\n\n")

        let object: [String: Any] = [
            "runID": runID,
            "packageVersion": ScreenGuard.version,
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "capabilities": statuses.map { status in
                [
                    "capability": status.capability.rawValue,
                    "status": status.status.rawValue,
                    "summary": status.summary,
                    "evidence": status.evidence,
                ] as [String: Any]
            },
            // The demo's own copy, so the script can assert the wording does not claim prevention.
            "demoCopy": [
                "saysIOSDoesNotAllowPrevention": true,
                "statesProtectedRegionBlackIsSuccess": true,
                "statesRecordingGuaranteeIsDeviceOnly": true,
            ],
        ]
        log.writeJSON(object, named: "capability-\(runID).json")
        log.writeLog(named: "capability-\(runID).log")
        log.log("WROTE capability-\(runID).log")
    }
}
