//
//  ScreenGuardScreenshotObserver.swift
//  ScreenGuard
//
//  Screenshot detection: `UIApplication.userDidTakeScreenshotNotification`.
//
//  This is detection only, and it is POST HOC: by the time the notification arrives the screenshot
//  already exists. iOS exposes no public API that blocks a screenshot, so the package never claims
//  to prevent one (docs/api-contract.md §0.2, §3.1).
//
//  End-to-end delivery is DEVICE-PENDING: the Simulator cannot fire this notification, because a
//  real screenshot is side-button + volume-up and `sim-use` exposes no volume button
//  (docs/TOOLING.md §2).
//

import UIKit

/// Observes the system's screenshot notification and republishes it.
///
/// Not public API: this is an internal engine detail. Consumers observe `ScreenGuardMonitor`.
///
/// iOS 15-compatible — `userDidTakeScreenshotNotification` is iOS 7.0+ and not deprecated.
@MainActor
final class ScreenGuardScreenshotObserver {

    /// Called on the main actor when a screenshot is detected.
    var onScreenshot: (() -> Void)?

    /// Whether the observer is currently registered.
    private(set) var isObserving = false

    /// Owns the notification token, so it is removed even if the observer is released without
    /// `stop()` — from any thread, without trapping. See `ScreenGuardObserverTokenStore`'s header.
    private let tokens = ScreenGuardObserverTokenStore()

    /// Begins observing. Idempotent.
    func start() {
        guard !isObserving else { return }
        isObserving = true
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Nonisolated closure: hop back explicitly, exactly as in the capture-state observer.
            MainActor.assumeIsolated {
                self?.onScreenshot?()
            }
        }
        tokens.add(notificationToken: token)
    }

    /// Removes the observer. Idempotent.
    func stop() {
        tokens.invalidate()
        isObserving = false
    }
}
