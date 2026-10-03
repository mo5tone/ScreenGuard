//
//  ScreenGuardShieldView+Content.swift
//  ScreenGuard
//
//  Where the protected content lives: a live subview, or detached for the public path.
//  Split out of ScreenGuardShieldView.swift to keep that file (and its type body) inside the size
//  limits. Behaviour is unchanged — see the F1 / F-R2-1 notes on each member.
//

import CoreGraphics
import UIKit

extension ScreenGuardShieldView {
    // MARK: - Where the protected content lives

    /// Whether the current mode requires the protected content to be a **live subview**.
    ///
    /// Only the public path requires the opposite. Every other mode either paints the content itself
    /// (`.disabled`, and the labelled `.detectionAndOverlayFallback`) or hosts it live on purpose
    /// (`.privateSecureLayer`, which needs a live view for the private exclusion to cover it).
    var requiresDetachedContent: Bool {
        shieldMode == .publicPreventsCaptureLayer
    }

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
    func synchronizeContentHosting() {
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
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        guard let protectedContentRenderer else {
            return
        }
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        guard let image = protectedContentRenderer(bounds.size, scale) else {
            return
        }

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
    func removeRenderedContentHost() {
        renderedContentHost?.removeFromSuperview()
        renderedContentHost = nil
        lastRenderedSize = .zero
    }

    /// Whether a private-path engine is currently engaged.
    ///
    /// Internal rather than public: it exists so the private path's REPORT can be compared against
    /// the engine's own `isEngaged` in a test — a success reported as a failure is the same honesty
    /// defect as a failure reported as a success (review round 1, F2).
    var isPrivateLayerEngaged: Bool {
        privateLayerOwner.isEngaged
    }
}
