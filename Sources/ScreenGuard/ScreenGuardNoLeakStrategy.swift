//
//  ScreenGuardNoLeakStrategy.swift
//  ScreenGuard
//
//  The no-leak mechanism selector and the refresh policy for the shield.
//  See docs/api-contract.md §6.4.
//
//  Read §3.2 and §9 of the contract before changing any wording in this file. The two strategies
//  have different statuses and different risk, and must never be described together as "the blocking
//  feature".
//

import CoreGraphics
import Foundation

/// Which mechanism protects content marked as sensitive.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardNoLeakStrategy: String, Equatable, Sendable {

    /// No protection. The shield renders content normally. For debugging and layout work only.
    case disabled

    /// DEFAULT. Renders protected content into an `AVSampleBufferDisplayLayer` with
    /// `preventsCapture = true`, over an opaque black shield.
    ///
    /// ⚠️ **DEVICE-PENDING.** On Simulator this strategy makes the layer paint **nothing at all**,
    /// including on screen — protected regions appear empty. That is a fail-closed behaviour, not a
    /// leak, and it is the expected Simulator result. See `docs/api-contract.md` §3.2.2.
    ///
    /// Public API. Does not guarantee protection of content that is not rendered into the layer.
    case publicPreventsCaptureLayer

    /// **OPT-IN, OFF BY DEFAULT.** Reparents the protected content's layer into the private secure
    /// canvas that UIKit uses to keep a secure text field out of captures. The canvas's class name is
    /// private, is not contract, and is named in exactly one file —
    /// `Shield/ScreenGuardPrivateSecureLayer.swift` — which is compiled only when the consumer enables
    /// the `PrivateAPI` package trait. Keeping the literal out of this always-compiled file is what
    /// keeps it out of a default consumer's generated `.swiftdoc` as well as its binary
    /// (`docs/api-contract.md` §9.4).
    ///
    /// ⚠️ **PRIVATE API.** Non-contract. Fragile across iOS releases. App Review risk. Read
    /// `docs/api-contract.md` §9 before enabling. **Never a security guarantee.**
    case privateSecureLayer
}

/// How often the shield re-rasterises its protected content.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardRefreshPolicy: Equatable, Sendable {

    /// Refresh only when `setNeedsContentRefresh()` is called. Cheapest. Default.
    case manual

    /// Refresh on bounds or trait changes.
    case onLayout

    /// Refresh on a timer.
    ///
    /// Measured cost on the public path: enqueue median 4.0–6.5 ms per frame, CPU 4.2–7.1 ms per
    /// frame (`docs/evidence/capability-matrix.md` §6). The measured achieved rate was 42–47 fps as
    /// a **floor**; no maximum is claimed.
    case periodic(TimeInterval)
}
