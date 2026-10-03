//
//  ScreenGuardShieldView.swift
//  ScreenGuard
//
//  The no-leak container (public path). See docs/api-contract.md §3.2 and §6.4.
//
//  WHAT THIS VIEW DOES, HONESTLY
//  ----------------------------
//  It renders protected content into an `AVSampleBufferDisplayLayer` with
//  `preventsCapture = true`, over an opaque shield. `AVSampleBufferDisplayLayer.preventsCapture`
//  (iOS 13+) is the ONLY public capture-protection API Apple publishes, and it protects only the
//  content rendered into that layer.
//
//  ⚠️ DEVICE-PENDING. On Simulator, `preventsCapture = true` makes the layer paint NOTHING AT ALL —
//  including on screen. A protected region therefore appears empty on Simulator. That is a
//  FAIL-CLOSED behaviour, not a leak, and it is the expected Simulator result. The public path's
//  actual capture behaviour is not measurable on Simulator and must be settled on hardware
//  (docs/evidence/capability-matrix.md §4).
//
//  ⚠️ RASTERISATION LIMIT. Whenever the content arrives as a RENDER CLOSURE — which is what the
//  SwiftUI route always supplies, because SwiftUI content has no live `UIView` — it is rendered to an
//  image on EVERY strategy. On the public path that image is pushed through the `CMSampleBuffer` →
//  layer pipeline; on the other modes it is hosted as a live `UIImageView` inside the shield. Either
//  way it is a REFRESHED SNAPSHOT, not a live view: animations and direct interaction inside a
//  protected region do not update unless the refresh policy, `setNeedsContentRefresh()` or a size
//  change causes a re-render. Only a shield handed a `protectedContentView` hosts genuinely live
//  content. This is a real trade-off and must be stated, not hidden.
//
//  NO SILENT FAILURE. If the mechanism cannot be engaged, `isProtecting` is `false`,
//  `protectionFailure` is set, `shieldMode` becomes `.detectionAndOverlayFallback`, and the view
//  emits a `protectionDegraded` event through `onProtectionFailure`. The view then shows the content
//  as a plain visual overlay — which removes no pixels from any capture, and says so.
//

import AVFoundation
import CoreGraphics
import UIKit

/// Hosts content that must not leak into captures.
///
/// The shield is the no-leak container. Content is supplied either as a live view
/// (`protectedContentView`) or as a render closure (`protectedContentRenderer`). On
/// `.publicPreventsCaptureLayer` the content is **rasterised** and pushed to the protected layer, so
/// it is a refreshed snapshot rather than a live view — see the type-level note.
///
/// A render closure's output is not dropped by the other modes: it is hosted as a live `UIImageView`
/// inside the shield, which is what makes the SwiftUI route work on `.privateSecureLayer` (where the
/// host must be a live view for the private exclusion to cover it) and what makes the labelled
/// `.detectionAndOverlayFallback` visible instead of an opaque black hole
/// (review round 2, finding F-R2-1).
///
/// ```swift
/// let shield = ScreenGuardShieldView()
/// shield.protectedContentView = accountCard
/// shield.refreshPolicy = .onLayout
/// // Check the outcome — never assume.
/// if !shield.isProtecting { audit.log("shield degraded: \(shield.protectionFailure as Any)") }
/// ```
///
/// iOS 15-compatible — every deprecated `AVSampleBufferDisplayLayer` member sits behind an
/// availability guard (docs/api-contract.md §7.2).
@MainActor
public final class ScreenGuardShieldView: UIView {
    // MARK: - Public surface

    /// Live content to protect.
    ///
    /// Rasterised on refresh when the strategy is `.publicPreventsCaptureLayer`; hosted directly when
    /// it is `.privateSecureLayer`.
    ///
    /// **The shield owns where this view lives.** On the public path it is deliberately kept OUT of
    /// the live hierarchy, because a subview in the live hierarchy is rendered by the ordinary capture
    /// path and would leak while the shield claimed protection. Switching strategy re-establishes
    /// that; a host does not have to detach it by hand.
    public var protectedContentView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            // No `guard protectedContentView != nil` here: assigning `nil` must fall back to the
            // render closure when there is one, rather than leaving the last picture on screen.
            synchronizeContentHosting()
            setNeedsContentRefresh()
        }
    }

    /// Alternative content source for content that is not a `UIView` (e.g. SwiftUI).
    ///
    /// Called on the main actor with the target size and screen scale.
    ///
    /// On `.publicPreventsCaptureLayer` the returned image goes into the protected display layer. On
    /// every other mode it is hosted as a live `UIImageView` inside the shield — which is what makes
    /// a SwiftUI-driven shield render at all on `.privateSecureLayer` and on the labelled
    /// `.detectionAndOverlayFallback` (review round 2, F-R2-1). A renderer is used only while
    /// `protectedContentView` is `nil`; a caller-supplied live view always wins.
    public var protectedContentRenderer: ((CGSize, CGFloat) -> UIImage?)? {
        didSet { setNeedsContentRefresh() }
    }

    /// Colour behind the protected layer. Default `.black` — this is what turns "pixels removed"
    /// into the "region is black" the product promise is written in.
    public var shieldColor: UIColor = .black {
        didSet { backgroundColor = shieldColor }
    }

    /// How often the shield re-rasterises its protected content.
    public var refreshPolicy: ScreenGuardRefreshPolicy = .manual {
        didSet { applyRefreshPolicy() }
    }

    /// `true` only when the selected strategy is actually engaged.
    ///
    /// `false` when `.disabled`, and `false` when the mechanism could not be engaged (including a
    /// failed private-path swap, or the private file having been excluded from the build).
    /// **Check this — do not assume.**
    ///
    /// - Important: `isProtecting` means **"the mechanism is engaged"**, not "a protected frame has
    ///   been produced". On the public path the layer exists and is configured from the moment the
    ///   strategy is applied, but the first frame can only be pushed once the view has a non-degenerate
    ///   size. Read `hasPushedFrame` for that stronger property; on `false` a blank region means
    ///   "nothing has been pushed yet", which is a different (and diagnosable) condition from
    ///   "the pixels were excluded" (`docs/TOOLING.md` §3).
    public private(set) var isProtecting: Bool = false

    /// Whether at least one frame has been successfully rasterised and enqueued into the protected
    /// display layer on the public path.
    ///
    /// `false` until the view has been laid out with a usable size, and `false` again if a later
    /// enqueue fails.
    ///
    /// - Important: **Always `false` on `.disabled`, on `.detectionAndOverlayFallback` and on
    ///   `.privateSecureLayer`**, because those modes never enqueue anything into a display layer.
    ///   In particular, a renderer-backed shield on `.privateSecureLayer` DOES rasterise a picture and
    ///   host it live, and this flag stays `false` there by design — do not read it as "nothing is
    ///   being shown". It answers one question only: "has a frame been pushed into the protected
    ///   layer?" See `isProtecting` for how the two differ.
    public private(set) var hasPushedFrame: Bool = false

    /// The strategy actually in effect, which may differ from the requested one if the requested
    /// strategy is unavailable on this OS build.
    public private(set) var effectiveStrategy: ScreenGuardNoLeakStrategy = .disabled

    /// Non-nil when protection failed to engage.
    ///
    /// Also emitted as `ScreenGuardEvent.Kind.protectionDegraded`.
    public private(set) var protectionFailure: ScreenGuardProtectionFailure?

    /// Records whether a protected frame was pushed. Internal, so the extension files in this
    /// directory can write it while the public surface stays read-only (private setter).
    func recordPushedFrame(_ pushed: Bool) {
        hasPushedFrame = pushed
    }

    /// Records a protection failure, or clears it. Internal for the same reason as the recorder above.
    func recordProtectionFailure(_ failure: ScreenGuardProtectionFailure?) {
        protectionFailure = failure
    }

    /// What the shield is actually doing, including the clearly-labelled degraded case.
    ///
    /// When this is `.detectionAndOverlayFallback` the shield is **not a no-leak control**: it
    /// removes no pixels from any capture. See `ScreenGuardShieldMode`.
    public private(set) var shieldMode: ScreenGuardShieldMode = .disabled

    /// Called when protection could not be engaged. The monitor wires this to
    /// `reportProtectionFailure(_:)`, which turns it into a `protectionDegraded` event.
    public var onProtectionFailure: ((ScreenGuardProtectionFailure) -> Void)?

    /// The strategy the shield was asked to use **most recently** — the init-time strategy until
    /// `apply(strategy:)` is called, and the last applied strategy afterwards.
    ///
    /// - Important: This is a *tracked* value, not an init-time snapshot. It used to be a `let`, which
    ///   made it go stale the moment `apply(strategy:)` changed the strategy, and that broke the
    ///   package's own SwiftUI bridge: `ScreenGuardShieldRepresentable.updateUIView` compares this
    ///   against the incoming strategy to decide whether to re-apply, so a value that never converged
    ///   caused a full teardown and re-rasterisation on **every** SwiftUI update pass.
    ///
    /// Use it to discover what was last requested; use `effectiveStrategy` for what is actually in
    /// effect, and `isProtecting` for whether it is engaged.
    public private(set) var requestedStrategy: ScreenGuardNoLeakStrategy

    // MARK: - State shared with the extensions in this directory

    //
    // These members are internal rather than private: Swift's private is FILE-scoped, so the
    // ScreenGuardShieldView+*.swift extensions that keep this file under the 400-line limit could
    // not see them otherwise. None of it is public API — the public surface above is unchanged, and
    // docs/api-contract.md §6 still describes exactly what a consumer sees.

    /// The protected display layer. `nil` when the public path is not engaged.
    var displayLayer: AVSampleBufferDisplayLayer?

    /// Hosts a render closure's output as a live subview, for the modes that display content.
    ///
    /// `nil` whenever there is nothing rendered to show: on the public path (which must keep the live
    /// hierarchy empty), and whenever the caller supplied a live `protectedContentView` instead.
    var renderedContentHost: UIImageView?

    /// The size the render closure last produced content at, so a size change re-rasterises.
    ///
    /// Shared by both render-closure consumers — the display layer on the public path and the hosted
    /// picture everywhere else — because they need the same two things from it: a FIRST render once the
    /// shield has a usable size, and a NEW one when that size changes. `.zero` means "no render has
    /// succeeded for the current arrangement yet".
    var lastRenderedSize: CGSize = .zero

    /// Owns the engaged private-path engine.
    ///
    /// Typed as the protocol, never as the concrete private-API type, so excluding
    /// `ScreenGuardPrivateSecureLayer.swift` leaves this file compiling (docs/api-contract.md §9.4).
    /// The owner is what releases the arrangement from `teardown()` and from `deinit` — see
    /// `ScreenGuardPrivateLayerOwner`.
    let privateLayerOwner = ScreenGuardPrivateLayerOwner()

    /// The iOS 17+ display-scale trait registration, so a scale change re-rasterises.
    ///
    /// Stored as `Any?` because `any UITraitChangeRegistration` is itself iOS 17.0+, so it cannot be
    /// the type of a stored property at an iOS 15 deployment target (`docs/api-contract.md` §7.1).
    var displayScaleRegistration: Any?

    /// Drives `.periodic` refreshes.
    var refreshTimer: Timer?

    /// Guards against re-entrant refresh during layout.
    var isRefreshing = false

    /// The scale of the last rasterisation, so a scale change can force a refresh.
    ///
    /// On iOS 17+ the trait registration below drives this. On iOS 15/16 this is compared in
    /// `layoutSubviews`, which is the non-deprecated route available at that deployment target — the
    /// `traitCollectionDidChange(_:)` override that used to do it is deprecated in iOS 17.0.
    var lastRasterisationScale: CGFloat = 0

    // MARK: - Init

    /// Creates a shield.
    ///
    /// - Parameter strategy: The no-leak mechanism to use. Defaults to
    ///   `.publicPreventsCaptureLayer` — the private path is never the default.
    ///
    /// - Important: **The private path needs a window, and this initialiser runs before the shield has
    ///   one.** `.privateSecureLayer` is only permitted to engage once the shield is in a window,
    ///   because the secure canvas does not exist before UIKit has built the field's render hierarchy.
    ///   The shield therefore records the request and **re-attempts engagement from
    ///   `didMoveToWindow`**, so `ScreenGuardShieldView(strategy: .privateSecureLayer)` behaves as
    ///   documented and a host does not have to know the ordering. Until that happens
    ///   `isProtecting == false` and `protectionFailure` says why — never a silent claim of
    ///   protection.
    public init(strategy: ScreenGuardNoLeakStrategy = .publicPreventsCaptureLayer) {
        requestedStrategy = strategy
        super.init(frame: .zero)
        backgroundColor = shieldColor
        isUserInteractionEnabled = false
        // A shield must not become a black hole in the capture when it is not protecting: the
        // fallback paints the content instead. Clipping keeps a rotated or oversized child inside.
        clipsToBounds = true
        registerForDisplayScaleChanges()
        apply(strategy: strategy)
    }

    /// Unavailable. Use `init(strategy:)`.
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        // Referenced so the parameter keeps its documented name: this view is not constructible from a
        // nib, and the formatter renames an unreferenced parameter.
        _ = coder
        fatalError("ScreenGuardShieldView must be created programmatically")
    }

    deinit {
        // `deinit` must not require manual cleanup. `Timer.invalidate` is not actor-isolated, so it
        // is safe to touch from here. The engaged private-path engine is released by
        // `privateLayerOwner`'s own `deinit`, which hops to the main actor without assuming the
        // releasing thread is main — `MainActor.assumeIsolated` here would trap (SIGABRT), which is
        // the defect `ScreenGuardObserverTokenStore` records.
        //
        // The display-scale trait registration is deliberately NOT unregistered here:
        // `unregisterForTraitChanges(_:)` is main-actor isolated, so calling it from a nonisolated
        // `deinit` does not compile (and hopping to the main actor here would either trap off-main or
        // touch a half-deallocated view). The registration's token is owned by this view, so it is
        // released with the view, and the handler captures nothing — it receives the trait environment
        // as a parameter — so there is no retain cycle for the registration to keep alive.
        // `testShieldFromAWindowDeallocates` pins that last claim rather than trusting it.
        refreshTimer?.invalidate()
    }

    // MARK: - Strategy

    /// Switches the shield to a different strategy, tearing down whatever was engaged first.
    ///
    /// Idempotent: re-applying the currently effective strategy is a no-op.
    ///
    /// - Parameter strategy: The mechanism to engage.
    public func apply(strategy: ScreenGuardNoLeakStrategy) {
        // Track the request. This is what makes `requestedStrategy` a live value rather than an
        // init-time snapshot, and what lets the SwiftUI bridge's comparison converge (see the
        // property's documentation).
        requestedStrategy = strategy

        teardown()
        recordProtectionFailure(nil)

        switch strategy {
        case .disabled:
            effectiveStrategy = .disabled
            shieldMode = .disabled
            isProtecting = false
            recordPushedFrame(false)

        case .publicPreventsCaptureLayer:
            effectiveStrategy = .publicPreventsCaptureLayer
            if engagePublicPath() {
                shieldMode = .publicPreventsCaptureLayer
                isProtecting = true
            } else {
                // The mechanism could not be engaged. Do NOT silently claim protection: label it.
                effectiveStrategy = .disabled
                shieldMode = .detectionAndOverlayFallback
                isProtecting = false
                recordPushedFrame(false)
                // Mechanism-correct reason: the private canvas has nothing to do with this path.
                fail(with: .publicPreventsCaptureLayerUnavailable)
            }

        case .privateSecureLayer:
            // `make()` returns nil when the private file has been excluded from the build, which is
            // the documented escape hatch (docs/api-contract.md §9.4).
            guard let engine = ScreenGuardPrivateSecureLayerFactory.make() else {
                effectiveStrategy = .disabled
                shieldMode = .detectionAndOverlayFallback
                isProtecting = false
                recordPushedFrame(false)
                fail(with: .privateSecureLayerUnavailable)
                break
            }
            if engine.engage(on: self) {
                // Adopt the engine so `teardown()` and `deinit` can restore the arrangement — an
                // engaged protection the package cannot release is not one it can promise.
                privateLayerOwner.adopt(engine)
                effectiveStrategy = .privateSecureLayer
                shieldMode = .privateSecureLayer
                isProtecting = true
                recordPushedFrame(false)
                recordProtectionFailure(nil)
            } else {
                // PRIVATE API could not be engaged. Fall back to the LABELLED overlay — never to a
                // silent claim of protection (docs/api-contract.md §9.2).
                effectiveStrategy = .disabled
                shieldMode = .detectionAndOverlayFallback
                isProtecting = false
                recordPushedFrame(false)
                fail(with: engine.failure ?? .privateSecureLayerUnavailable)
            }
        }

        // PUT THE CONTENT WHERE THE MODE REQUIRES IT TO BE. This is the package's job, not the
        // host's: after the transition to the public path the content must not remain a live
        // subview, because a live subview is rendered by the ordinary capture path while the shield
        // claims protection (review round 1, F1).
        synchronizeContentHosting()

        applyRefreshPolicy()
        setNeedsContentRefresh()
    }

    // MARK: - Layout

    /// Lays out the engaged mechanism and honours the `.onLayout` refresh policy.
    override public func layoutSubviews() {
        super.layoutSubviews()
        layoutProtectedContent()
    }
}

// MARK: - Window lifecycle

public extension ScreenGuardShieldView {
    /// Re-attempts private-path engagement when the shield joins a window.
    ///
    /// The private canvas only exists once UIKit has built the secure field's render hierarchy, which
    /// needs a window — so `init(strategy: .privateSecureLayer)` (and any `apply` before the shield is
    /// in a hierarchy) necessarily records the request rather than satisfying it. This makes the
    /// documented call site work without the host having to know the ordering (review round 1, F9).
    ///
    /// It only ever runs for an **unengaged private request**: the public path needs no window, and
    /// re-applying an engaged strategy would tear down and rebuild a working mechanism.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil,
              requestedStrategy == .privateSecureLayer,
              !isProtecting
        else {
            return
        }
        // `apply` re-runs the whole sequence, including the detach/host decision, so this cannot
        // leave live content behind on the public path either.
        apply(strategy: .privateSecureLayer)
    }
}
