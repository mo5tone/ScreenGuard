//
//  ScreenGuardCapability.swift
//  ScreenGuard
//
//  The capability and verification-status model of docs/api-contract.md §4 and §5.
//
//  This is the honesty mechanism of the package: every capability the package models carries its
//  real status, so a host app (and the package's own example) can *render* the truth instead of
//  restating a marketing claim. `ScreenGuard.capabilityStatuses` returns exactly the rows of §4.
//
//  Status vocabulary, defined once (docs/api-contract.md §4):
//
//    measured      Demonstrated by a measurement in docs/evidence/capability-matrix.md, with a
//                  control that rules out the obvious false positive.
//    devicePending Designed and implemented, but NOT measurable on Simulator; the claim is withheld
//                  until a physical device run. Not a working guarantee today.
//    notMeasured   No measurement attempted; no claim made.
//    notPossible   The platform does not permit it.
//

import Foundation

// MARK: - Capability

/// The capabilities the package does or does not provide. One case per row of
/// `docs/api-contract.md` §4.
///
/// The enum deliberately includes the two `prevent*` cases and `noLeakRecordingPath`: the *absence*
/// of a guarantee is itself reportable, rather than being an omission a consumer cannot see.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardCapability: String, CaseIterable, Equatable, Sendable {

    /// Screenshot **detection** — `UIApplication.userDidTakeScreenshotNotification`. §4 row 1.
    case screenshotDetection

    /// Capture **detection** (recording / mirroring / AirPlay) — iOS 17+
    /// `UITraitCollection.sceneCaptureState`, iOS 15/16 `UIScreen.isCaptured`. §4 row 2.
    case captureStateDetection

    /// **No-leak** for a text field's own content — `isSecureTextEntry`. §4 row 3.
    case noLeakSecureTextEntry

    /// **No-leak** for arbitrary content on the public path —
    /// `AVSampleBufferDisplayLayer.preventsCapture` over an opaque black shield. §4 row 4.
    case noLeakPublicPreventsCapture

    /// **No-leak** for arbitrary content on the opt-in private path — secure-layer swap into the
    /// private secure canvas. The canvas's class name is not contract and is named only in
    /// `Shield/ScreenGuardPrivateSecureLayer.swift`, which the `PrivateAPI` trait gates, so it stays
    /// out of a default consumer's binary and generated `.swiftdoc` (`docs/api-contract.md` §9.4).
    /// §4 row 5.
    case noLeakPrivateSecureLayer

    /// **No-leak** on the recording/mirroring path by *any* technique. Exists so the absence of a
    /// guarantee is itself reportable. Must resolve to `.notMeasured`. §4 row 6.
    case noLeakRecordingPath

    /// Forensic **watermark** — tiled overlay. Removes no pixels. §4 row 7.
    case watermark

    /// **App-switcher snapshot** protection — scene-deactivation cover. §4 row 8.
    case appSwitcherSnapshotProtection

    /// **Prevent** a screenshot. Must resolve to `.notPossible`. §4 row 9.
    case preventUserScreenshot

    /// **Prevent** a recording. Must resolve to `.notPossible`. §4 row 10.
    case preventUserRecording
}

// MARK: - Verification status

/// How well a capability is established. See `docs/api-contract.md` §4.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardVerificationStatus: String, Equatable, Sendable {

    /// Demonstrated by measurement with a control band that rules out the obvious false positive.
    case measured

    /// Designed and implemented, but not measurable on Simulator. Requires device validation.
    /// **Not a working guarantee today.**
    case devicePending

    /// No measurement attempted; no claim made.
    case notMeasured

    /// The platform does not permit it.
    case notPossible
}

// MARK: - Capability status

/// A capability, its status, and the evidence for that status.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardCapabilityStatus: Equatable, Sendable {

    /// The capability being described.
    public let capability: ScreenGuardCapability

    /// How well the capability is established.
    public let status: ScreenGuardVerificationStatus

    /// One-line guarantee, or the reason there is none.
    public let summary: String

    /// The measurement or reasoning that earns the status; cites
    /// `docs/evidence/capability-matrix.md`.
    public let evidence: String

    /// Creates a capability-status record. Public because the type is public and a host app may
    /// build its own projections of it (e.g. a settings screen or an audit export).
    public init(
        capability: ScreenGuardCapability,
        status: ScreenGuardVerificationStatus,
        summary: String,
        evidence: String
    ) {
        self.capability = capability
        self.status = status
        self.summary = summary
        self.evidence = evidence
    }
}
