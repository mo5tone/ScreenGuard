//
//  ScreenGuardShieldView+Refresh.swift
//  ScreenGuard
//
//  Rasterisation, refresh policy and teardown for ScreenGuardShieldView.
//  Split out of ScreenGuardShieldView.swift to keep that file (and its type body) inside the size
//  limits. Behaviour is unchanged. Members shared across these files are internal because Swift
//  private is file-scoped.
//

import AVFoundation
import CoreGraphics
import UIKit

extension ScreenGuardShieldView {
    /// Whether the content this mode displays comes from `protectedContentRenderer`.
    ///
    /// It is not simply "a renderer is set": the two content sources have a precedence order, and
    /// `layoutSubviews` must agree with it or it either re-renders pointlessly (a live view is the
    /// source, so no render will ever move `lastRenderedSize`) or never renders at all (the renderer is
    /// the source but a live view is also attached, as on the public path).
    var rendersFromRenderer: Bool {
        guard protectedContentRenderer != nil else {
            return false
        }
        // The public path rasterises the renderer when it has one — see `renderProtectedContent`.
        if requiresDetachedContent {
            return true
        }
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
    func registerForDisplayScaleChanges() {
        guard #available(iOS 17.0, *) else {
            return
        }
        let handleScaleChange: (ScreenGuardShieldView, UITraitCollection) -> Void = { view, _ in
            MainActor.assumeIsolated { view.refreshIfDisplayScaleChanged() }
        }
        displayScaleRegistration = registerForTraitChanges(
            [UITraitDisplayScale.self],
            handler: handleScaleChange
        )
    }

    /// Re-renders for a display-scale change, for the strategies that rasterise content in-process.
    ///
    /// Extracted from the trait handler so the handler needs no explicit parameter types: spelling out
    /// (view: ScreenGuardShieldView, _: UITraitCollection) puts the parameters on a line of their own,
    /// which the line limit leaves no room for.
    private func refreshIfDisplayScaleChanged() {
        guard effectiveStrategy == .publicPreventsCaptureLayer else {
            return
        }
        refresh()
    }

    // MARK: - Public path

    /// Builds the `AVSampleBufferDisplayLayer`, engages `preventsCapture`, and pushes a first frame.
    ///
    /// - Returns: `true` when the layer was created and is available for rendering.
    func engagePublicPath() -> Bool {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resize
        layer.frame = bounds
        // `preventsCapture` is the whole point of this strategy. It is iOS 13.0+ and NOT deprecated.
        layer.preventsCapture = true
        self.layer.addSublayer(layer)
        displayLayer = layer
        recordPushedFrame(false)
        refresh()
        return true
    }

    /// Renders the protected content and pushes it into the display layer.
    func refresh() {
        switch effectiveStrategy {
        case .publicPreventsCaptureLayer:
            guard let displayLayer else {
                return
            }
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
            guard bounds.width > 1, bounds.height > 1 else {
                return
            }
            guard let image = renderProtectedContent(scale: scale),
                  let cgImage = image.cgImage
            else {
                return
            }
            lastRasterisationScale = scale
            lastRenderedSize = bounds.size
            // Drive `hasPushedFrame` from the REAL enqueue result, so "the layer is engaged" and
            // "a protected frame was actually produced" stay distinguishable (review round 1, F8).
            recordPushedFrame(ScreenGuardSampleBufferFactory.enqueue(cgImage, into: displayLayer))

        case .disabled, .privateSecureLayer:
            // Nothing to rasterise INTO A LAYER here, so no frame is pushed. The overlay modes paint
            // the content themselves — including a render closure's output, which
            // `synchronizeContentHosting()` turns into a live subview. The private path hosts it the
            // same way, which is what puts it under the private exclusion (review round 2, F-R2-1).
            recordPushedFrame(false)
            synchronizeContentHosting()
        }
    }

    /// Produces the image that goes into the protected layer.
    private func renderProtectedContent(scale: CGFloat) -> UIImage? {
        if let protectedContentRenderer {
            return protectedContentRenderer(bounds.size, scale)
        }
        guard let protectedContentView else {
            return nil
        }
        return ScreenGuardContentRasterizer.rasterize(
            protectedContentView,
            size: bounds.size,
            scale: scale
        )
    }

    // MARK: - Refresh policy

    func applyRefreshPolicy() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard case let .periodic(interval) = refreshPolicy, interval > 0 else {
            return
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    // MARK: - Teardown

    func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        // Releases the private-path engine, which restores the layer arrangement it displaced. The
        // owner is what makes this happen from `deinit` too, without assuming the releasing thread is
        // the main actor.
        privateLayerOwner.release()
        displayLayer?.removeFromSuperlayer()
        displayLayer = nil
        lastRasterisationScale = 0
        recordPushedFrame(false)
        // DETACH. Whatever happens next, no content may still be a live subview unless the mode that
        // is about to be engaged says so; `apply(strategy:)` re-hosts it when it does.
        protectedContentView?.removeFromSuperview()
        removeRenderedContentHost()
    }

    func fail(with reason: ScreenGuardProtectionFailure) {
        recordProtectionFailure(reason)
        onProtectionFailure?(reason)
    }

    // MARK: - Refresh

    /// Re-rasterises the protected content. Required after content changes under `.manual`.
    ///
    /// Idempotent and safe to call from `layoutSubviews`, `onAppear`, or a data update.
    public func setNeedsContentRefresh() {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        refresh()
    }

    /// Lays out the engaged mechanism and honours the .onLayout refresh policy.
    ///
    /// Split out of layoutSubviews() so that override stays in the class body (an override in an
    /// extension in another file is itself a lint violation) while this file stays inside the size
    /// limit. Same statements, same order.
    func layoutProtectedContent() {
        displayLayer?.frame = bounds

        if needsDisplayScaleRefresh {
            refresh()
        }

        if needsRendererRefresh {
            refresh()
        }

        if case .onLayout = refreshPolicy {
            refresh()
        }
    }

    /// Whether a display-scale change means the pushed frame must be rebuilt.
    ///
    /// The iOS 15/16 route for keeping a pushed frame sharp after a scale change. On iOS 17+ the trait
    /// registration in registerForDisplayScaleChanges() does this; this check is the non-deprecated
    /// alternative for the deployment floor, and is a cheap comparison that no-ops when the scale has
    /// not moved. (traitCollectionDidChange(_:) — the override this replaced — is deprecated in
    /// iOS 17.0 and warned at an iOS 26 deployment target.)
    var needsDisplayScaleRefresh: Bool {
        effectiveStrategy == .publicPreventsCaptureLayer
            && traitCollection.displayScale > 0
            && traitCollection.displayScale != lastRasterisationScale
            && lastRasterisationScale > 0
    }

    /// Whether a renderer-fed shield must (re-)render at the current size.
    ///
    /// RENDER-CLOSURE REFRESH. A shield whose content arrives as a render closure needs work from
    /// this method that a caller-supplied live view does not, and the first case is not an
    /// optimisation:
    ///
    ///   * NO render has succeeded yet for the current arrangement -> try now. The first attempt
    ///     happens while the shield is still zero-sized (the SwiftUI bridge sets its renderer before
    ///     layout, and `ScreenGuardShieldView(strategy:)` is usually built outside any hierarchy),
    ///     so without this retry a `.manual` refresh policy leaves a renderer-fed shield blank
    ///     FOREVER. That is the F-R2-1 blank one layer down, and it applied to the public path too.
    ///   * a render EXISTS but was produced at a different size -> re-rasterise it, so what is on
    ///     screen keeps representing the content it stands for.
    ///
    /// A renderer that cannot produce anything yet is retried on the next layout pass rather than
    /// parked, which is what makes "nothing is being shown" a transient state instead of a silent
    /// one. Layout passes do not trigger themselves here, so the retry is bounded.
    var needsRendererRefresh: Bool {
        rendersFromRenderer
            && bounds.width > 1
            && bounds.height > 1
            && lastRenderedSize != bounds.size
    }
}
