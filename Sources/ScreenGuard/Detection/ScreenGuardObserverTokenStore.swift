//
//  ScreenGuardObserverTokenStore.swift
//  ScreenGuard
//
//  Owns every observer token and tears them down when the store is released.
//
//  WHY THIS EXISTS — a reproduced crash
//  -----------------------------------
//  The obvious way to clean up in `deinit` is to hop back to the main actor:
//
//      deinit { MainActor.assumeIsolated { observer.stop() } }
//
//  That TRAPS (SIGABRT) whenever the last release happens off the main thread, because
//  `assumeIsolated` asserts that the current executor already is the main actor. `ScreenGuardMonitor`
//  is `@MainActor`, but that constrains where its *methods* may be called — it does not control which
//  thread the final `release` lands on. Measured: a monitor started on the main thread and released
//  from a background queue crashed the test process with exactly this pattern.
//
//  The contract requires `deinit` not to need manual cleanup (docs/api-contract.md §10), so the
//  cleanup has to happen without assuming an executor. This store is the fix:
//
//    * `NotificationCenter.removeObserver(_:)` is documented thread-safe, so notification tokens are
//      removed directly from `deinit`, on whatever thread that happens to be.
//    * Trait-registration teardown (`unregisterForTraitChanges(_:)`) is main-actor isolated, so it is
//      performed synchronously when the store is already on the main thread and dispatched to the main
//      queue otherwise. The token and the view are captured strongly by the dispatched block, so
//      nothing dangles while the hop is in flight.
//
//  This type is deliberately NOT actor-isolated, which is what makes the above possible.
//

import Foundation

/// Holds observer tokens and removes them on deallocation.
///
/// Not actor-isolated by design — see the file header. Only `invalidate()`'s trait teardown requires
/// the main thread, and it enforces that itself.
final class ScreenGuardObserverTokenStore {
    /// NotificationCenter tokens. Removal is thread-safe.
    private var notificationTokens: [NSObjectProtocol] = []

    /// Main-actor-isolated teardown work, run on deallocation.
    private var mainActorTeardown: [() -> Void] = []

    /// Registers a `NotificationCenter` token for removal on deallocation.
    ///
    /// - Parameter token: The token returned by `addObserver(forName:object:queue:using:)`.
    func add(notificationToken token: NSObjectProtocol) {
        notificationTokens.append(token)
    }

    /// Registers main-actor-isolated teardown work to run on deallocation.
    ///
    /// - Parameter work: The teardown. It is called on the main actor, synchronously when possible.
    func addMainActorTeardown(_ work: @escaping () -> Void) {
        mainActorTeardown.append(work)
    }

    /// Removes everything now. Safe from any thread, and safe to call repeatedly.
    ///
    /// **Reusable.** This removes the tokens currently held and nothing more — it does not disable the
    /// store. That matters because the owners legitimately cycle: `ScreenGuardAppSwitcherShield`
    /// re-installs, and the capture-state observer re-registers when the view moves to a new screen.
    /// A store that latched into a dead state after its first `invalidate()` would silently stop
    /// removing the tokens added afterwards, leaking an observer per re-install.
    ///
    /// Called explicitly by `stop()` / `uninstall()`, and implicitly on deallocation.
    func invalidate() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()

        let teardown = mainActorTeardown
        mainActorTeardown.removeAll()
        guard !teardown.isEmpty else {
            return
        }

        if Thread.isMainThread {
            // Already on the main actor — `assumeIsolated` is valid here, and this is the only place
            // it is used.
            MainActor.assumeIsolated {
                for work in teardown {
                    work()
                }
            }
        } else {
            // Hop without blocking the releasing thread. The work captures its own references, so
            // nothing dangles.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for work in teardown {
                        work()
                    }
                }
            }
        }
    }

    /// Removes everything on deallocation.
    deinit {
        invalidate()
    }
}
