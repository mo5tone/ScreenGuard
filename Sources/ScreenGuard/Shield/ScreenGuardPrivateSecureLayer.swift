//
//  ScreenGuardPrivateSecureLayer.swift
//  ScreenGuard
//
//  ============================================================================================
//  ⚠️  THIS FILE DEPENDS ON A PRIVATE UIKit CLASS NAME. IT IS NOT CONTRACT.
//  ============================================================================================
//
//  * It matches the private class `_UITextLayoutCanvasView` — the canvas UIKit uses to keep a secure
//    text field's content out of captures. That name is **not documented, not contract, and not
//    stable**: Apple may rename, restructure or remove it in any iOS release, at which point this
//    protection silently stops working. The engine therefore reports
//    `ScreenGuardProtectionFailure.privateSecureLayerUnavailable` instead of pretending.
//  * It carries **App Review risk**. Using a private API can cause App Review rejection and, in the
//    worst case, removal from the App Store.
//  * App Review exposure is a **COMPILE-TIME** property, not a runtime one: the class name is matched
//    by string, so the literal is present in the compiled binary regardless of whether the opt-in is
//    ever granted. Enabling it at runtime does not add exposure; leaving it off does not remove it.
//  * It is **OFF BY DEFAULT** and is never a security guarantee. It must never be described as
//    secure, guaranteed, safe, recommended, production-ready, or App-Store-safe
//    (docs/api-contract.md §9.5).
//
//  ESCAPE HATCH (how a consumer keeps the string out of their binary)
//  ----------------------------------------------------------------
//  This file is compiled ONLY when the `PrivateAPI` package trait is enabled. The trait is not in
//  `default(enabledTraits:)`, so by default the private code — and therefore this class-name
//  literal — is not compiled at all. A consumer opts IN from their own manifest, with no fork:
//
//      .package(url: "…/ScreenGuard.git", from: "1.0.0", traits: ["PrivateAPI"])
//
//  `Package.swift` wires the trait to the define that guards this file:
//
//      .define("SCREENGUARD_PRIVATE_API", .when(traits: ["PrivateAPI"]))
//
//  With the trait absent, `ScreenGuardNoLeakStrategy.privateSecureLayer` degrades to the labelled
//  detection-and-overlay fallback with `protectionFailure = .privateSecureLayerUnavailable`
//  (docs/api-contract.md §9.4). This is why the private code lives in exactly one file.
//
//  Author-side only: a fork / vendored checkout / CI build may ALSO exclude this file, but only while
//  the trait is off. That mechanism is not available to a normal SPM consumer, because `exclude:`
//  exists only on a package's own target declarations.
//
//  WHY IT EXISTS AT ALL
//  --------------------
//  Measured, it is the ONLY mechanism that blanks ARBITRARY content in a capture while still painting
//  it on the display: sentinel (200,0,160) in `drawHierarchy` while the host display capture reads
//  the real colour (38,102,242), with the swap-disabled control band leaking on both paths
//  (docs/evidence/capability-matrix.md §3 rows 4 and 6). That is a real capability, and withholding
//  it would be dishonest in the other direction — so it is offered, off by default, clearly labelled.
//

import UIKit

#if SCREENGUARD_PRIVATE_API

/// Reparents a view's layer into a private `_UITextLayoutCanvasView` descendant, so the view's
/// content is excluded from the render-server-backed capture read while still painting on the
/// display.
///
/// Not public API: reachable only through
/// `ScreenGuardNoLeakStrategy.privateSecureLayer`, which is opt-in and off by default.
///
/// - Warning: Private API. Non-contract. Fragile across iOS releases. App Review risk. Never a
///   security guarantee. Read `docs/api-contract.md` §9 before enabling.
@MainActor
final class ScreenGuardPrivateSecureLayer: ScreenGuardPrivateSecureLayerEngaging {

    /// The private class-name fragment matched at runtime. The literal lives in this file and
    /// nowhere else, so excluding this file removes it from the binary.
    private static let canvasClassNameFragment = "_UITextLayoutCanvasView"

    /// Whether a caller has explicitly opted in at runtime. `false` by default.
    ///
    /// Naming `ScreenGuardNoLeakStrategy.privateSecureLayer` is not sufficient on its own: the caller
    /// must also set `ScreenGuard.PrivateAPI.isEnabled`. Two explicit acts are required for a private
    /// API, and the default posture is "off".
    private static var isOptedIn: Bool { ScreenGuard.PrivateAPI.isEnabled }

    // MARK: - Instance state

    /// Why engagement failed, when it did.
    private(set) var failure: ScreenGuardProtectionFailure?

    /// The hidden secure text field whose canvas hosts the protected layer.
    private var hostField: UITextField?

    /// The layer that was in the canvas before the swap, restored on `disengage()`.
    private var displacedCanvasLayer: CALayer?

    /// The canvas whose layer was replaced.
    private weak var canvas: UIView?

    /// The view whose layer was reparented.
    private weak var protectedHost: UIView?

    /// Whether the swap is currently applied.
    private(set) var isEngaged = false

    // MARK: - Engage

    /// Engages the swap for `host`.
    ///
    /// - Parameter host: The view whose content must be excluded from captures.
    /// - Returns: `true` when the swap was applied; `false` when it could not be, with `failure` set.
    func engage(on host: UIView) -> Bool {
        guard Self.isOptedIn else {
            // OFF BY DEFAULT. This is the normal, expected result for a caller that named the
            // strategy without opting in.
            failure = .privateSecureLayerUnavailable
            return false
        }
        guard host.window != nil else {
            // The canvas only exists once UIKit has built the field's render hierarchy, which needs a
            // window. Report rather than silently do nothing.
            failure = .privateSecureLayerSwapFailed
            return false
        }

        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            field.topAnchor.constraint(equalTo: host.topAnchor),
            field.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        host.layoutIfNeeded()

        guard let canvas = Self.findCanvas(in: field) else {
            // The private class name is gone on this OS build. Do NOT claim protection.
            field.removeFromSuperview()
            failure = .privateSecureLayerUnavailable
            return false
        }

        let displaced = canvas.layer
        let hostLayer = host.layer
        // The measured sequence, reproduced exactly: park the protected layer in the canvas, toggle
        // secure entry so UIKit rebuilds its exclusion bookkeeping around it, then put the canvas's own
        // layer back. See docs/evidence/capability-matrix.md §3 row 4.
        canvas.setValue(hostLayer, forKey: "layer")
        field.isSecureTextEntry = false
        field.isSecureTextEntry = true
        canvas.setValue(displaced, forKey: "layer")

        // VERIFY WHAT THE SEQUENCE ACTUALLY ESTABLISHES — and nothing more.
        //
        // The research harness checked `canvas.layer === host.layer` immediately after the swap and
        // BEFORE its restore, then only recorded `swapApplied = true`. A postcondition placed after
        // the restore can therefore never be satisfied: measured, `canvas.layer` is `displaced` again
        // by then, so that check was unreachable and the shield denied a capability it was in fact
        // delivering (review round 1, F2).
        //
        // What IS checkable here, and can genuinely fail, is that the sequence ran and left the layer
        // arrangement intact:
        //   * the canvas is back on its own layer (the restore happened);
        //   * the host still owns its original layer;
        //   * that layer is still attached to a superlayer (CoreAnimation did not orphan it).
        //
        // What is deliberately NOT asserted, because it cannot be: that the pixels are now excluded
        // from a capture. Capture exclusion is render-server state and is not observable in-process —
        // it is established by measurement (sentinel `200,0,160` in `drawHierarchy` while the display
        // shows `38,102,242`, docs/evidence/capability-matrix.md §3 rows 4 and 6) and re-checked end to
        // end by the example app's pixel probe. Asserting it here would be a guess dressed as a check.
        guard canvas.layer === displaced,
              host.layer === hostLayer,
              hostLayer.superlayer != nil else {
            canvas.setValue(displaced, forKey: "layer")
            field.removeFromSuperview()
            failure = .privateSecureLayerSwapFailed
            return false
        }

        hostField = field
        displacedCanvasLayer = displaced
        self.canvas = canvas
        protectedHost = host
        isEngaged = true
        failure = nil
        return true
    }

    /// Restores the canvas and removes the hidden field. Idempotent.
    func disengage() {
        if let canvas, let displacedCanvasLayer {
            canvas.setValue(displacedCanvasLayer, forKey: "layer")
        }
        hostField?.removeFromSuperview()
        hostField = nil
        displacedCanvasLayer = nil
        canvas = nil
        protectedHost = nil
        isEngaged = false
    }

    // MARK: - Private helpers

    /// Recursive, because the canvas is not guaranteed to be a direct subview.
    private static func findCanvas(in view: UIView) -> UIView? {
        for subview in view.subviews {
            if NSStringFromClass(type(of: subview)).contains(canvasClassNameFragment) { return subview }
            if let found = findCanvas(in: subview) { return found }
        }
        return nil
    }
}

/// The factory the shield uses. This definition exists only when the private file is compiled in;
/// its counterpart in `ScreenGuardPrivateSecureLayerSupport.swift` covers the excluded case.
@MainActor
enum ScreenGuardPrivateSecureLayerFactory {

    /// Whether the private path is compiled into this build at all.
    static let isCompiledIn = true

    /// Builds the private-path engine.
    ///
    /// - Returns: A new engine. Whether it can *engage* is decided by `engage(on:)`, which checks the
    ///   runtime opt-in and the presence of the private canvas class.
    static func make() -> (any ScreenGuardPrivateSecureLayerEngaging)? {
        ScreenGuardPrivateSecureLayer()
    }
}

#endif
