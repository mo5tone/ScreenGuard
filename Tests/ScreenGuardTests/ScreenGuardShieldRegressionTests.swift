//
//  ScreenGuardShieldRegressionTests.swift
//  ScreenGuardTests
//
//  Regression tests for review round 1 (docs/evidence/review-round1.md, findings F1–F9).
//
//  Every test here is written to FAIL against the reviewed revision and pass against the repair. The
//  three that are cheap to re-run against the old code (F1's hierarchy assertions and F3's
//  convergence) were also executed against a copy of the pre-repair sources and did fail, so they are
//  not vacuous.
//
//  WHY THE PRIVATE-PATH TESTS SKIP IN THE DEFAULT BUILD — and why that is honest:
//  the package's default is `.default(enabledTraits: [])`, so `xcodebuild test -scheme ScreenGuard`
//  builds a configuration in which `ScreenGuardPrivateSecureLayer.swift` is not compiled at all and
//  there is no engine to engage. The tests therefore SKIP with an explicit reason rather than
//  weakening the assertion to fit the default build (the six existing device/scene skips are the same
//  pattern). The enabled configuration is exercised two other ways, both recorded by t10:
//    * the same suite, run in a throwaway checkout whose manifest enables the trait;
//    * `Examples/ScreenGuardDemo`, whose package dependency enables the trait, via
//      `Scripts/verify_capture.sh` — which asserts the private path's state AND its pixels.
//

@testable import ScreenGuard
import UIKit
import XCTest

@MainActor
final class ScreenGuardShieldRegressionTests: XCTestCase {
    /// The reason string for tests that need the private-API code compiled in.
    static let privateTraitReason =
        "PRIVATEAPI-REQUIRED: the `PrivateAPI` package trait is not enabled in this build, so the "
            + "private secure-layer engine is not compiled in and cannot be engaged. Run this suite in a "
            + "trait-enabled checkout, or see Scripts/verify_capture.sh (the example app enables the trait)."

    // MARK: - Helpers

    /// A window that behaves like a real hierarchy for the purposes of `view.window != nil`.
    ///
    /// It deliberately has no `windowScene`: the tests that need a scene resolve the test host's own
    /// key window instead, and the ones that do not need a scene must not depend on one.
    func makeWindow(width: CGFloat = 320, height: CGFloat = 240) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    /// A shield installed in `makeWindow()`'s hierarchy, laid out.
    func makeShieldInAWindow(
        strategy: ScreenGuardNoLeakStrategy,
        window: UIWindow
    ) -> ScreenGuardShieldView {
        let shield = ScreenGuardShieldView(strategy: strategy)
        window.rootViewController?.view.addSubview(shield)
        shield.frame = window.bounds
        shield.layoutIfNeeded()
        return shield
    }

    /// A solid-colour image, for the rasterisation paths.
    static func solidImage(size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 1, size.height > 1 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(
            bounds: CGRect(origin: .zero, size: size),
            format: format
        ).image { context in
            UIColor(red: 38 / 255, green: 102 / 255, blue: 242 / 255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - F1 — switching to the public path must detach the protected content

    /// THE LEAK. `.disabled` hosts the content as a live subview; switching to the public path used to
    /// leave it there while the shield reported `isProtecting == true`. A live subview is rendered by
    /// the ordinary capture path, so the sensitive content would appear in a real screenshot.
    func testSwitchingFromDisabledToThePublicPathDetachesTheContent() {
        let window = makeWindow()
        let shield = makeShieldInAWindow(strategy: .disabled, window: window)
        let content = UIView()
        shield.protectedContentView = content
        shield.layoutIfNeeded()

        // Baseline: the fallback/disabled mode SHOWS the content, which is correct for that mode.
        XCTAssertTrue(content.isDescendant(of: shield), "the disabled mode must show the content")

        shield.apply(strategy: .publicPreventsCaptureLayer)
        shield.layoutIfNeeded()

        XCTAssertTrue(shield.isProtecting, "the public path must still engage")
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
        XCTAssertFalse(
            content.isDescendant(of: shield),
            "the protected content must NOT remain in the live view hierarchy on the public path — a "
                + "live subview is rendered by the ordinary capture path while the shield claims "
                + "protection (review round 1, F1)"
        )
    }

    /// The same leak by the other route the reviewer named: a failed private attempt falls back to the
    /// labelled overlay (which hosts the content live by design), and switching from that to the
    /// public path must detach it too.
    func testFailedPrivateAttemptThenThePublicPathDetachesTheContent() {
        let window = makeWindow()
        let shield = makeShieldInAWindow(strategy: .disabled, window: window)
        let content = UIView()
        shield.protectedContentView = content
        shield.layoutIfNeeded()

        // No opt-in, so this cannot engage and must degrade to the LABELLED fallback.
        ScreenGuard.PrivateAPI.isEnabled = false
        shield.apply(strategy: .privateSecureLayer)
        shield.layoutIfNeeded()

        XCTAssertFalse(shield.isProtecting)
        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertTrue(
            content.isDescendant(of: shield),
            "the labelled fallback must SHOW the content it cannot protect"
        )

        shield.apply(strategy: .publicPreventsCaptureLayer)
        shield.layoutIfNeeded()

        XCTAssertTrue(shield.isProtecting)
        XCTAssertFalse(
            content.isDescendant(of: shield),
            "the public path must detach content left live by the fallback"
        )
    }

    /// The detach must not be a one-off: assigning the content AFTER the strategy is already the
    /// public path must also leave it detached.
    func testAssigningContentWhileAlreadyOnThePublicPathKeepsItDetached() {
        let window = makeWindow()
        let shield = makeShieldInAWindow(strategy: .publicPreventsCaptureLayer, window: window)

        let content = UIView()
        shield.protectedContentView = content
        shield.layoutIfNeeded()

        XCTAssertTrue(shield.isProtecting)
        XCTAssertFalse(content.isDescendant(of: shield))
        XCTAssertNil(content.superview, "a detached view has no superview")
    }

    /// THE COUNTERPART, so the detach cannot be "achieved" by never showing anything: the two modes
    /// whose documented job is to paint the content must keep doing so.
    func testOverlayModesStillShowTheContent() {
        let window = makeWindow()

        let disabledShield = makeShieldInAWindow(strategy: .disabled, window: window)
        let disabledContent = UIView()
        disabledShield.protectedContentView = disabledContent
        XCTAssertTrue(disabledContent.isDescendant(of: disabledShield))
        XCTAssertFalse(disabledContent.isHidden)

        let fallbackShield = makeShieldInAWindow(strategy: .privateSecureLayer, window: window)
        let fallbackContent = UIView()
        fallbackShield.protectedContentView = fallbackContent
        XCTAssertEqual(fallbackShield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertTrue(fallbackContent.isDescendant(of: fallbackShield))
        XCTAssertFalse(fallbackContent.isHidden)
    }

    /// The PIXEL half of F1, where an in-process read permits one.
    ///
    /// `drawHierarchy` renders nothing in a unit-test host (pinned by `ScreenGuardRasterizerTests`), so
    /// this reads the **ordinary layer tree** with `CALayer.render(in:)` instead. That is exactly the
    /// tree a live subview contributes its pixels to — the thing F1 was about — and it comes with its
    /// own control: the same read must image the content while the content IS live, or the assertion
    /// below would pass merely because the readback produced nothing.
    ///
    /// What this is NOT: a capture-path measurement. Whether the pixels survive a *real* screenshot is
    /// device-pending and stays that way (`docs/api-contract.md` §4).
    func testPublicPathKeepsTheSensitivePixelsOutOfTheOrdinaryLayerTree() throws {
        let sentinel = UIColor(red: 200 / 255, green: 0, blue: 160 / 255, alpha: 1)
        let secret = UIColor(red: 38 / 255, green: 102 / 255, blue: 242 / 255, alpha: 1)

        let window = makeWindow()
        let root = try XCTUnwrap(window.rootViewController?.view)
        root.backgroundColor = sentinel

        let shield = ScreenGuardShieldView(strategy: .disabled)
        shield.shieldColor = .black
        root.addSubview(shield)
        shield.frame = root.bounds

        let secretView = UIView()
        secretView.backgroundColor = secret
        shield.protectedContentView = secretView
        root.layoutIfNeeded()

        // CONTROL: while the content is live, the ordinary layer-tree read images it.
        let liveRead = try XCTUnwrap(Self.pixel(in: Self.render(root), at: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertLessThan(
            Self.channelDistance(liveRead, Self.components(secret)),
            40,
            "the control read \(liveRead) should be the content colour \(Self.components(secret)) — the "
                + "readback is not imaging the live content, so the assertion below would prove nothing"
        )

        shield.apply(strategy: .publicPreventsCaptureLayer)
        shield.layoutIfNeeded()
        root.layoutIfNeeded()

        let detachedRead = try XCTUnwrap(Self.pixel(in: Self.render(root), at: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertFalse(secretView.isDescendant(of: shield))
        XCTAssertGreaterThan(
            Self.channelDistance(detachedRead, Self.components(secret)),
            40,
            "the sensitive pixels are still in the ordinary layer tree after switching to the public "
                + "path (read \(detachedRead)) — that is the F1 leak, and a live view is what a real "
                + "capture would have rendered"
        )
    }

    // MARK: - F2 — the private path must report success when the effect is in place

    /// The engine itself: with the trait compiled in, the opt-in granted and a host in a window, the
    /// swap must report success. Before the repair this returned `false` with
    /// `.privateSecureLayerSwapFailed` on every attempt, because the postcondition compared
    /// `canvas.layer === host.layer` AFTER the sequence had already restored the canvas's own layer.
    func testPrivateEngineEngagesWithTheTraitTheOptInAndAWindow() throws {
        try requirePrivateTrait()

        let window = makeWindow()
        let host = UIView(frame: window.bounds)
        window.rootViewController?.view.addSubview(host)
        host.layoutIfNeeded()

        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let engine = try XCTUnwrap(
            ScreenGuardPrivateSecureLayerFactory.make(),
            "the trait reports itself compiled in, so a factory must exist"
        )

        XCTAssertTrue(
            engine.engage(on: host),
            "engage must succeed with the trait on, the opt-in on and a window present — got "
                + "failure \(String(describing: engine.failure))"
        )
        XCTAssertTrue(engine.isEngaged)
        XCTAssertNil(engine.failure)

        engine.disengage()
        XCTAssertFalse(engine.isEngaged, "disengage() must be reachable and must clear the state")
    }

    /// Through the public API: the shield's report must AGREE with the engine's `isEngaged`.
    ///
    /// A capability that is delivered but reported as failed is the same honesty defect as a failure
    /// reported as success — it tells a risk engine the wrong thing and fires a spurious
    /// `protectionDegraded` on every attempt.
    func testShieldReportMatchesTheEngagedPrivatePath() throws {
        try requirePrivateTrait()

        let window = makeWindow()
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let shield = makeShieldInAWindow(strategy: .privateSecureLayer, window: window)
        shield.layoutIfNeeded()

        XCTAssertTrue(
            shield.isProtecting,
            "the shield must report the engaged private path — got \(String(describing: shield.protectionFailure))"
        )
        XCTAssertEqual(shield.shieldMode, .privateSecureLayer)
        XCTAssertEqual(shield.effectiveStrategy, .privateSecureLayer)
        XCTAssertNil(shield.protectionFailure, "a success must not be reported as a failure")
        XCTAssertTrue(
            shield.isPrivateLayerEngaged,
            "the shield's report must match the engine's isEngaged"
        )
    }

    /// The engagement must also be RELEASABLE: switching away has to disengage the engine, or the
    /// package cannot promise to undo the arrangement it created.
    func testSwitchingAwayReleasesTheEngagedPrivateLayer() throws {
        try requirePrivateTrait()

        let window = makeWindow()
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let shield = makeShieldInAWindow(strategy: .privateSecureLayer, window: window)
        shield.layoutIfNeeded()
        XCTAssertTrue(shield.isProtecting)
        XCTAssertTrue(shield.isPrivateLayerEngaged)

        shield.apply(strategy: .publicPreventsCaptureLayer)

        XCTAssertFalse(
            shield.isPrivateLayerEngaged,
            "teardown() must release the private engine it adopted"
        )
        XCTAssertTrue(shield.isProtecting, "the public path must then engage")
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
    }

    // MARK: - F4 — no deprecated trait override, and no retain cycle from the registration

    /// The display-scale registration must not keep the shield alive: the handler receives its trait
    /// environment as a parameter rather than capturing the view.
    ///
    /// This also pins the decision not to unregister from `deinit` — `unregisterForTraitChanges(_:)`
    /// is main-actor isolated and cannot be called from a nonisolated `deinit`, so the registration's
    /// lifetime is the view's lifetime and it must therefore not be a cycle.
    func testShieldFromAWindowDeallocates() {
        // A window strong-referenced by the test, and a shield that is only referenced weakly.
        //
        // The `autoreleasepool` is not cosmetic: measured, a plain `UIView` added to a window and
        // removed again ALSO stays alive until the enclosing autorelease pool drains, so without it
        // this test would fail for a plain view too and would be measuring the test host rather than
        // the shield.
        let window = makeWindow()
        weak var weakShield: ScreenGuardShieldView?

        autoreleasepool {
            let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)
            window.rootViewController?.view.addSubview(shield)
            shield.frame = window.bounds
            shield.layoutIfNeeded()
            weakShield = shield
            XCTAssertNotNil(weakShield, "the shield must exist while the window holds it")
            XCTAssertTrue(shield.isProtecting)
            // The window is retained by this test, so drop the subview reference as well; otherwise
            // the assertion below would pass merely because the window still owns it.
            shield.removeFromSuperview()
        }

        XCTAssertNil(
            weakShield,
            "the shield must deallocate once the caller releases it — the display-scale trait "
                + "registration must not retain it"
        )
    }
}
