//
//  ScreenGuardModifiers.swift
//  ScreenGuard
//
//  The SwiftUI entry points. See docs/api-contract.md §6.8.
//
//  All modifiers are iOS 15-compatible — no availability guard is required.
//
//  ⚠️ DISPLAY TRAP (docs/api-contract.md §6.9, verified): `ScreenGuardCaptureState`,
//  `ScreenGuardDetectionSource` and `ScreenGuardProtectionFailure` are String-raw-valued and do NOT
//  conform to `CustomStringConvertible`, because conforming does not help: SwiftUI's
//  `Text("\(value)")` uses `LocalizedStringKey.StringInterpolation`, and interpolating a non-String
//  produces a DEPRECATION ERROR at an iOS 15 deployment target. Display these values through
//  `.rawValue` (or an explicit `String`), never by bare interpolation.
//

import SwiftUI

// MARK: - Protected content

public extension View {

    /// Marks this view's content as sensitive and shields it from leaking into captures.
    ///
    /// SwiftUI content is not a `UIView`, so this modifier hands the shield a **render closure** and
    /// the content is rasterised on **every** strategy: it is a refreshed snapshot, not a live view
    /// (iOS 16+ renders it with `ImageRenderer`; iOS 15 lays it out in a detached
    /// `UIHostingController`). `refreshPolicy` — or an explicit `setNeedsContentRefresh()` — is what
    /// keeps it current. For content that must stay genuinely live, give `ScreenGuardShieldView` a
    /// `protectedContentView` instead; a live view is the only source the shield does not rasterise.
    ///
    /// With `.publicPreventsCaptureLayer` (default) the rendered image is pushed into the protected
    /// display layer. With `.privateSecureLayer` it is hosted as a **live subview inside the shield**,
    /// which is what places it under the private exclusion — the private API and App Review risk of
    /// `docs/api-contract.md` §9 apply, and it is never a security guarantee.
    ///
    /// - Important: The public path is **DEVICE-PENDING**. On Simulator the protected region paints
    ///   nothing at all, on screen included. That is fail-closed and expected, not a leak.
    ///
    /// - Parameters:
    ///   - strategy: The no-leak mechanism. Default `.publicPreventsCaptureLayer`.
    ///   - refreshPolicy: How often the protected content is re-rasterised. Default `.manual`.
    ///   - onProtectionFailure: Called when the mechanism could not be engaged, so the caller can
    ///     surface the degraded state instead of believing the content is protected.
    /// - Returns: A view whose content is shielded.
    func screenGuardProtected(
        strategy: ScreenGuardNoLeakStrategy = .publicPreventsCaptureLayer,
        refreshPolicy: ScreenGuardRefreshPolicy = .manual,
        onProtectionFailure: ((ScreenGuardProtectionFailure) -> Void)? = nil
    ) -> some View {
        ScreenGuardProtectedView(
            content: self,
            strategy: strategy,
            refreshPolicy: refreshPolicy,
            onProtectionFailure: onProtectionFailure
        )
    }
}

/// Wraps content in a `ScreenGuardShieldView`.
///
/// ⚠️ WHY THIS IS A WRAPPER VIEW AND NOT A `ViewModifier` — measured, not stylistic.
///
/// The rasteriser needs the content as a **value**. A `ViewModifier`'s `body(content:)` hands back a
/// `_ViewModifier_Content` placeholder, and that placeholder does not render on its own: fed to
/// `ImageRenderer` it produces NO image at all. Measured in the iOS 26.2 Simulator test host
/// (round-3 repair):
///
/// ```
/// DIAG 1  ViewModifier's own `content`  -> ImageRenderer.uiImage != nil : false
/// DIAG 2  wrapper view's STORED content -> ImageRenderer.uiImage != nil : true
/// DIAG 5  the package's modifier: renderer(bounds.size, 2) -> nil
/// ```
///
/// The consequence was not subtle: `protectedContentRenderer` returned `nil` on **every** strategy,
/// for every size, at every scale, so the shield had nothing to show anywhere. On the default public
/// path that was invisible on Simulator — `preventsCapture = true` already makes that layer paint
/// nothing there (`docs/TOOLING.md` §7.1) — which is how a second, independent defect hid behind a
/// documented confound. Storing the content as a stored property of a real `View` is what makes the
/// rasteriser work.
struct ScreenGuardProtectedView<ProtectedContent: View>: View {

    /// The content to protect. A STORED value, not a modifier placeholder — see the type note.
    let content: ProtectedContent

    let strategy: ScreenGuardNoLeakStrategy
    let refreshPolicy: ScreenGuardRefreshPolicy
    let onProtectionFailure: ((ScreenGuardProtectionFailure) -> Void)?

    var body: some View {
        ScreenGuardShieldRepresentable(
            strategy: strategy,
            refreshPolicy: refreshPolicy,
            onProtectionFailure: onProtectionFailure
        ) { size, scale in
            // Rasterise the SwiftUI content itself. SwiftUI content has no `UIView`, so this closure
            // is the shield's only content source on this route: the public path pushes its output
            // into the protected display layer, and every other mode hosts it as a live subview
            // (review round 2, F-R2-1 — it used to reach neither).
            ScreenGuardSwiftUIRasterizer.image(of: content, size: size, scale: scale)
        }
        // The shield must not be allowed to size itself; it takes the content's size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rasterises SwiftUI content into a `UIImage` for the protected layer.
///
/// Two implementations, because the good one is iOS 16+:
///
/// | OS | Mechanism |
/// |---|---|
/// | iOS 16.0+ | `ImageRenderer` — the supported, layout-accurate route. |
/// | iOS 15 | `UIHostingController` laid out off-hierarchy, rasterised by `ScreenGuardContentRasterizer`. |
///
/// The iOS 15 path exists because the package's deployment floor is iOS 15 and refusing to protect
/// SwiftUI content there would be a silent hole. It is a best-effort layout: a detached hosting view
/// has no window, so SwiftUI resolves its own sizing rather than inheriting it.
@MainActor
enum ScreenGuardSwiftUIRasterizer {

    /// Renders `content` at `size` and `scale`.
    ///
    /// - Parameters:
    ///   - content: The SwiftUI content to render.
    ///   - size: The target size in points.
    ///   - scale: The target scale.
    /// - Returns: The rendered image, or `nil` when `size` is degenerate.
    static func image<Content: View>(of content: Content, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }

        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(size)
            return renderer.uiImage
        }

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        return ScreenGuardContentRasterizer.rasterize(host.view, size: size, scale: scale)
    }
}

/// The UIKit bridge behind `screenGuardProtected(strategy:refreshPolicy:)`.
private struct ScreenGuardShieldRepresentable: UIViewRepresentable {

    let strategy: ScreenGuardNoLeakStrategy
    let refreshPolicy: ScreenGuardRefreshPolicy
    let onProtectionFailure: ((ScreenGuardProtectionFailure) -> Void)?
    let renderer: (CGSize, CGFloat) -> UIImage?

    func makeUIView(context: Context) -> ScreenGuardShieldView {
        let shield = ScreenGuardShieldView(strategy: strategy)
        shield.refreshPolicy = refreshPolicy
        shield.protectedContentRenderer = renderer
        shield.onProtectionFailure = onProtectionFailure
        return shield
    }

    func updateUIView(_ uiView: ScreenGuardShieldView, context: Context) {
        if uiView.requestedStrategy != strategy {
            uiView.apply(strategy: strategy)
        }
        uiView.refreshPolicy = refreshPolicy
        uiView.protectedContentRenderer = renderer
        uiView.onProtectionFailure = onProtectionFailure
        uiView.setNeedsContentRefresh()
    }
}

// MARK: - Watermark

public extension View {

    /// Overlays a tiled forensic watermark.
    ///
    /// **DETERRENT AND FORENSIC ONLY — removes no pixels.** It makes a leak attributable; it protects
    /// nothing and stops nothing. See `docs/api-contract.md` §3.3.
    ///
    /// - Parameter configuration: The mark's appearance and content.
    /// - Returns: This view with the watermark overlaid.
    func screenGuardWatermarked(_ configuration: ScreenGuardWatermarkConfiguration) -> some View {
        overlay(
            ScreenGuardWatermarkRepresentable(configuration: configuration)
                .allowsHitTesting(false)
        )
    }
}

/// The UIKit bridge behind `screenGuardWatermarked(_:)`.
private struct ScreenGuardWatermarkRepresentable: UIViewRepresentable {

    let configuration: ScreenGuardWatermarkConfiguration

    func makeUIView(context: Context) -> ScreenGuardWatermarkView {
        ScreenGuardWatermarkView(configuration: configuration)
    }

    func updateUIView(_ uiView: ScreenGuardWatermarkView, context: Context) {
        uiView.configuration = configuration
        uiView.refresh()
    }
}

// MARK: - App-switcher cover

public extension View {

    /// Covers this view (or the window) while the scene is inactive, protecting the app-switcher
    /// snapshot.
    ///
    /// ⚠️ **DEVICE-PENDING** — see `docs/api-contract.md` §3.4. Snapshot pixels cannot be decoded on
    /// Simulator.
    ///
    /// SwiftUI's own `privacySensitive()` is the system-supported, zero-configuration alternative and
    /// is worth preferring where it is sufficient.
    ///
    /// - Parameter style: What to show in place of the content.
    /// - Returns: This view with an app-switcher cover attached.
    func screenGuardAppSwitcherProtected(
        style: ScreenGuardAppSwitcherStyle = .blur(style: .systemMaterial)
    ) -> some View {
        modifier(ScreenGuardAppSwitcherModifier(style: style))
    }
}

/// Observes scene phase and covers its content while the scene is inactive.
struct ScreenGuardAppSwitcherModifier: ViewModifier {

    let style: ScreenGuardAppSwitcherStyle

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                // `scenePhase` is the SwiftUI-side signal; the UIKit shield is what covers a window
                // when the host uses `ScreenGuardAppSwitcherShield` directly. Both are offered.
                if scenePhase != .active {
                    ScreenGuardAppSwitcherCoverRepresentable(style: style)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Renders the cover for the SwiftUI modifier.
private struct ScreenGuardAppSwitcherCoverRepresentable: UIViewRepresentable {

    let style: ScreenGuardAppSwitcherStyle

    func makeUIView(context: Context) -> ScreenGuardAppSwitcherShield {
        let shield = ScreenGuardAppSwitcherShield(style: style)
        shield.coverNow()
        return shield
    }

    func updateUIView(_ uiView: ScreenGuardAppSwitcherShield, context: Context) {
        uiView.style = style
        uiView.coverNow()
    }
}
