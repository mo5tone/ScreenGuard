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

// MARK: - Shield mode

/// What the shield is actually doing, as opposed to what it was asked to do.
///
/// This exists so a degraded shield is **clearly labelled** rather than silently shipping a broken
/// guarantee. A host app can render this value directly; it is `String`-backed for that reason.
///
/// iOS 15-compatible — no availability guard is required.
public enum ScreenGuardShieldMode: String, Equatable, Sendable {

    /// No protection. Content is shown normally. Layout and debugging only.
    case disabled

    /// Public path engaged: content is rasterised into an `AVSampleBufferDisplayLayer` with
    /// `preventsCapture = true`, over an opaque shield.
    ///
    /// ⚠️ **DEVICE-PENDING.** On Simulator the layer paints nothing at all, so protected regions
    /// appear empty on screen. Fail-closed, not a leak. Requires device validation.
    case publicPreventsCaptureLayer

    /// Private path engaged: the content's layer was reparented into a private secure-canvas
    /// descendant of a hidden secure text field (the class name is not contract and lives only in
    /// `Shield/ScreenGuardPrivateSecureLayer.swift`).
    ///
    /// ⚠️ PRIVATE API. Non-contract. Fragile across iOS releases. App Review risk. Never a security
    /// guarantee.
    case privateSecureLayer

    /// **FALLBACK — NOT A NO-LEAK CONTROL.** The requested mechanism could not be engaged, so the
    /// shield shows the protected content as a plain visual overlay. It removes **no pixels** from
    /// any capture, screenshot or recording, and it protects nothing. The host app should treat this
    /// as "detection only": use `ScreenGuardMonitor` to learn that a capture happened, and treat the
    /// content as unprotected.
    case detectionAndOverlayFallback
}

// MARK: - Shield view

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

    // MARK: - Private state

    /// The protected display layer. `nil` when the public path is not engaged.
    private var displayLayer: AVSampleBufferDisplayLayer?

    /// Hosts a render closure's output as a live subview, for the modes that display content.
    ///
    /// `nil` whenever there is nothing rendered to show: on the public path (which must keep the live
    /// hierarchy empty), and whenever the caller supplied a live `protectedContentView` instead.
    private var renderedContentHost: UIImageView?

    /// The size the render closure last produced content at, so a size change re-rasterises.
    ///
    /// Shared by both render-closure consumers — the display layer on the public path and the hosted
    /// picture everywhere else — because they need the same two things from it: a FIRST render once the
    /// shield has a usable size, and a NEW one when that size changes. `.zero` means "no render has
    /// succeeded for the current arrangement yet".
    private var lastRenderedSize: CGSize = .zero

    /// Owns the engaged private-path engine.
    ///
    /// Typed as the protocol, never as the concrete private-API type, so excluding
    /// `ScreenGuardPrivateSecureLayer.swift` leaves this file compiling (docs/api-contract.md §9.4).
    /// The owner is what releases the arrangement from `teardown()` and from `deinit` — see
    /// `ScreenGuardPrivateLayerOwner`.
    private let privateLayerOwner = ScreenGuardPrivateLayerOwner()

    /// Whether a private-path engine is currently engaged.
    ///
    /// Internal rather than public: it exists so the private path's REPORT can be compared against
    /// the engine's own `isEngaged` in a test — a success reported as a failure is the same honesty
    /// defect as a failure reported as a success (review round 1, F2).
    var isPrivateLayerEngaged: Bool { privateLayerOwner.isEngaged }

    /// The iOS 17+ display-scale trait registration, so a scale change re-rasterises.
    ///
    /// Stored as `Any?` because `any UITraitChangeRegistration` is itself iOS 17.0+, so it cannot be
    /// the type of a stored property at an iOS 15 deployment target (`docs/api-contract.md` §7.1).
    private var displayScaleRegistration: Any?

    /// Drives `.periodic` refreshes.
    private var refreshTimer: Timer?

    /// Guards against re-entrant refresh during layout.
    private var isRefreshing = false

    /// The scale of the last rasterisation, so a scale change can force a refresh.
    ///
    /// On iOS 17+ the trait registration below drives this. On iOS 15/16 this is compared in
    /// `layoutSubviews`, which is the non-deprecated route available at that deployment target — the
    /// `traitCollectionDidChange(_:)` override that used to do it is deprecated in iOS 17.0.
    private var lastRasterisationScale: CGFloat = 0

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
        self.requestedStrategy = strategy
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
    public required init?(coder: NSCoder) { fatalError("ScreenGuardShieldView must be created programmatically") }

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
        protectionFailure = nil

        switch strategy {
        case .disabled:
            effectiveStrategy = .disabled
            shieldMode = .disabled
            isProtecting = false
            hasPushedFrame = false

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
                hasPushedFrame = false
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
                hasPushedFrame = false
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
                hasPushedFrame = false
                protectionFailure = nil
            } else {
                // PRIVATE API could not be engaged. Fall back to the LABELLED overlay — never to a
                // silent claim of protection (docs/api-contract.md §9.2).
                effectiveStrategy = .disabled
                shieldMode = .detectionAndOverlayFallback
                isProtecting = false
                hasPushedFrame = false
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

    // MARK: - Refresh

    /// Re-rasterises the protected content. Required after content changes under `.manual`.
    ///
    /// Idempotent and safe to call from `layoutSubviews`, `onAppear`, or a data update.
    public func setNeedsContentRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        refresh()
    }

    // MARK: - Layout

    /// Lays out the engaged mechanism and honours the `.onLayout` refresh policy.
    public override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds

        // The iOS 15/16 route for keeping a pushed frame sharp after a scale change. On iOS 17+ the
        // trait registration in `registerForDisplayScaleChanges()` does this; this check is the
        // non-deprecated alternative for the deployment floor, and is a cheap comparison that no-ops
        // when the scale has not moved. (`traitCollectionDidChange(_:)` — the override this replaced —
        // is deprecated in iOS 17.0 and warned at an iOS 26 deployment target.)
        if effectiveStrategy == .publicPreventsCaptureLayer,
           traitCollection.displayScale > 0,
           traitCollection.displayScale != lastRasterisationScale,
           lastRasterisationScale > 0 {
            refresh()
        }

        // RENDER-CLOSURE REFRESH. A shield whose content arrives as a render closure needs work from
        // this method that a caller-supplied live view does not, and the first case is not an
        // optimisation:
        //
        //   * NO render has succeeded yet for the current arrangement -> try now. The first attempt
        //     happens while the shield is still zero-sized (the SwiftUI bridge sets its renderer before
        //     layout, and `ScreenGuardShieldView(strategy:)` is usually built outside any hierarchy),
        //     so without this retry a `.manual` refresh policy leaves a renderer-fed shield blank
        //     FOREVER. That is the F-R2-1 blank one layer down, and it applied to the public path too.
        //   * a render EXISTS but was produced at a different size -> re-rasterise it, so what is on
        //     screen keeps representing the content it stands for.
        //
        // A renderer that cannot produce anything yet is retried on the next layout pass rather than
        // parked, which is what makes "nothing is being shown" a transient state instead of a silent
        // one. Layout passes do not trigger themselves here, so the retry is bounded.
        if rendersFromRenderer, bounds.width > 1, bounds.height > 1,
           lastRenderedSize != bounds.size {
            refresh()
        }

        if case .onLayout = refreshPolicy {
            refresh()
        }
    }

    /// Whether the content this mode displays comes from `protectedContentRenderer`.
    ///
    /// It is not simply "a renderer is set": the two content sources have a precedence order, and
    /// `layoutSubviews` must agree with it or it either re-renders pointlessly (a live view is the
    /// source, so no render will ever move `lastRenderedSize`) or never renders at all (the renderer is
    /// the source but a live view is also attached, as on the public path).
    private var rendersFromRenderer: Bool {
        guard protectedContentRenderer != nil else { return false }
        // The public path rasterises the renderer when it has one — see `renderProtectedContent`.
        if requiresDetachedContent { return true }
        // Every other mode prefers a caller-supplied live view.
        return protectedContentView == nil
    }

    /// Registers for display-scale changes on iOS 17+, where `traitCollectionDidChange(_:)` is
    /// deprecated.
    ///
    /// The registration is stored as `Any?` because `any UITraitChangeRegistration` is itself
    /// iOS 17.0+, so it cannot be the type of a stored property at an iOS 15 deployment target
    /// (docs/api-contract.md §7.1). The handler is `@MainActor`-isolated via `assumeIsolated`: it is
    /// delivered by UIKit on the main actor, so the assumption is sound here.
    private func registerForDisplayScaleChanges() {
        guard #available(iOS 17.0, *) else { return }
        displayScaleRegistration = registerForTraitChanges([UITraitDisplayScale.self]) {
            (view: ScreenGuardShieldView, _: UITraitCollection) in
            MainActor.assumeIsolated {
                guard view.effectiveStrategy == .publicPreventsCaptureLayer else { return }
                view.refresh()
            }
        }
    }

    // MARK: - Public path

    /// Builds the `AVSampleBufferDisplayLayer`, engages `preventsCapture`, and pushes a first frame.
    ///
    /// - Returns: `true` when the layer was created and is available for rendering.
    private func engagePublicPath() -> Bool {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resize
        layer.frame = bounds
        // `preventsCapture` is the whole point of this strategy. It is iOS 13.0+ and NOT deprecated.
        layer.preventsCapture = true
        self.layer.addSublayer(layer)
        displayLayer = layer
        hasPushedFrame = false
        refresh()
        return true
    }

    /// Renders the protected content and pushes it into the display layer.
    private func refresh() {
        switch effectiveStrategy {
        case .publicPreventsCaptureLayer:
            guard let displayLayer else { return }
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
            guard bounds.width > 1, bounds.height > 1 else { return }
            guard let image = renderProtectedContent(scale: scale),
                  let cgImage = image.cgImage else { return }
            lastRasterisationScale = scale
            lastRenderedSize = bounds.size
            // Drive `hasPushedFrame` from the REAL enqueue result, so "the layer is engaged" and
            // "a protected frame was actually produced" stay distinguishable (review round 1, F8).
            hasPushedFrame = ScreenGuardSampleBufferFactory.enqueue(cgImage, into: displayLayer)

        case .disabled, .privateSecureLayer:
            // Nothing to rasterise INTO A LAYER here, so no frame is pushed. The overlay modes paint
            // the content themselves — including a render closure's output, which
            // `synchronizeContentHosting()` turns into a live subview. The private path hosts it the
            // same way, which is what puts it under the private exclusion (review round 2, F-R2-1).
            hasPushedFrame = false
            synchronizeContentHosting()
        }
    }

    /// Produces the image that goes into the protected layer.
    private func renderProtectedContent(scale: CGFloat) -> UIImage? {
        if let protectedContentRenderer {
            return protectedContentRenderer(bounds.size, scale)
        }
        guard let protectedContentView else { return nil }
        return ScreenGuardContentRasterizer.rasterize(
            protectedContentView,
            size: bounds.size,
            scale: scale
        )
    }

    // MARK: - Where the protected content lives

    /// Whether the current mode requires the protected content to be a **live subview**.
    ///
    /// Only the public path requires the opposite. Every other mode either paints the content itself
    /// (`.disabled`, and the labelled `.detectionAndOverlayFallback`) or hosts it live on purpose
    /// (`.privateSecureLayer`, which needs a live view for the private exclusion to cover it).
    private var requiresDetachedContent: Bool { shieldMode == .publicPreventsCaptureLayer }

    /// Puts the protected content where `shieldMode` requires it: live for the overlay modes, and
    /// **out of the view hierarchy** for the public path.
    ///
    /// The public path's invariant is the important one. A view in the live hierarchy is rendered by
    /// the ordinary capture path, so leaving it there while the public path claims protection makes
    /// the sensitive content appear in a real screenshot while `isProtecting == true` — the exact
    /// failure this package exists to prevent. `teardown()` never used to detach it, so a
    /// `.disabled → .publicPreventsCaptureLayer` switch leaked (review round 1, F1).
    ///
    /// The same invariant covers `renderedContentHost`: a render closure's output is a live subview
    /// too, so it is torn down on the public path — and only there (review round 2, F-R2-1).
    private func synchronizeContentHosting() {
        // THE PUBLIC PATH KEEPS THE LIVE HIERARCHY EMPTY. Whatever the content source is, nothing
        // may be a live subview here while the shield claims protection.
        if requiresDetachedContent {
            protectedContentView?.removeFromSuperview()
            removeRenderedContentHost()
            return
        }

        // A caller-supplied live view always wins over a render closure.
        if let protectedContentView {
            removeRenderedContentHost()
            if protectedContentView.superview !== self {
                hostContentLive(protectedContentView)
            }
            protectedContentView.isHidden = false
            return
        }

        // No live view: the render closure is the only content source there is. Its output becomes a
        // live subview, so the modes whose documented job is to SHOW the content actually do — and,
        // on `.privateSecureLayer`, so the content is inside the view the private swap excludes.
        installRenderedContentHostIfPossible()
    }

    // MARK: - Live content

    /// Adds the protected content as a live subview, pinned to the shield's bounds.
    ///
    /// Used by the modes that deliberately SHOW the content: `.disabled` (debug/layout), the labelled
    /// `.detectionAndOverlayFallback` (which "removes no pixels" and would otherwise be an opaque
    /// black hole), and `.privateSecureLayer` (which hosts the content live so the private exclusion
    /// covers it).
    private func hostContentLive(_ content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Render-closure content

    /// Rasterises `protectedContentRenderer`'s output and hosts it as a live subview.
    ///
    /// WHY THIS EXISTS (review round 2, F-R2-1). The SwiftUI bridge supplies content **only** through
    /// `protectedContentRenderer`, because SwiftUI content is not a `UIView`. The private path hosts a
    /// live view, and the public path's display layer is not engaged on the private strategy — so
    /// without this step the renderer's output reached nothing at all, and
    /// `screenGuardProtected(strategy: .privateSecureLayer)` produced an empty card while reporting
    /// `isProtecting = true`, `shieldMode = .privateSecureLayer` and `protectionFailure = nil`.
    ///
    /// The hosted image is a **live subview**, so it inherits the mode's exclusion: on
    /// `.privateSecureLayer` it sits inside the view the private swap excludes, and on the labelled
    /// fallback it is simply visible content, which is what that mode promises.
    ///
    /// It is never installed on the public path: `synchronizeContentHosting()` returns before calling
    /// this when the mode requires a detached content source, because a live subview is rendered by
    /// the ordinary capture path while the shield claims protection (review round 1, F1).
    ///
    /// Nothing is installed while there is nothing to install: a degenerate size or a renderer that
    /// returns `nil` leaves the shield as it was, and the next refresh tries again. That keeps the
    /// "no frame yet" state honest rather than papering over it with a stretched stale picture.
    private func installRenderedContentHostIfPossible() {
        guard let protectedContentRenderer else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        guard let image = protectedContentRenderer(bounds.size, scale) else { return }

        let host = renderedContentHost ?? makeRenderedContentHost()
        host.image = image
        lastRenderedSize = bounds.size
    }

    /// Builds the live host for a render closure's output and pins it to the shield's bounds.
    ///
    /// `.scaleToFill` rather than an aspect-preserving mode: the picture is rendered at exactly the
    /// shield's size, and `layoutSubviews` re-rasterises whenever that size changes, so there is
    /// nothing to letterbox and a stale frame must not be preserved at the cost of showing the wrong
    /// content.
    private func makeRenderedContentHost() -> UIImageView {
        let host = UIImageView()
        host.contentMode = .scaleToFill
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = false
        host.clipsToBounds = true
        renderedContentHost = host
        hostContentLive(host)
        return host
    }

    /// Removes the render-closure host, if there is one. Idempotent.
    private func removeRenderedContentHost() {
        renderedContentHost?.removeFromSuperview()
        renderedContentHost = nil
        lastRenderedSize = .zero
    }

    // MARK: - Refresh policy

    private func applyRefreshPolicy() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard case .periodic(let interval) = refreshPolicy, interval > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    // MARK: - Teardown

    private func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        // Releases the private-path engine, which restores the layer arrangement it displaced. The
        // owner is what makes this happen from `deinit` too, without assuming the releasing thread is
        // the main actor.
        privateLayerOwner.release()
        displayLayer?.removeFromSuperlayer()
        displayLayer = nil
        lastRasterisationScale = 0
        hasPushedFrame = false
        // DETACH. Whatever happens next, no content may still be a live subview unless the mode that
        // is about to be engaged says so; `apply(strategy:)` re-hosts it when it does.
        protectedContentView?.removeFromSuperview()
        removeRenderedContentHost()
    }

    private func fail(with reason: ScreenGuardProtectionFailure) {
        protectionFailure = reason
        onProtectionFailure?(reason)
    }
}

// MARK: - Window lifecycle

extension ScreenGuardShieldView {

    /// Re-attempts private-path engagement when the shield joins a window.
    ///
    /// The private canvas only exists once UIKit has built the secure field's render hierarchy, which
    /// needs a window — so `init(strategy: .privateSecureLayer)` (and any `apply` before the shield is
    /// in a hierarchy) necessarily records the request rather than satisfying it. This makes the
    /// documented call site work without the host having to know the ordering (review round 1, F9).
    ///
    /// It only ever runs for an **unengaged private request**: the public path needs no window, and
    /// re-applying an engaged strategy would tear down and rebuild a working mechanism.
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil,
              requestedStrategy == .privateSecureLayer,
              !isProtecting else { return }
        // `apply` re-runs the whole sequence, including the detach/host decision, so this cannot
        // leave live content behind on the public path either.
        apply(strategy: .privateSecureLayer)
    }
}

// MARK: - CMSampleBuffer plumbing

/// Turns a `CGImage` into a `CMSampleBuffer` and enqueues it into a display layer.
///
/// Split out so the availability guard around the deprecated pre-iOS-18 `AVSampleBufferDisplayLayer`
/// members lives in exactly one place (docs/api-contract.md §7.2).
@MainActor
enum ScreenGuardSampleBufferFactory {

    /// Enqueues `image` into `layer`, flushing a failed renderer first.
    ///
    /// - Parameters:
    ///   - image: The frame to display.
    ///   - layer: The protected display layer.
    /// - Returns: `true` when a sample buffer was produced and enqueued.
    @discardableResult
    static func enqueue(_ image: CGImage, into layer: AVSampleBufferDisplayLayer) -> Bool {
        guard let buffer = makeSampleBuffer(from: image) else { return false }
        if #available(iOS 17.0, *) {
            // `sampleBufferRenderer` is the modern spelling. The pre-iOS-18 members are hard-
            // deprecated in iOS 18.0, so they are used ONLY in the else branch, which keeps this
            // clean at an iOS 26 deployment target (docs/api-contract.md §7.2).
            let renderer = layer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(buffer)
        } else {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(buffer)
        }
        return true
    }

    /// Builds a `CMSampleBuffer` around a BGRA `CVPixelBuffer` holding `image`.
    ///
    /// - Parameter image: The source frame.
    /// - Returns: A ready sample buffer, or `nil` if the pixel buffer could not be created.
    static func makeSampleBuffer(from image: CGImage) -> CMSampleBuffer? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer),
           let context = CGContext(
               data: base,
               width: width,
               height: height,
               bitsPerComponent: 8,
               bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue
           ) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &format
        ) == noErr, let format else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        return sampleBuffer
    }
}
