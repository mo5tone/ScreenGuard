//
//  ScreenGuardAppSwitcherShield.swift
//  ScreenGuard
//
//  App-switcher snapshot protection. See docs/api-contract.md §3.4 / §6.7.
//
//  ⚠️ DEVICE-PENDING. The system writes its app-switcher snapshot to
//  `data/Library/SplashBoard/Snapshots/**/*.ktx` in Apple's proprietary AAPL-magic KTX variant, which
//  NEITHER ImageMagick NOR ffmpeg can decode (docs/TOOLING.md §4). Snapshot pixels are therefore NOT
//  pixel-verifiable on Simulator, and this capability is device-validated only.
//
//  MECHANISM REQUIREMENT: the cover must be installed SYNCHRONOUSLY on
//  `UISceneWillDeactivateNotification` — the system snapshots immediately afterwards. An asynchronous
//  or deferred cover is a defect. Everything in this file is therefore synchronous.
//
//  This does not protect against a real screenshot or a recording. It covers the app-switcher
//  snapshot only.
//

import UIKit

// MARK: - Style

/// What is shown in place of the app's content while the scene is inactive.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardAppSwitcherStyle {

    /// A blur of the covered content. Default.
    case blur(style: UIBlurEffect.Style)

    /// A solid colour.
    case opaque(color: UIColor)

    /// A brand cover, e.g. a logo on the app's background colour.
    case branded(image: UIImage?, backgroundColor: UIColor)
}

// MARK: - Shield

/// Covers the window while the scene is inactive, so the system's app-switcher snapshot does not
/// contain app content.
///
/// ⚠️ **DEVICE-PENDING.** Snapshot pixels cannot be decoded on Simulator (`docs/TOOLING.md` §4), so
/// this capability is device-validated only. See `docs/api-contract.md` §3.4.
///
/// ```swift
/// let cover = ScreenGuardAppSwitcherShield(style: .branded(image: logo, backgroundColor: .systemBackground))
/// cover.install(on: window)
/// ```
///
/// iOS 15-compatible — no availability guard is required.
@MainActor
public final class ScreenGuardAppSwitcherShield: UIView {

    // MARK: - Public surface

    /// The cover's appearance. Changing it updates the installed cover immediately.
    public var style: ScreenGuardAppSwitcherStyle {
        didSet { applyStyle() }
    }

    /// Whether the cover is currently installed on a window.
    public private(set) var isInstalled: Bool = false

    /// Called when the shield could not engage, so the host can report a `protectionDegraded` event
    /// rather than believing it is covered.
    ///
    /// Invoked with `.appSwitcherCoverUnavailable` when there is nothing to cover: a window with no
    /// scene (so the lifecycle signal cannot be bound to it), or a `coverNow()` on a shield that was
    /// never installed. Without this the seam was inert and its monitor wiring unreachable: a host
    /// could be told nothing at all while nothing had been installed.
    public var onProtectionFailure: ((ScreenGuardProtectionFailure) -> Void)?

    // MARK: - Private state

    private weak var hostWindow: UIWindow?

    /// Owns the lifecycle-notification tokens, so they are removed even if the shield is released
    /// without `uninstall()` — from any thread, without trapping. See
    /// `ScreenGuardObserverTokenStore`'s header.
    private let tokens = ScreenGuardObserverTokenStore()

    /// The opaque content view that carries the cover. Held so the blur / logo can be swapped without
    /// rebuilding the observer wiring.
    private let coverView = UIView()

    /// The blur or logo on top of `coverView`.
    private var effectView: UIView?

    // MARK: - Init

    /// Creates a shield.
    ///
    /// - Parameter style: What to show in place of the content. Default
    ///   `.blur(style: .systemMaterial)`.
    public init(style: ScreenGuardAppSwitcherStyle = .blur(style: .systemMaterial)) {
        self.style = style
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        // Hidden until the scene deactivates: while the app is foreground-active the cover must not
        // obstruct anything.
        isHidden = true
        alpha = 0

        coverView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverView)
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverView.topAnchor.constraint(equalTo: topAnchor),
            coverView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyStyle()
    }

    /// Unavailable. Use `init(style:)`.
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ScreenGuardAppSwitcherShield must be created programmatically") }

    // MARK: - Install

    /// Installs the shield on `window` and begins observing scene lifecycle notifications
    /// (`UISceneWillDeactivateNotification` / `UISceneDidActivateNotification`). Idempotent.
    ///
    /// The cover is applied synchronously in the notification handler: the system snapshots
    /// immediately after `UISceneWillDeactivateNotification`, so anything deferred is a defect.
    ///
    /// - Parameter window: The window to cover. It must be retained by the host.
    public func install(on window: UIWindow) {
        if isInstalled, self.hostWindow === window { return }
        if isInstalled { uninstall() }

        self.hostWindow = window
        translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: window.leadingAnchor),
            trailingAnchor.constraint(equalTo: window.trailingAnchor),
            topAnchor.constraint(equalTo: window.topAnchor),
            bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.bringSubviewToFront(self)
        isInstalled = true

        // The scene this window belongs to. Registering with a specific object keeps a multi-scene app
        // from reacting to another scene's lifecycle.
        let scene = window.windowScene

        let willDeactivate = NotificationCenter.default.addObserver(
            forName: UIScene.willDeactivateNotification,
            object: scene,
            queue: .main
        ) { [weak self] _ in
            // SYNCHRONOUS by design — the snapshot follows immediately.
            MainActor.assumeIsolated { self?.coverNow() }
        }

        let didActivate = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: scene,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.uncoverNow() }
        }

        tokens.add(notificationToken: willDeactivate)
        tokens.add(notificationToken: didActivate)

        // A scene that is already inactive when the shield is installed (e.g. installed from a
        // background launch path) must be covered immediately.
        if let scene, scene.activationState != .foregroundActive {
            coverNow()
        }

        // There is no scene to bind to. The cover is still installed and will still respond to a
        // deactivation notification (the observer is registered for every scene in that case), but
        // reporting is the difference between "covered, one signal late" and silence.
        if !Self.canCover(window: window) {
            onProtectionFailure?(.appSwitcherCoverUnavailable)
        }
    }

    /// Removes the shield and every observer. Idempotent.
    public func uninstall() {
        tokens.invalidate()
        removeFromSuperview()
        hostWindow = nil
        isInstalled = false
    }

    // MARK: - Coverability

    /// Whether `window` is something this shield can cover.
    ///
    /// A cover is driven by `UISceneWillDeactivateNotification`, which is bound to a scene, so a
    /// window without one has no signal this shield can react to. `nil` is the "no window at all"
    /// case. Internal rather than public so the predicate itself is unit-testable — the failure seam
    /// this feeds used to be inert precisely because its condition was never exercised.
    ///
    /// - Parameter window: The window to test, or `nil`.
    /// - Returns: `true` when the window has a scene to bind the lifecycle signal to.
    static func canCover(window: UIWindow?) -> Bool {
        window?.windowScene != nil
    }

    // MARK: - Covering

    /// Installs the cover. Called synchronously from the deactivation notification.
    ///
    /// Reports `.appSwitcherCoverUnavailable` when the shield is not installed on a window, because
    /// then there is nothing to cover — silence here would leave a host believing the app-switcher
    /// snapshot is covered when no cover exists.
    public func coverNow() {
        guard isInstalled else {
            onProtectionFailure?(.appSwitcherCoverUnavailable)
            return
        }
        isHidden = false
        alpha = 1
        hostWindow?.bringSubviewToFront(self)
    }

    /// Removes the cover.
    public func uncoverNow() {
        alpha = 0
        isHidden = true
    }

    // MARK: - Style

    private func applyStyle() {
        effectView?.removeFromSuperview()
        effectView = nil

        switch style {
        case .blur(let blurStyle):
            coverView.backgroundColor = .clear
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
            blur.translatesAutoresizingMaskIntoConstraints = false
            coverView.addSubview(blur)
            NSLayoutConstraint.activate([
                blur.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
                blur.topAnchor.constraint(equalTo: coverView.topAnchor),
                blur.bottomAnchor.constraint(equalTo: coverView.bottomAnchor)
            ])
            effectView = blur

        case .opaque(let color):
            coverView.backgroundColor = color

        case .branded(let image, let backgroundColor):
            coverView.backgroundColor = backgroundColor
            guard let image else { return }
            let imageView = UIImageView(image: image)
            imageView.contentMode = .center
            imageView.translatesAutoresizingMaskIntoConstraints = false
            coverView.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: coverView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor)
            ])
            effectView = imageView
        }
    }
}
