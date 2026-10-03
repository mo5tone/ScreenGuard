//
//  ScreenGuardMonitor.swift
//  ScreenGuard
//
//  The detection engine. See docs/api-contract.md §6.2.
//
//  Detection only. The monitor observes and reports; it changes nothing about a capture, and it
//  cannot prevent one. Every event it emits is described honestly in ScreenGuardCapability's
//  registry — read that before describing this class to a user.
//

import Combine
import UIKit

/// Observes capture state and screenshot events and republishes them as `ScreenGuardEvent` values.
///
/// The monitor is the single detection seam. Start it from `viewDidLoad` / `onAppear`; it is
/// idempotent and safe to call repeatedly.
///
/// ```swift
/// final class ViewController: UIViewController, ScreenGuardDelegate {
///     func viewDidLoad() {
///         super.viewDidLoad()
///         ScreenGuard.start(delegate: self)
///     }
///
///     func screenGuard(_ monitor: ScreenGuardMonitor, didDetect event: ScreenGuardEvent) {
///         switch event.kind {
///         case .screenshotTaken:       audit.log("screenshot")
///         case .captureBegan:          audit.log("capture began")
///         case .captureEnded:          audit.log("capture ended")
///         case .protectionDegraded:    audit.log("protection degraded")
///         }
///     }
/// }
/// ```
///
/// iOS 15-compatible — no availability guard is required.
@MainActor
public final class ScreenGuardMonitor: ObservableObject {
    // MARK: - Configuration

    /// The configuration this monitor was created with.
    public let configuration: ScreenGuardConfiguration

    // MARK: - Observable state

    /// Current knowledge. Observable from SwiftUI via `@ObservedObject` / `@StateObject`.
    @Published public private(set) var state: ScreenGuardState

    // MARK: - Seams

    /// Delegate seam. Held **weakly** — the host must retain its delegate.
    public weak var delegate: ScreenGuardDelegate?

    /// Closure seam, for callers that prefer it. Called on the main actor, after `delegate`.
    public var onEvent: ((ScreenGuardEvent) -> Void)?

    // MARK: - Engine

    private let captureStateObserver = ScreenGuardCaptureStateObserver()
    private let screenshotObserver = ScreenGuardScreenshotObserver()

    /// The window whose scene is observed for capture state. Weak: the monitor must not keep a
    /// window alive.
    private weak var observedWindow: UIWindow?

    /// The app-switcher cover, when `configuration.isAppSwitcherShieldEnabled` is `true`.
    private var appSwitcherShield: ScreenGuardAppSwitcherShield?

    /// The key window the app-switcher cover was installed on.
    private weak var shieldWindow: UIWindow?

    private var keyWindowObserver: NSObjectProtocol?

    // MARK: - Init

    /// Creates a monitor.
    ///
    /// - Parameter configuration: The configuration to use. Defaults to
    ///   `ScreenGuardConfiguration()` — screenshot detection, capture-state detection and the
    ///   app-switcher cover all on, and the no-leak strategy `.publicPreventsCaptureLayer`.
    public init(configuration: ScreenGuardConfiguration = ScreenGuardConfiguration()) {
        self.configuration = configuration
        state = ScreenGuardState()

        captureStateObserver.onStateChange = { [weak self] captureState, source in
            self?.handleCaptureStateChange(to: captureState, source: source)
        }
        screenshotObserver.onScreenshot = { [weak self] in
            self?.handleScreenshot()
        }
    }

    // MARK: - Lifecycle

    /// Begins observation. Idempotent. Safe to call from `viewDidLoad` / `onAppear`.
    ///
    /// On iOS 17+ the scene-capture trait is the only signal registered — the legacy `UIScreen`
    /// observer is not installed at all, so one signal produces exactly one event.
    public func start() {
        guard !isMonitoring else {
            return
        }

        state.isMonitoring = true

        if configuration.isCaptureStateDetectionEnabled, let host = hostForCaptureState() {
            captureStateObserver.start(host: host)
        }

        if configuration.isScreenshotDetectionEnabled {
            screenshotObserver.start()
        }

        if configuration.isAppSwitcherShieldEnabled {
            startAppSwitcherShield()
        }
    }

    /// Stops observation and removes every observer and trait registration. Idempotent.
    public func stop() {
        guard isMonitoring || hasResidualObservers else {
            return
        }

        captureStateObserver.stop()
        screenshotObserver.stop()
        stopAppSwitcherShield()

        state.isMonitoring = false
        state.detectionSource = nil
        state.captureState = .unspecified
    }

    /// Whether the monitor is currently observing.
    public var isMonitoring: Bool {
        state.isMonitoring
    }

    /// `true` when an observer is still installed even though `isMonitoring` is `false`. Guards
    /// `stop()` against being a no-op before `start()`, and keeps it idempotent after.
    private var hasResidualObservers: Bool {
        captureStateObserver.isObserving
            || screenshotObserver.isObserving
            || appSwitcherShield != nil
            || keyWindowObserver != nil
    }

    // MARK: - Host resolution

    /// The best trait environment available for capture-state registration.
    ///
    /// Prefers the key window's root view (a `UITraitEnvironment`, as in the contract's verified
    /// snippet); falls back to the key window's `UIWindowScene`, which is also a
    /// `UITraitChangeObservable`. If neither exists yet, the observer starts against a scene when one
    /// appears (see `observeKeyWindowChanges`).
    private func hostForCaptureState() -> ScreenGuardCaptureStateObserver.Host? {
        if let window = resolvedWindow(), window.windowScene != nil {
            return .view(window)
        }
        if let scene = resolvedWindow()?.windowScene {
            return .windowScene(scene)
        }
        observeKeyWindowChanges()
        return nil
    }

    /// Resolves the window to observe without ever touching `UIScreen.main` (hard-deprecated as of
    /// iOS 26.0).
    private func resolvedWindow() -> UIWindow? {
        if let observedWindow, observedWindow.windowScene != nil {
            return observedWindow
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
        if let keyWindow {
            observedWindow = keyWindow
            return keyWindow
        }
        let anyWindow = scenes.first?.windows.first
        observedWindow = anyWindow
        return anyWindow
    }

    /// Re-attempts registration when a window becomes key. Needed because a monitor may be started
    /// before the app's window exists (e.g. from an early `init`).
    private func observeKeyWindowChanges() {
        guard keyWindowObserver == nil else {
            return
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isMonitoring, self.configuration.isCaptureStateDetectionEnabled else {
                    return
                }
                guard let host = self.hostForCaptureState() else {
                    return
                }
                if let keyWindowObserver = self.keyWindowObserver {
                    NotificationCenter.default.removeObserver(keyWindowObserver)
                    self.keyWindowObserver = nil
                }
                self.captureStateObserver.start(host: host)
            }
        }
    }

    // MARK: - Event delivery

    private func handleCaptureStateChange(
        to captureState: ScreenGuardCaptureState,
        source: ScreenGuardDetectionSource
    ) {
        let previous = state.captureState
        state.captureState = captureState
        state.detectionSource = source

        guard let kind = ScreenGuardEventMapper.eventKind(from: previous, to: captureState) else {
            return
        }
        emit(ScreenGuardEvent(kind: kind, captureState: captureState, detectionSource: source))
    }

    private func handleScreenshot() {
        let now = Date()
        state.lastScreenshotAt = now
        state.detectionSource = .screenshotNotification
        emit(
            ScreenGuardEvent(
                kind: .screenshotTaken,
                captureState: state.captureState,
                detectionSource: .screenshotNotification,
                timestamp: now
            )
        )
    }

    /// Emits a protection-degraded event. Called by the shield when a no-leak mechanism fails to
    /// engage, so protection never fails silently.
    ///
    /// - Parameter reason: Why protection could not engage.
    public func reportProtectionFailure(_ reason: ScreenGuardProtectionFailure) {
        let source = state.detectionSource ?? .sceneCaptureState
        emit(
            ScreenGuardEvent(
                kind: .protectionDegraded(reason: reason),
                captureState: state.captureState,
                detectionSource: source
            )
        )
    }

    private func emit(_ event: ScreenGuardEvent) {
        delegate?.screenGuard(self, didDetect: event)
        onEvent?(event)
    }

    // MARK: - App-switcher shield

    private func startAppSwitcherShield() {
        guard appSwitcherShield == nil else {
            return
        }
        let shield = ScreenGuardAppSwitcherShield()
        shield.onProtectionFailure = { [weak self] reason in
            self?.reportProtectionFailure(reason)
        }
        appSwitcherShield = shield
        installShieldIfPossible()
    }

    private func installShieldIfPossible() {
        guard let shield = appSwitcherShield, let window = resolvedWindow() else {
            observeKeyWindowChanges()
            return
        }
        shield.install(on: window)
        shieldWindow = window
    }

    private func stopAppSwitcherShield() {
        appSwitcherShield?.uninstall()
        appSwitcherShield = nil
        shieldWindow = nil
    }

    // MARK: - Cleanup

    // No `deinit`. Every observer and the app-switcher cover own their own teardown through
    // `ScreenGuardObserverTokenStore`, which removes its tokens when it is released — from whatever
    // thread that release happens on.
    //
    // This is deliberate and load-bearing. The obvious alternative,
    //
    //     deinit { MainActor.assumeIsolated { captureStateObserver.stop() } }
    //
    // TRAPS (SIGABRT) when the last release lands off the main thread, because `assumeIsolated`
    // asserts the current executor already is the main actor. `@MainActor` on the class constrains
    // where its methods are called; it does not control which thread performs the final `release`.
    // Measured: a monitor started on the main thread and released from a background queue crashed the
    // test process with exactly that pattern (see ScreenGuardObserverTokenStore's header, and
    // ScreenGuardMonitorTests.testDeallocatingARunningMonitorOffTheMainThread).
    //
    // docs/api-contract.md §10 requires `deinit` not to need manual cleanup. Ownership, not `deinit`,
    // is what delivers that.
}
