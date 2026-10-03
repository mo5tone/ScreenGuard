//
//  ScreenGuard.swift
//  ScreenGuard
//
//  Namespace, version, and the capability registry that backs the package's public claims.
//
//  The registry is the single source of truth for what the package promises. It mirrors the
//  quotable capability table in `docs/api-contract.md` §4 exactly, in the same order — a unit test
//  asserts the mapping, including that the entry count equals the number of §4 rows, so the code
//  cannot drift from the contract.
//

import Foundation

/// The ScreenGuard namespace: package version and the capability registry.
///
/// `ScreenGuard` is an uninstantiable namespace. Use `ScreenGuard.start()` for the shared monitor,
/// or build your own `ScreenGuardMonitor`.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuard {
    // MARK: - Version

    /// Semantic version of the package.
    public static let version: String = "1.0.0"

    // MARK: - Capability registry

    /// Every capability the package models, with its honest status. Backs the README's claim table.
    ///
    /// Returns exactly the rows of `docs/api-contract.md` §4, with the same statuses, in the same
    /// order. Order is normative: `ScreenGuardCapability` is `CaseIterable`, and the array is built
    /// by mapping `allCases`, so the two can never disagree.
    public static var capabilityStatuses: [ScreenGuardCapabilityStatus] {
        ScreenGuardCapability.allCases.map(statusRecord(for:))
    }

    /// Convenience lookup.
    ///
    /// - Parameter capability: The capability to look up.
    /// - Returns: The honest verification status of `capability`.
    public static func status(of capability: ScreenGuardCapability) -> ScreenGuardVerificationStatus {
        statusRecord(for: capability).status
    }

    /// The full record (status + one-line guarantee + evidence citation) for a capability.
    ///
    /// - Parameter capability: The capability to describe.
    /// - Returns: The record for `capability`.
    public static func capabilityStatus(for capability: ScreenGuardCapability) -> ScreenGuardCapabilityStatus {
        statusRecord(for: capability)
    }

    // MARK: - The §4 table, in code

    /// The §4 rows, one case per row, in table order. See `docs/api-contract.md` §4.
    ///
    /// Each row is built by its own private helper purely so no single body exceeds the 50-line limit;
    /// this dispatcher is exhaustive, with no default. Every string is verbatim from the previous
    /// single-switch version.
    private static func statusRecord(for capability: ScreenGuardCapability) -> ScreenGuardCapabilityStatus {
        switch capability {
        case .screenshotDetection:
            screenshotDetectionRecord()

        case .captureStateDetection:
            captureStateDetectionRecord()

        case .noLeakSecureTextEntry:
            noLeakSecureTextEntryRecord()

        case .noLeakPublicPreventsCapture:
            noLeakPublicPreventsCaptureRecord()

        case .noLeakPrivateSecureLayer:
            noLeakPrivateSecureLayerRecord()

        case .noLeakRecordingPath:
            noLeakRecordingPathRecord()

        case .watermark:
            watermarkRecord()

        case .appSwitcherSnapshotProtection:
            appSwitcherSnapshotProtectionRecord()

        case .preventUserScreenshot:
            preventUserScreenshotRecord()

        case .preventUserRecording:
            preventUserRecordingRecord()
        }
    }

    /// The §4 row for .screenshotDetection. See `docs/api-contract.md` §4.
    private static func screenshotDetectionRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .screenshotDetection,
            status: .devicePending,
            summary: "Tells you a screenshot was taken, after it was taken. The API is public and "
                + "long-stable, but the event was never observed end-to-end — the Simulator "
                + "cannot fire it.",
            evidence: "capability-matrix.md §7; docs/TOOLING.md §2 (no volume button on the "
                + "Simulator, so userDidTakeScreenshotNotification cannot be triggered)."
        )
    }

    /// The §4 row for .captureStateDetection. See `docs/api-contract.md` §4.
    private static func captureStateDetectionRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .captureStateDetection,
            status: .devicePending,
            summary: "Tells you the screen is being captured, and when that changes. Does not say "
                + "which kind.",
            evidence: "capability-matrix.md §7: RPScreenRecorder started, then UIScreen.main"
                + ".isCaptured stayed false with 0 capturedDidChangeNotification callbacks."
        )
    }

    /// The §4 row for .noLeakSecureTextEntry. See `docs/api-contract.md` §4.
    private static func noLeakSecureTextEntryRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .noLeakSecureTextEntry,
            status: .measured,
            summary: "The field's text is blanked in captures (user sees dots). Text-field content "
                + "only.",
            evidence: "capability-matrix.md §3 row 5: TEXT-BLANKED 0/1068 dark pixels in "
                + "drawHierarchy while the same field's dots are visible on the display "
                + "(19.02% dark); row 7 calibration band proves the path can image text "
                + "(205/1068)."
        )
    }

    /// The §4 row for .noLeakPublicPreventsCapture. See `docs/api-contract.md` §4.
    private static func noLeakPublicPreventsCaptureRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .noLeakPublicPreventsCapture,
            status: .devicePending,
            summary: "Designed to blank arbitrary content in captures. On Simulator the layer "
                + "paints nothing at all, so this is unverified — requires a device.",
            evidence: "capability-matrix.md §4: preventsCapture=true shows the sentinel on the "
                + "bypass host display for both set-before-add and set-after-add, while "
                + "preventsCapture=false paints correctly — so row 8's NO-LEAK(black) is "
                + "unearned."
        )
    }

    /// The §4 row for .noLeakPrivateSecureLayer. See `docs/api-contract.md` §4.
    private static func noLeakPrivateSecureLayerRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .noLeakPrivateSecureLayer,
            status: .measured,
            summary: "Blanks arbitrary content in captures. Non-contract, fragile, App Review "
                + "risk. Never a security guarantee. Opt-in, off by default.",
            evidence: "capability-matrix.md §3 row 4 and row 6: sentinel (200,0,160) in "
                + "drawHierarchy while the host display capture reads the real colour "
                + "(38,102,242); the swap-disabled control band leaks on both paths."
        )
    }

    /// The §4 row for .noLeakRecordingPath. See `docs/api-contract.md` §4.
    private static func noLeakRecordingPathRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .noLeakRecordingPath,
            status: .notMeasured,
            summary: "None claimed. RPScreenRecorder.startCapture reported success then delivered "
                + "0 callbacks in 30 s.",
            evidence: "capability-matrix.md §7: video=0 audioApp=0 audioMic=0 over 30 s; "
                + "startRecording reported isRecording=true with no frames."
        )
    }

    /// The §4 row for .watermark. See `docs/api-contract.md` §4.
    private static func watermarkRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .watermark,
            status: .notMeasured,
            summary: "Makes a leak attributable. Removes no pixels. Deterrent/forensic only — not "
                + "a security control.",
            evidence: "No forensic-efficacy measurement exists. Tile geometry is deterministic and "
                + "unit-tested; efficacy is not claimed."
        )
    }

    /// The §4 row for .appSwitcherSnapshotProtection. See `docs/api-contract.md` §4.
    private static func appSwitcherSnapshotProtectionRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .appSwitcherSnapshotProtection,
            status: .devicePending,
            summary: "Covers content before the system snapshots it. Snapshot pixels are not "
                + "decodable on Simulator.",
            evidence: "docs/TOOLING.md §4: SplashBoard snapshots are Apple's proprietary "
                + "AAPL-magic KTX variant; neither ImageMagick nor ffmpeg can decode them."
        )
    }

    /// The §4 row for .preventUserScreenshot. See `docs/api-contract.md` §4.
    private static func preventUserScreenshotRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .preventUserScreenshot,
            status: .notPossible,
            summary: "iOS does not permit an app to block a screenshot.",
            evidence: "docs/api-contract.md §0.2: no public API exists; the app is told afterwards "
                + "via userDidTakeScreenshotNotification (post hoc)."
        )
    }

    /// The §4 row for .preventUserRecording. See `docs/api-contract.md` §4.
    private static func preventUserRecordingRecord() -> ScreenGuardCapabilityStatus {
        ScreenGuardCapabilityStatus(
            capability: .preventUserRecording,
            status: .notPossible,
            summary: "iOS does not permit an app to block a recording.",
            evidence: "docs/api-contract.md §0.2: a recording is started by the user or by "
                + "ReplayKit; an app cannot veto it."
        )
    }
}

// MARK: - Shared monitor

public extension ScreenGuard {
    /// Process-wide monitor using the default configuration.
    ///
    /// Created lazily on first access. Prefer `ScreenGuard.start(delegate:)` when you want the
    /// monitor running immediately.
    @MainActor static let shared: ScreenGuardMonitor = .init()

    /// Starts the shared monitor, optionally installing a delegate, and returns it.
    ///
    /// Idempotent — calling it twice returns the same monitor and does not double-register
    /// observers.
    ///
    /// - Parameter delegate: An optional delegate to receive detection events. Held weakly.
    /// - Returns: The shared monitor.
    @MainActor
    @discardableResult
    static func start(delegate: ScreenGuardDelegate? = nil) -> ScreenGuardMonitor {
        let monitor = shared
        if let delegate {
            monitor.delegate = delegate
        }
        monitor.start()
        return monitor
    }

    /// Stops the shared monitor and removes every observer it installed.
    @MainActor
    static func stop() {
        shared.stop()
    }
}
