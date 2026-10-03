//
//  ScreenGuardEventMapper.swift
//  ScreenGuard
//
//  Pure transition logic: capture state in, event kind out.
//
//  Deliberately separated from the observers so it is unit-testable with no window, no simulator
//  capture, and no timing. This is the "event-type mapping from capture state" surface required by
//  the package's acceptance criteria.
//

import Foundation

/// Maps capture-state transitions to `ScreenGuardEvent.Kind` values, and normalises raw platform
/// signals into `ScreenGuardCaptureState`.
///
/// Pure value logic — no UIKit, no observers, no timing. Every method is deterministic.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardEventMapper {

    /// The event kind implied by a state transition, or `nil` when nothing should be emitted.
    ///
    /// Rules:
    /// - anything → `.active` emits `.captureBegan`.
    /// - `.active` → `.inactive` emits `.captureEnded` — capture genuinely ended.
    /// - `.unspecified` → `.inactive` and `.inactive` → `.unspecified` emit **nothing**: "unknown" and
    ///   "known not capturing" are both non-capture states, and the first real observation of "not
    ///   capturing" is not an event. A platform that cannot determine the state must not be reported
    ///   as "capture ended".
    /// - `.active` → `.unspecified` emits **nothing**, deliberately. The platform losing the ability to
    ///   determine the state is not evidence that capture stopped; claiming `.captureEnded` there would
    ///   be a fabrication.
    /// - a same-state transition emits nothing (idempotent: repeated signals do not spam the host).
    ///
    /// - Parameters:
    ///   - previous: The state the observer held before this signal.
    ///   - current: The state the observer now holds.
    /// - Returns: The event kind to emit, or `nil` when the transition is not reportable.
    public static func eventKind(
        from previous: ScreenGuardCaptureState,
        to current: ScreenGuardCaptureState
    ) -> ScreenGuardEvent.Kind? {
        guard previous != current else { return nil }

        switch (previous, current) {
        case (_, .active):
            // Capture began (recording, mirroring or AirPlay — indistinguishable, §3.1.1).
            return .captureBegan
        case (.active, .inactive):
            // Capture genuinely ended.
            return .captureEnded
        case (.unspecified, .inactive),
             (.inactive, .unspecified),
             (.active, .unspecified):
            // Never claim an end we cannot substantiate.
            return nil
        case (.unspecified, .unspecified),
             (.inactive, .inactive):
            // Unreachable (guarded above) but listed so the switch is exhaustive without a `default`,
            // which would silently absorb a future case.
            return nil
        }
    }

    /// Normalises the iOS 17+ `UISceneCaptureState` raw value into `ScreenGuardCaptureState`.
    ///
    /// Takes the raw `Int` value rather than the platform enum so this stays callable (and testable)
    /// at an iOS 15 deployment target without an availability guard. `UISceneCaptureState`'s cases
    /// are `unspecified = 0`, `inactive = 1`, `active = 2`; any future value degrades to
    /// `.unspecified` instead of crashing or being misread as "active".
    ///
    /// - Parameter sceneCaptureStateRawValue: The raw value of a `UISceneCaptureState`.
    /// - Returns: The equivalent `ScreenGuardCaptureState`.
    public static func captureState(sceneCaptureStateRawValue: Int) -> ScreenGuardCaptureState {
        switch sceneCaptureStateRawValue {
        case 1: return .inactive
        case 2: return .active
        default: return .unspecified
        }
    }

    /// Normalises the iOS 15/16 `UIScreen.isCaptured` boolean into `ScreenGuardCaptureState`.
    ///
    /// The legacy signal is a coarse boolean with no "unknown" case, so `false` maps to `.inactive`
    /// (a known, non-captured state), never to `.unspecified`.
    ///
    /// - Parameter isCaptured: The value of `UIScreen.isCaptured`.
    /// - Returns: `.active` when captured, `.inactive` otherwise.
    public static func captureState(isCaptured: Bool) -> ScreenGuardCaptureState {
        isCaptured ? .active : .inactive
    }
}
