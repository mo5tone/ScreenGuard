//
//  ScreenGuardCaptureStateObserver.swift
//  ScreenGuard
//
//  Capture-state observation: the iOS 17+ trait path, and the iOS 15/16 legacy path.
//  Shape taken verbatim from docs/api-contract.md §7.1, which was verified to compile clean with
//  `-warnings-as-errors` at BOTH `-target arm64-apple-ios15.0` and `arm64-apple-ios26.0`.
//
//  TWO TRAPS IN THIS FILE, both verified compile failures, not stylistic preferences:
//
//   1. `any UITraitChangeRegistration` is itself iOS 17.0+, so it CANNOT be the type of a stored
//      property at an iOS 15 deployment target. The token is stored as `Any?` and cast at use site.
//   2. A `NotificationCenter` closure is NONISOLATED even when the queue is `.main`. Calling a
//      `@MainActor` method from it is a warning, i.e. an error under `-warnings-as-errors`. The hop
//      back is explicit (`MainActor.assumeIsolated`).
//
//  `UIScreen.main` is FORBIDDEN here: it is hard-deprecated as of iOS 26.0. The screen is always
//  resolved through `view.window?.windowScene?.screen` (docs/api-contract.md §7.2, §7.3).
//

import UIKit

/// Observes whether the scene is being captured, and reports changes.
///
/// Not public API: this is an internal engine detail. Consumers observe `ScreenGuardMonitor`.
///
/// iOS 15-compatible — every iOS 17+ symbol sits behind an availability guard.
@MainActor
final class ScreenGuardCaptureStateObserver {
    /// What to register the trait change against. Both cases conform to `UITraitChangeObservable` on
    /// iOS 17+; the `UIView` case is preferred because the contract's verified snippet registers
    /// against a view.
    enum Host {
        /// A view in the hierarchy (preferred — `UITraitEnvironment`).
        case view(UIView)
        /// A window scene, used when no view is available.
        case windowScene(UIWindowScene)
    }

    /// Called on the main actor for every reportable state change.
    ///
    /// - Parameters:
    ///   - state: The new capture state.
    ///   - source: The signal that produced it.
    var onStateChange: ((ScreenGuardCaptureState, ScreenGuardDetectionSource) -> Void)?

    /// The most recent state this observer published.
    private(set) var currentState: ScreenGuardCaptureState = .unspecified

    /// Whether the observer is currently registered.
    private(set) var isObserving = false

    /// The iOS 17+ trait registration token. Typed `Any?` on purpose — see trap 1 above.
    private var registration: Any?

    /// Owns the `NotificationCenter` tokens, so they are removed even if the observer is released
    /// without `stop()` — from any thread, without trapping. See
    /// `ScreenGuardObserverTokenStore`'s header for the reproduced crash this avoids.
    private let tokens = ScreenGuardObserverTokenStore()

    /// The screen the legacy observer is registered against.
    private weak var observedScreen: UIScreen?

    private weak var hostView: UIView?

    // MARK: - Lifecycle

    /// Begins observation against `host`. Idempotent: a second call with the same host is a no-op,
    /// and a call with a different host tears the previous registration down first.
    ///
    /// - Parameter host: The trait environment to register against.
    func start(host: Host) {
        if isObserving {
            // Already registered against this host — do not double-register.
            if case let .view(existing) = self.host, case let .view(requested) = host, existing === requested {
                return
            }
            stop()
        }
        self.host = host
        isObserving = true

        switch host {
        case let .view(view):
            hostView = view
            startForView(view)

        case let .windowScene(scene):
            startForWindowScene(scene)
        }
    }

    /// The iOS 17+ trait registration for a view host, or the legacy screen observer below it.
    private func startForView(_ view: UIView) {
        if #available(iOS 17.0, *) {
            let reg = view.registerForTraitChanges(
                [UITraitSceneCaptureState.self]
            ) { (environment: UIView, _: UITraitCollection) in
                // The handler is not actor-isolated; hop back explicitly.
                MainActor.assumeIsolated {
                    self.publish(environment.traitCollection.sceneCaptureState)
                }
            }
            registration = reg
            registerTraitTeardown { [weak view] in
                guard let view else {
                    return
                }
                view.unregisterForTraitChanges(reg)
            }
            publish(view.traitCollection.sceneCaptureState)
        } else {
            startLegacy(screen: view.window?.windowScene?.screen)
        }
    }

    /// The iOS 17+ trait registration for a window-scene host, or the legacy screen observer.
    private func startForWindowScene(_ scene: UIWindowScene) {
        if #available(iOS 17.0, *) {
            let reg = scene.registerForTraitChanges(
                [UITraitSceneCaptureState.self]
            ) { (environment: UIWindowScene, _: UITraitCollection) in
                MainActor.assumeIsolated {
                    self.publish(environment.traitCollection.sceneCaptureState)
                }
            }
            registration = reg
            registerTraitTeardown { [weak scene] in
                guard let scene else {
                    return
                }
                scene.unregisterForTraitChanges(reg)
            }
            publish(scene.traitCollection.sceneCaptureState)
        } else {
            startLegacy(screen: scene.screen)
        }
    }

    /// Removes every registration. Idempotent.
    func stop() {
        unregisterTraitChanges()
        tokens.invalidate()

        observedScreen = nil
        hostView = nil
        host = nil
        isObserving = false
    }

    // MARK: - The stored host

    private var host: Host?

    /// Hands trait teardown to the token store, so the registration is removed even when `stop()` is
    /// never called and even when the final release lands off the main thread.
    private func registerTraitTeardown(_ work: @escaping () -> Void) {
        tokens.addMainActorTeardown(work)
    }

    /// Removes the current trait registration now, on the main actor. Idempotent.
    private func unregisterTraitChanges() {
        guard let registration else {
            return
        }
        self.registration = nil
        if #available(iOS 17.0, *), let reg = registration as? any UITraitChangeRegistration {
            switch host {
            case let .view(view):
                view.unregisterForTraitChanges(reg)

            case let .windowScene(scene):
                scene.unregisterForTraitChanges(reg)

            case .none:
                break
            }
        }
    }

    // MARK: - Legacy path (iOS 15/16 only)

    /// Installs the `capturedDidChangeNotification` observer against a specific screen.
    ///
    /// `object: nil` would observe *every* screen, which is a correctness bug on multi-scene apps
    /// (docs/api-contract.md §7.1 rule 5). When the screen cannot be resolved yet — `view.window` is
    /// `nil` before the view joins a hierarchy — the observer waits for the key window to change and
    /// then re-resolves, rather than silently widening its scope.
    private func startLegacy(screen: UIScreen?) {
        if let screen {
            registerLegacy(screen: screen)
            publishLegacy(screen.isCaptured)
        } else {
            // Not yet in a window hierarchy. Re-resolve when a window becomes key.
            let token = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isObserving else {
                        return
                    }
                    let resolved = self.hostView?.window?.windowScene?.screen
                    guard let resolved, resolved !== self.observedScreen else {
                        return
                    }
                    self.registerLegacy(screen: resolved)
                    self.publishLegacy(resolved.isCaptured)
                }
            }
            tokens.add(notificationToken: token)
        }
    }

    private func registerLegacy(screen: UIScreen) {
        // Re-registering for a new screen: drop the previous tokens first, so a screen change does not
        // leave an observer behind on the old screen.
        tokens.invalidate()
        observedScreen = screen
        let token = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: screen,
            queue: .main
        ) { [weak self, weak screen] _ in
            // Nonisolated closure — hop back explicitly to keep actor isolation honest.
            MainActor.assumeIsolated {
                self?.publishLegacy(screen?.isCaptured ?? false)
            }
        }
        tokens.add(notificationToken: token)
    }

    private func publishLegacy(_ isCaptured: Bool) {
        let state = ScreenGuardEventMapper.captureState(isCaptured: isCaptured)
        publish(state, source: .screenIsCaptured)
    }

    // MARK: - Publishing

    @available(iOS 17.0, *)
    private func publish(_ state: UISceneCaptureState) {
        let mapped: ScreenGuardCaptureState = switch state {
        case .active:
            .active

        case .inactive:
            .inactive

        case .unspecified:
            .unspecified

        @unknown default:
            // Never crash on a future OS value, and never misread it as "active".
            .unspecified
        }
        publish(mapped, source: .sceneCaptureState)
    }

    private func publish(_ state: ScreenGuardCaptureState, source: ScreenGuardDetectionSource) {
        guard state != currentState else {
            return
        }
        currentState = state
        onStateChange?(state, source)
    }
}
