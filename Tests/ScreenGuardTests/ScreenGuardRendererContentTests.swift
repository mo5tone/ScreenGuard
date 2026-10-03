//
//  ScreenGuardRendererContentTests.swift
//  ScreenGuardTests
//
//  Regression tests for review round 2, finding **F-R2-1** — the silent blank
//  (`docs/evidence/review-round2.md`, `docs/api-contract.md` §13 A3).
//
//  THE DEFECT, STATED AS AN INVARIANT RATHER THAN AS A ROUTE.
//  `ScreenGuardShieldRepresentable.makeUIView` supplies the shield with content **only** through
//  `protectedContentRenderer`; it never sets `protectedContentView`, because the SwiftUI content does
//  not exist as a `UIView`. Measured by two independent probes (P10, P9), the shield then reported
//  `isProtecting = true` / `shieldMode = .privateSecureLayer` / `protectionFailure = nil` while
//  rendering **nothing at all** — a blank card and no signal.
//
//  So the invariant these tests pin is route-agnostic on purpose:
//
//      a shield that was handed a renderer must never end up showing NOTHING in a mode whose
//      documented job is to show the content, and must never report the private path as engaged
//      while there is no protected content in its hierarchy.
//
//  Both honest repairs satisfy it — consuming the renderer output, or refusing with a reported
//  failure — so this file does not encode which one is chosen. It only rejects silence.
//
//  WHY SOME TESTS SKIP IN THE DEFAULT BUILD: `Package.swift` ships
//  `.default(enabledTraits: [])`, so `xcodebuild test -scheme ScreenGuard` compiles a configuration in
//  which `ScreenGuardPrivateSecureLayer.swift` does not exist and there is no private engine to
//  engage. Those tests SKIP with an explicit reason rather than weakening the assertion; the enabled
//  configuration is exercised in a trait-enabled checkout and, end to end, by
//  `Scripts/verify_capture.sh` (the example app enables the trait).
//

@testable import ScreenGuard
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ScreenGuardRendererContentTests: XCTestCase {
    /// The reason string for tests that need the private-API code compiled in.
    static let privateTraitReason =
        "PRIVATEAPI-REQUIRED: the `PrivateAPI` package trait is not enabled in this build, so the "
            + "private secure-layer engine is not compiled in and cannot be engaged. Run this suite in a "
            + "trait-enabled checkout, or see Scripts/verify_capture.sh (the example app enables the trait)."

    /// The colour the test renderer paints. Equal to the demo's `sensitiveColour`, so the pixel check
    /// below uses the same reference the end-to-end probe uses.
    static let rendererColour = UIColor(red: 38 / 255, green: 102 / 255, blue: 242 / 255, alpha: 1)

    // MARK: - Helpers

    /// A window that behaves like a real hierarchy for `view.window != nil`.
    func makeWindow(width: CGFloat = 320, height: CGFloat = 240) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    /// The shield, built and fed **exactly** the way `ScreenGuardShieldRepresentable.makeUIView` does.
    ///
    /// This is the point of the file: the SwiftUI bridge is `private` to the module, so its call
    /// sequence — `init(strategy:)`, then `protectedContentRenderer = …`, then the view joins a
    /// window — is reproduced verbatim here. `protectedContentView` is never set, because the bridge
    /// has no `UIView` to give.
    ///
    /// - Returns: The shield and a counter of how many times the renderer ran.
    func makeSwiftUIShapedShield(
        strategy: ScreenGuardNoLeakStrategy,
        window: UIWindow
    ) -> (shield: ScreenGuardShieldView, renderCount: () -> Int) {
        var renders = 0
        let shield = ScreenGuardShieldView(strategy: strategy) // makeUIView, line 1
        shield.protectedContentRenderer = { size, scale in // makeUIView, line 2
            renders += 1
            return Self.solidImage(size: size, scale: scale)
        }
        window.rootViewController?.view.addSubview(shield)
        shield.frame = window.bounds
        shield.layoutIfNeeded()
        return (shield, { renders })
    }

    /// A solid `rendererColour` image, the way the SwiftUI bridge's `ImageRenderer` would produce one.
    static func solidImage(size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 1, size.height > 1 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: size), format: format)
            .image { context in
                rendererColour.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
    }

    /// The image the shield is currently DISPLAYING for its renderer, if any.
    ///
    /// Deliberately a property of the live hierarchy rather than of a particular mechanism: the
    /// question F-R2-1 asks is "does anything the user can see carry the rendered content?". Hidden
    /// views do not count — a view the user cannot see is the blank card the finding is about.
    func displayedRendererImage(in shield: ScreenGuardShieldView) -> UIImage? {
        var found: UIImage?
        func walk(_ view: UIView) {
            guard found == nil else {
                return
            }
            if let imageView = view as? UIImageView, let image = imageView.image, !imageView.isHidden {
                found = image
                return
            }
            view.subviews.forEach(walk)
        }
        shield.subviews.forEach(walk)
        return found
    }

    /// One normalised sample of `image` as `(r, g, b)` in 0…255, normalised to RGBA8 first.
    ///
    /// The renderer's output is 16 bits per component, so a raw byte read yields noise
    /// (`docs/TOOLING.md` §5).
    static func pixel(in image: UIImage, at normalizedPoint: CGPoint) -> (Int, Int, Int)? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = bytes.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = min(width - 1, max(0, Int(normalizedPoint.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int(normalizedPoint.y * CGFloat(height))))
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    static func components(_ color: UIColor) -> (Int, Int, Int) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    static func channelDistance(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Int {
        max(abs(lhs.0 - rhs.0), max(abs(lhs.1 - rhs.1), abs(lhs.2 - rhs.2)))
    }

    /// Skips with the documented reason when the private-API code is not compiled into this build.
    func requirePrivateTrait() throws {
        guard ScreenGuard.PrivateAPI.isCompiledIn else {
            throw XCTSkip(Self.privateTraitReason)
        }
    }

    // MARK: - The renderer must reach the screen in the modes whose job is to show content

    /// `.disabled` is documented as "No protection. Content is shown normally. Layout and debugging
    /// only." A renderer-fed shield must therefore show the rendered content.
    ///
    /// RED before the repair: nothing was hosted, so this mode was an opaque black card whatever the
    /// renderer returned. `.disabled` is the cheapest observable statement of the root cause, and it
    /// does not need the private trait.
    func testDisabledStrategyWithARendererShowsTheRenderedContent() throws {
        let window = makeWindow()
        let (shield, renderCount) = makeSwiftUIShapedShield(strategy: .disabled, window: window)

        XCTAssertEqual(shield.shieldMode, .disabled)
        XCTAssertGreaterThan(
            renderCount(), 0,
            "a shield with a renderer and no live view must call the renderer at all — before the "
                + "repair it never did, so nothing could ever be shown"
        )

        let image = try XCTUnwrap(
            displayedRendererImage(in: shield),
            "`.disabled` must show the rendered content; showing nothing is the F-R2-1 blank"
        )
        let centre = try XCTUnwrap(Self.pixel(in: image, at: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertLessThan(
            Self.channelDistance(centre, Self.components(Self.rendererColour)),
            24,
            "the hosted image must carry the RENDERER's output (read \(centre)), not just any image"
        )
    }

    /// The labelled fallback is documented as showing the content it cannot protect: "The shield then
    /// shows the content as a plain visual overlay — which removes no pixels from any capture, and
    /// says so."
    ///
    /// A shield that refuses to protect and then shows nothing is a black hole with a failure code
    /// attached — strictly worse than the labelled overlay it is supposed to be, and it is what the
    /// SwiftUI route did whenever the private path could not engage.
    ///
    /// RED before the repair, and it needs no trait: with the trait off, `.privateSecureLayer`
    /// degrades to exactly this mode.
    func testLabelledFallbackWithARendererShowsTheRenderedContent() throws {
        let window = makeWindow()
        let (shield, _) = makeSwiftUIShapedShield(strategy: .privateSecureLayer, window: window)

        XCTAssertFalse(shield.isProtecting, "the private path cannot engage in this configuration")
        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertNotNil(
            shield.protectionFailure,
            "and it must SAY so — the failure signal is the half of F-R2-1 the package did deliver"
        )

        let image = try XCTUnwrap(
            displayedRendererImage(in: shield),
            "the labelled fallback must SHOW the content it cannot protect; showing nothing makes the "
                + "degraded state indistinguishable from an opaque cover"
        )
        let centre = try XCTUnwrap(Self.pixel(in: image, at: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertLessThan(Self.channelDistance(centre, Self.components(Self.rendererColour)), 24)
    }

    /// The SwiftUI route, with the private path actually engaged.
    ///
    /// RED before the repair: the shield reported the private path as engaged and the region was
    /// blank. This is the exact state probe P10 measured (`isProtecting = true`,
    /// `mode = privateSecureLayer`, `failure = nil`, `contentView = nil`).
    func testPrivateStrategyWithARendererHostsTheRenderedContent() throws {
        try requirePrivateTrait()

        let window = makeWindow()
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let (shield, renderCount) = makeSwiftUIShapedShield(strategy: .privateSecureLayer, window: window)
        shield.layoutIfNeeded()

        XCTAssertTrue(
            shield.isProtecting,
            "the private engine must still engage — got \(String(describing: shield.protectionFailure))"
        )
        XCTAssertEqual(shield.shieldMode, .privateSecureLayer)
        XCTAssertGreaterThan(renderCount(), 0, "the renderer is the shield's only content source here")

        let image = try XCTUnwrap(
            displayedRendererImage(in: shield),
            "a shield that reports `.privateSecureLayer` and `isProtecting` while hosting no content is "
                + "the F-R2-1 defect: it claims protection over a region that was never painted"
        )
        let centre = try XCTUnwrap(Self.pixel(in: image, at: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertLessThan(Self.channelDistance(centre, Self.components(Self.rendererColour)), 24)
    }

    /// The invariant, stated directly and independently of the route chosen: reporting the private
    /// path as ENGAGED while nothing is displayed is the lie, whether or not the content is later
    /// hosted. A repair that refuses instead of hosting satisfies this test too.
    func testPrivateStrategyWithARendererNeverClaimsProtectionOverNothing() throws {
        try requirePrivateTrait()

        let window = makeWindow()
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let (shield, _) = makeSwiftUIShapedShield(strategy: .privateSecureLayer, window: window)
        shield.layoutIfNeeded()

        let claimsPrivateProtection =
            shield.isProtecting && shield.shieldMode == .privateSecureLayer
        let showsSomething = displayedRendererImage(in: shield) != nil

        XCTAssertFalse(
            claimsPrivateProtection && !showsSomething,
            "the shield reports isProtecting=true / mode=privateSecureLayer while its hierarchy "
                + "contains no content at all — a silent blank with a success claim on top "
                + "(review round 2, F-R2-1)"
        )
        if !claimsPrivateProtection {
            XCTAssertNotNil(
                shield.protectionFailure,
                "refusing is an acceptable answer; refusing SILENTLY is not"
            )
        }
    }

    // MARK: - The guard: the repair must not put live content on the public path

    /// The public path's invariant (review round 1, F1): a view in the live hierarchy is rendered by
    /// the ordinary capture path, so the protected content must NOT be a live subview while the
    /// public path claims protection.
    ///
    /// This is the "no new leak surface" guard for any repair that hosts renderer output live: the
    /// hosting must be torn down on the switch to `.publicPreventsCaptureLayer`, exactly as the
    /// caller-supplied live view already is. It is written in two halves so that it cannot pass
    /// vacuously — the content must be shown FIRST, and gone after.
    func testSwitchingToThePublicPathRemovesRendererBackedContent() {
        let window = makeWindow()
        let (shield, _) = makeSwiftUIShapedShield(strategy: .disabled, window: window)

        XCTAssertNotNil(
            displayedRendererImage(in: shield),
            "precondition: a showing mode hosts the rendered content, so the assertion below can "
                + "actually fail if the public path leaves it behind"
        )

        shield.apply(strategy: .publicPreventsCaptureLayer)
        shield.layoutIfNeeded()

        XCTAssertTrue(shield.isProtecting, "the public path must engage")
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
        XCTAssertNil(
            displayedRendererImage(in: shield),
            "renderer-backed content is still a LIVE SUBVIEW while the public path claims protection "
                + "— that is the F1 leak, and a real capture would render it"
        )
    }
}
