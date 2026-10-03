//
//  ScreenGuardContentRasterizer.swift
//  ScreenGuard
//
//  Renders a protected content view to an image, for the public path's
//  `CMSampleBuffer → AVSampleBufferDisplayLayer` pipeline.
//
//  WHY THIS USES `CALayer.render(in:)` AND NOT `drawHierarchy`
//  ---------------------------------------------------------
//  `docs/TOOLING.md` §7.2 records that `CALayer.render(in:)` is NOT a valid substitute for
//  `drawHierarchy` when *MEASURING* protection: it walks the layer tree directly, never goes through
//  the render server, and therefore does not honour capture exclusion. That rule governs capture
//  readback, and this file never does capture readback.
//
//  Here the direction is the opposite: the app renders its OWN content into an image so it can push
//  it into the protected display layer. The content view is deliberately kept OUT of the live
//  hierarchy on the public path — anything in the live hierarchy leaks into captures, which is
//  precisely the limitation of the public path — and a view that is not in a window has no
//  render-server content for `drawHierarchy` to hand back.
//
//  Measured on iPhone 17 Pro / iOS 26.2 Simulator while writing this file (Xcode 27.0):
//
//    * `drawHierarchy(afterScreenUpdates: false)` on a detached view → `(0,0,0)` at both sample
//      points; it draws NOTHING.
//    * `drawHierarchy(afterScreenUpdates: false)` on a view attached to a `UIWindow` that is not in a
//      scene (`windowScene == nil`) → also `(0,0,0)`; it still draws nothing.
//    * `CALayer.render(in:)` on the same detached view → the correct colours.
//
//  So `drawHierarchy` cannot serve this purpose, and `layer.render` can. The orientation is asserted
//  by `ScreenGuardRasterizerTests` rather than trusted, because the y-flip is exactly the class of slip
//  that produced a reported `50.87` where the truth was `3.77` in the research harness
//  (`docs/TOOLING.md` §7.2).
//
//  ORIENTATION, STATED AND MEASURED
//  --------------------------------
//  `CALayer.render(in:)` documents a Quartz (y-up) context, which would suggest a flip before drawing
//  into the y-down context `UIGraphicsImageRenderer` provides. Measured, a flip INVERTS the result:
//  with a flip, a view whose top half is red renders red at the bottom; without a flip, the
//  orientation is correct. The flip is therefore deliberately absent — verified, not assumed.
//
//  WHAT THIS COSTS
//  ---------------
//  `layer.render` does not resolve `UIVisualEffectView` blur, and it bypasses the render server. The
//  consequence for the public path is that the rasterised snapshot is a plain layer-tree render of the
//  app's own content. That is acceptable *for producing* the protected frame — the frame is then
//  handed to the display layer, which is what excludes it from captures. It would NOT be acceptable as
//  a way to verify protection, which is why this file is not used for that anywhere in the package.
//

import CoreGraphics
import UIKit

/// Rasterises a view into a `UIImage` for the protected display layer.
///
/// Not public API: an internal detail of `ScreenGuardShieldView`.
@MainActor
enum ScreenGuardContentRasterizer {
    /// Renders `view` at `size` and `scale`.
    ///
    /// The view is expected to be **detached** from the live hierarchy on the public path, and this
    /// method adopts the requested geometry so an unlaid-out view still renders correctly.
    ///
    /// - Parameters:
    ///   - view: The content view. May be detached from any window.
    ///   - size: The target size in points.
    ///   - scale: The target scale (typically `UITraitCollection.displayScale`).
    /// - Returns: The rendered image, or `nil` when `size` is degenerate.
    static func rasterize(_ view: UIView, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 1, size.height > 1 else {
            return nil
        }

        // A detached view is never laid out by UIKit, so give it the target geometry explicitly. This
        // is what makes an off-hierarchy rasterisation possible at all.
        if view.bounds.size != size {
            view.bounds = CGRect(origin: .zero, size: size)
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale > 0 ? scale : 2
        format.opaque = true

        let bounds = CGRect(origin: .zero, size: size)
        // NOTE: this renderer's output is 16 bpc / 64 bpp. That is harmless here because the image is
        // handed straight to CoreGraphics; it only bites when raw bytes are read (docs/TOOLING.md §5).
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            // NO y-flip — measured, see the type-level note.
            view.layer.render(in: context.cgContext)
        }
    }
}
