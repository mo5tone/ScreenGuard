//
//  DemoShieldContainer.swift
//  ScreenGuardDemo
//
//  A demo-side wrapper around `ScreenGuardShieldView`.
//
//  WHY THIS EXISTS (and why it is not a criticism of the package)
//  -------------------------------------------------------------
//  The private secure-layer path needs two things the package correctly refuses to do implicitly:
//
//    1. The explicit runtime opt-in, `ScreenGuard.PrivateAPI.isEnabled = true` — naming the strategy
//       is not enough, and that is deliberate (`docs/api-contract.md` §9.2).
//    2. A **window**. The private canvas only exists once UIKit has built the secure field's render
//       hierarchy, and `ScreenGuardPrivateSecureLayer.engage(on:)` correctly refuses and reports
//       `.privateSecureLayerSwapFailed` when there is no window.
//
//  A SwiftUI `UIViewRepresentable` cannot order those reliably — the strategy has to be re-applied
//  after the view joins the window. So the demo owns that ordering here, in UIKit, where the
//  lifecycle is explicit, and leaves the package untouched.
//
//  ⚠️ THE PRIVATE PATH IS A PRIVATE API. Non-contract, fragile across iOS releases, an App Review
//  risk, and never a security guarantee (`docs/api-contract.md` §9). It is off unless this demo's
//  caller turns it on.
//

import UIKit
import ScreenGuard

/// Hosts a `ScreenGuardShieldView` over a live content view, and re-applies the strategy once the
/// shield is in a window.
@MainActor
final class DemoShieldContainer: UIView {

    /// Called after every state synchronisation, so a host can render the shield's real status.
    var onStateChange: ((ScreenGuardShieldView) -> Void)?

    /// The shield itself, exposed so a host can read `isProtecting`, `shieldMode` and
    /// `protectionFailure` — and so a probe can report them.
    let shield: ScreenGuardShieldView

    /// The live content the shield is asked to protect.
    private let content: UIView

    /// A view controller whose `view` is `content`, retained for as long as the container lives.
    ///
    /// Needed when the content is a `UIHostingController`'s view: the view alone does not keep its
    /// controller alive, and a deallocated hosting controller is not a supported state.
    var retainedHost: UIViewController?

    /// The strategy the host asked for.
    private var requested: ScreenGuardNoLeakStrategy

    /// Retries left for the private path, which cannot engage before the view has a window.
    private var retriesRemaining = 4

    /// Creates a container.
    ///
    /// - Parameters:
    ///   - strategy: The no-leak strategy to request.
    ///   - content: The live content view to protect.
    ///   - shieldColor: The colour behind the protected layer. Default `.black`, which is the
    ///     construction the product promise is written in ("protected regions come out black").
    init(
        strategy: ScreenGuardNoLeakStrategy,
        content: UIView,
        shieldColor: UIColor = .black
    ) {
        self.requested = strategy
        self.content = content
        // Start inert and engage deliberately, so the ordering above is under this type's control.
        self.shield = ScreenGuardShieldView(strategy: .disabled)
        super.init(frame: .zero)

        shield.shieldColor = shieldColor
        shield.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shield)
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: trailingAnchor),
            shield.topAnchor.constraint(equalTo: topAnchor),
            shield.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        sync()
    }

    /// Unavailable. Use `init(strategy:content:shieldColor:)`.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DemoShieldContainer must be created programmatically") }

    /// Requests a different strategy and re-synchronises.
    ///
    /// - Parameter strategy: The strategy to request.
    func request(_ strategy: ScreenGuardNoLeakStrategy) {
        requested = strategy
        retriesRemaining = 4
        sync()
    }

    /// The strategy currently requested.
    var requestedStrategy: ScreenGuardNoLeakStrategy { requested }

    /// Re-applies the requested strategy. Safe to call repeatedly.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        sync()
    }

    /// Lays out the shield so the private canvas exists before the swap is attempted.
    override func layoutSubviews() {
        super.layoutSubviews()
        shield.setNeedsContentRefresh()
    }

    // MARK: - Synchronisation

    /// Applies `requested` in the order the package requires, and reports the real outcome.
    private func sync() {
        // Detach first. Re-assigning `protectedContentView` is what moves the content between the
        // live hierarchy (private path, and the labelled fallback) and the rasterised path (public
        // path), and doing it explicitly keeps a strategy change from leaving live content behind.
        shield.protectedContentView = nil

        shield.apply(strategy: requested)

        if requested == .privateSecureLayer, !shield.isProtecting {
            // Not engaged — either the opt-in is off, or the view is not in a window yet. Show the
            // content anyway so the page is readable, and let the host render the fact that the
            // shield is NOT protecting. Never silently look protected.
            shield.protectedContentView = content
            scheduleRetryIfPossible()
        } else {
            shield.protectedContentView = content
        }

        setNeedsLayout()
        layoutIfNeeded()
        onStateChange?(shield)
    }

    /// Retries the private-path engagement after the next layout pass.
    private func scheduleRetryIfPossible() {
        guard retriesRemaining > 0, window != nil else { return }
        retriesRemaining -= 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutIfNeeded()
            self.sync()
        }
    }
}
