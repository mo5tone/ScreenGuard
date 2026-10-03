//
//  ScreenGuardDelegate.swift
//  ScreenGuard
//
//  The callback seam. See docs/api-contract.md §6.2 and §6.3.
//

import Foundation

/// The callback seam. A host app forwards these events to its own risk engine.
///
/// The package contains **no networking of any kind** (docs/api-contract.md §6.3). Forwarding an
/// event to a risk engine is the host app's job, and this protocol — plus
/// `ScreenGuardMonitor.onEvent` — is the only seam for it.
///
/// Called on the main actor. The monitor holds its delegate **weakly**, so a delegate must be
/// retained by the host.
///
/// iOS 15-compatible — no availability guard is required.
@MainActor
public protocol ScreenGuardDelegate: AnyObject {
    /// Called for every detection event.
    ///
    /// - Parameters:
    ///   - monitor: The monitor that observed the event.
    ///   - event: What was detected.
    func screenGuard(_ monitor: ScreenGuardMonitor, didDetect event: ScreenGuardEvent)
}
