//
//  ScreenGuardEvent.swift
//  ScreenGuard
//
//  The unified detection event, the capture state it reports, and the seam that delivers it.
//  See docs/api-contract.md §6.2.
//
//  Every detection seam in the package delivers exactly `ScreenGuardEvent`. A host app forwards it
//  to its own risk engine through `ScreenGuardDelegate` or `ScreenGuardMonitor.onEvent` — the
//  package itself contains no networking of any kind (docs/api-contract.md §6.3).
//

import Foundation

// MARK: - Capture state

/// Whether the scene is being captured. Mirrors `UISceneCaptureState` on iOS 17+ and the
/// `UIScreen.isCaptured` boolean on iOS 15/16.
///
/// Raw-valued and `String`-backed **on purpose**: a consumer displaying live capture state writes
/// `Text(state.rawValue)`. Bare interpolation of a non-`String` value into `Text` is a deprecation
/// error at an iOS 15 deployment target (docs/api-contract.md §6.9).
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardCaptureState: String, Equatable, Sendable {

    /// The platform could not determine the state (iOS 17+ `.unspecified`; legacy `false`).
    case unspecified

    /// Not being captured.
    case inactive

    /// Being captured.
    ///
    /// NOTE: this covers recording, mirroring and AirPlay alike — the platform does not distinguish
    /// them. See `docs/api-contract.md` §3.1.1.
    case active
}

// MARK: - Detection source

/// Which signal produced an event. Lets a host app reason about confidence and OS coverage.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardDetectionSource: String, Equatable, Sendable {

    /// `UITraitCollection.sceneCaptureState` — iOS 17.0 and later only.
    case sceneCaptureState

    /// `UIScreen.isCaptured` / `UIScreen.capturedDidChangeNotification` — iOS 15/16 path.
    case screenIsCaptured

    /// `UIApplication.userDidTakeScreenshotNotification`.
    case screenshotNotification
}

// MARK: - Protection failure

/// A reason the no-leak shield could not engage. Reported so protection never fails silently.
///
/// Raw-valued and `String`-backed, matching `ScreenGuardCaptureState` and
/// `ScreenGuardDetectionSource`, so a consumer can display it with `Text(reason.rawValue)`. Bare
/// interpolation of a non-`String` value into `Text` is a deprecation error at an iOS 15 deployment
/// target (docs/api-contract.md §6.9).
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardProtectionFailure: String, Equatable, Sendable {

    /// The private secure-layer canvas class was not found on this OS build, the private-API code is
    /// not compiled in, or the runtime opt-in was not granted. The shield is **not** protecting.
    /// See `docs/api-contract.md` §9.
    case privateSecureLayerUnavailable

    /// The private layer swap was attempted and the layer arrangement could not be left intact, so
    /// the host must not be told the swap took effect.
    case privateSecureLayerSwapFailed

    /// The public `AVSampleBufferDisplayLayer` could not be engaged, or no frame could be pushed into
    /// it, so a protected region may be empty for the wrong reason.
    ///
    /// Mechanism-correct on purpose: the public path has nothing to do with the private canvas, and
    /// reporting a private-API reason here would tell a risk engine that the wrong mechanism failed.
    case publicPreventsCaptureLayerUnavailable

    /// The app-switcher cover could not be installed or engaged, because there was no window/scene to
    /// cover. Reported rather than silently doing nothing, so a host is never left believing the
    /// snapshot is covered when nothing was installed.
    case appSwitcherCoverUnavailable
}

// MARK: - Event

/// The single unified detection event. Every detection seam delivers exactly this type.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardEvent: Equatable, Sendable {

    /// What happened.
    public enum Kind: Equatable, Sendable {

        /// A screenshot was taken. Delivered **after** the fact — the image already exists.
        case screenshotTaken

        /// Capture began (recording, mirroring or AirPlay).
        case captureBegan

        /// Capture ended.
        case captureEnded

        /// A protection mechanism failed to engage. Emitted so the host can react.
        case protectionDegraded(reason: ScreenGuardProtectionFailure)
    }

    /// What happened.
    public let kind: Kind

    /// The capture state at the moment of the event.
    public let captureState: ScreenGuardCaptureState

    /// Which signal produced this event.
    public let detectionSource: ScreenGuardDetectionSource

    /// When the event was created.
    public let timestamp: Date

    /// Creates a detection event.
    ///
    /// - Parameters:
    ///   - kind: What happened.
    ///   - captureState: The capture state at the moment of the event.
    ///   - detectionSource: Which signal produced the event.
    ///   - timestamp: When the event was created. Defaults to now.
    public init(
        kind: Kind,
        captureState: ScreenGuardCaptureState,
        detectionSource: ScreenGuardDetectionSource,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.captureState = captureState
        self.detectionSource = detectionSource
        self.timestamp = timestamp
    }
}

// MARK: - State snapshot

/// A snapshot of the monitor's current knowledge.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardState: Equatable, Sendable {

    /// The most recently observed capture state.
    public var captureState: ScreenGuardCaptureState

    /// The signal that produced the most recent state; `nil` until the first detection.
    public var detectionSource: ScreenGuardDetectionSource?

    /// When the most recent screenshot was detected, if any.
    public var lastScreenshotAt: Date?

    /// Whether the monitor is currently observing.
    public var isMonitoring: Bool

    /// Creates a state snapshot. Defaults describe a stopped, never-detected monitor.
    ///
    /// - Parameters:
    ///   - captureState: The most recently observed capture state. Default `.unspecified`.
    ///   - detectionSource: The signal behind the most recent state. Default `nil`.
    ///   - lastScreenshotAt: When the most recent screenshot was detected. Default `nil`.
    ///   - isMonitoring: Whether the monitor is observing. Default `false`.
    public init(
        captureState: ScreenGuardCaptureState = .unspecified,
        detectionSource: ScreenGuardDetectionSource? = nil,
        lastScreenshotAt: Date? = nil,
        isMonitoring: Bool = false
    ) {
        self.captureState = captureState
        self.detectionSource = detectionSource
        self.lastScreenshotAt = lastScreenshotAt
        self.isMonitoring = isMonitoring
    }
}
