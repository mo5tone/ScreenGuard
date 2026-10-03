//
//  ScreenGuardShieldMode.swift
//  ScreenGuard
//
//  What the shield is actually doing, as opposed to what it was asked to do.
//  Split out of ScreenGuardShieldView.swift to keep that file inside the size limit. The type is
//  unchanged and still public.
//

// MARK: - Shield mode

/// What the shield is actually doing, as opposed to what it was asked to do.
///
/// This exists so a degraded shield is **clearly labelled** rather than silently shipping a broken
/// guarantee. A host app can render this value directly; it is `String`-backed for that reason.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardShieldMode: String, Equatable, Sendable {
    /// No protection. Content is shown normally. Layout and debugging only.
    case disabled

    /// Public path engaged: content is rasterised into an `AVSampleBufferDisplayLayer` with
    /// `preventsCapture = true`, over an opaque shield.
    ///
    /// ⚠️ **DEVICE-PENDING.** On Simulator the layer paints nothing at all, so protected regions
    /// appear empty on screen. Fail-closed, not a leak. Requires device validation.
    case publicPreventsCaptureLayer

    /// Private path engaged: the content's layer was reparented into a private secure-canvas
    /// descendant of a hidden secure text field (the class name is not contract and lives only in
    /// `Shield/ScreenGuardPrivateSecureLayer.swift`).
    ///
    /// ⚠️ PRIVATE API. Non-contract. Fragile across iOS releases. App Review risk. Never a security
    /// guarantee.
    case privateSecureLayer

    /// **FALLBACK — NOT A NO-LEAK CONTROL.** The requested mechanism could not be engaged, so the
    /// shield shows the protected content as a plain visual overlay. It removes **no pixels** from
    /// any capture, screenshot or recording, and it protects nothing. The host app should treat this
    /// as "detection only": use `ScreenGuardMonitor` to learn that a capture happened, and treat the
    /// content as unprotected.
    case detectionAndOverlayFallback
}
