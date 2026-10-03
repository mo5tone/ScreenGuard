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

import UIKit
import XCTest
@testable import ScreenGuard

@MainActor
final class ScreenGuardShieldRegressionTests: XCTestCase {

    /// The reason string for tests that need the private-API code compiled in.
    private static let privateTraitReason =
        "PRIVATEAPI-REQUIRED: the `PrivateAPI` package trait is not enabled in this build, so the "
        + "private secure-layer engine is not compiled in and cannot be engaged. Run this suite in a "
        + "trait-enabled checkout, or see Scripts/verify_capture.sh (the example app enables the trait)."

    // MARK: - Helpers

    /// A window that behaves like a real hierarchy for the purposes of `view.window != nil`.
    ///
    /// It deliberately has no `windowScene`: the tests that need a scene resolve the test host's own
    /// key window instead, and the ones that do not need a scene must not depend on one.
    private func makeWindow(width: CGFloat = 320, height: CGFloat = 240) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    /// A shield installed in `makeWindow()`'s hierarchy, laid out.
    private func makeShieldInAWindow(
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
    private static func solidImage(size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }
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

    // MARK: - F3 — requestedStrategy must track apply(strategy:)

    func testRequestedStrategyFollowsApply() {
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        XCTAssertEqual(shield.requestedStrategy, .privateSecureLayer, "the init-time value must survive")

        shield.apply(strategy: .publicPreventsCaptureLayer)
        XCTAssertEqual(
            shield.requestedStrategy,
            .publicPreventsCaptureLayer,
            "requestedStrategy must report the LAST request, not the init-time one"
        )

        shield.apply(strategy: .disabled)
        XCTAssertEqual(shield.requestedStrategy, .disabled)
    }

    /// The concrete consequence of F3: the package's own SwiftUI bridge compares
    /// `requestedStrategy` against the incoming strategy to decide whether to re-apply. When the value
    /// never converged, EVERY later update re-ran `apply(strategy:)` — a full teardown plus
    /// re-rasterisation, forever, after the first strategy change.
    ///
    /// `ScreenGuardShieldRepresentable` is private to the module, so the comparison is reproduced here
    /// verbatim from `ScreenGuardModifiers.swift:130`; what it reads (`requestedStrategy`) is the
    /// property under test. The render counter is observable through the public
    /// `protectedContentRenderer` seam, and it is the number of times the public path actually
    /// re-rasterised.
    func testRequestedStrategyConvergesSoTheSwiftUIBridgeDoesNotReapply() {
        let window = makeWindow()
        let shield = makeShieldInAWindow(strategy: .disabled, window: window)

        var renders = 0
        shield.protectedContentRenderer = { size, scale in
            renders += 1
            return ScreenGuardShieldRegressionTests.solidImage(size: size, scale: scale)
        }
        shield.setNeedsContentRefresh()

        // The bridge's decision, verbatim.
        func swiftUIUpdateUIView(strategy: ScreenGuardNoLeakStrategy) {
            if shield.requestedStrategy != strategy {
                shield.apply(strategy: strategy)
            }
        }

        let rendersBefore = renders
        swiftUIUpdateUIView(strategy: .publicPreventsCaptureLayer)
        let rendersAfterFirstUpdate = renders

        XCTAssertGreaterThan(
            rendersAfterFirstUpdate,
            rendersBefore,
            "a genuine strategy change must engage the mechanism (and rasterise)"
        )
        XCTAssertEqual(shield.requestedStrategy, .publicPreventsCaptureLayer)

        swiftUIUpdateUIView(strategy: .publicPreventsCaptureLayer)
        swiftUIUpdateUIView(strategy: .publicPreventsCaptureLayer)

        XCTAssertEqual(
            renders,
            rendersAfterFirstUpdate,
            "a second and third update with the SAME strategy must be a no-op — the bridge must not "
                + "re-run apply(strategy:) on every update pass (review round 1, F3)"
        )
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

    // MARK: - F8 — engaged is not the same as "a frame was pushed"

    func testEngagedIsNotTheSameAsHavingPushedAFrame() {
        // No window, so no size: the layer is engaged, but nothing can have been pushed into it.
        let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)

        XCTAssertTrue(shield.isProtecting, "isProtecting means the mechanism is engaged")
        XCTAssertFalse(
            shield.hasPushedFrame,
            "no frame can have been pushed before the view has a usable size — a blank region here "
                + "means 'nothing pushed yet', not 'pixels excluded'"
        )
    }

    func testPushingAFrameIsReported() {
        let window = makeWindow()
        let shield = makeShieldInAWindow(strategy: .publicPreventsCaptureLayer, window: window)

        shield.protectedContentRenderer = { size, scale in
            ScreenGuardShieldRegressionTests.solidImage(size: size, scale: scale)
        }
        shield.setNeedsContentRefresh()
        shield.layoutIfNeeded()

        XCTAssertTrue(shield.isProtecting)
        XCTAssertTrue(
            shield.hasPushedFrame,
            "after a successful enqueue the shield must report that a protected frame exists"
        )

        // And the flag must not be sticky: leaving the public path clears it.
        shield.apply(strategy: .disabled)
        XCTAssertFalse(shield.hasPushedFrame)
        XCTAssertFalse(shield.isProtecting)
    }

    // MARK: - F9 — the documented initialiser must work without the host ordering it

    /// `ScreenGuardShieldView(strategy: .privateSecureLayer)` is constructed before the shield has a
    /// window, so engagement cannot happen at `init`. The shield must re-attempt when it joins one.
    func testShieldReattemptsPrivateEngagementWhenItJoinsAWindow() throws {
        try requirePrivateTrait()

        let window = makeWindow()
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        // Created OUTSIDE any window, exactly as the documentation shows.
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        XCTAssertFalse(
            shield.isProtecting,
            "without a window the private canvas does not exist, so this must not claim protection"
        )

        // Joining a window must be enough. No host-side re-apply.
        shield.translatesAutoresizingMaskIntoConstraints = false
        window.rootViewController?.view.addSubview(shield)
        shield.frame = window.bounds
        shield.layoutIfNeeded()

        XCTAssertTrue(
            shield.isProtecting,
            "didMoveToWindow must re-attempt the private path so init(strategy:) behaves as documented"
        )
        XCTAssertEqual(shield.shieldMode, .privateSecureLayer)
        XCTAssertEqual(shield.requestedStrategy, .privateSecureLayer)
    }

    // MARK: - F7 — the app-switcher failure seam must report something real

    /// The coverability predicate itself, tested directly so the install-time report is not left to
    /// whatever environment the suite happens to run in. `nil` is the "no window at all" case.
    func testCoverabilityRequiresAWindowWithAScene() {
        XCTAssertFalse(
            ScreenGuardAppSwitcherShield.canCover(window: nil),
            "a shield with no window has nothing to cover, and must say so rather than stay silent"
        )
    }

    /// `install(on:)` must report exactly when the window has no scene to bind the lifecycle signal
    /// to — and must still install, so a late signal can engage the cover.
    ///
    /// Measured: in this XCTest host a bare `UIWindow(frame:)` is given a scene automatically, so the
    /// `hasScene` branch is the one exercised here. The predicate above covers both directions
    /// directly, and `testAppSwitcherReportsFailureWhenCoverIsRequestedWithoutInstall` covers the
    /// other reachable public route to the same report.
    func testAppSwitcherReportsCoverUnavailableExactlyWhenThereIsNoScene() {
        let window = makeWindow()
        let hasScene = window.windowScene != nil

        let shield = ScreenGuardAppSwitcherShield()
        var reported: [ScreenGuardProtectionFailure] = []
        shield.onProtectionFailure = { reported.append($0) }

        shield.install(on: window)

        XCTAssertTrue(shield.isInstalled, "the cover is still installed, so a late signal can engage it")
        if hasScene {
            XCTAssertTrue(
                reported.isEmpty,
                "a window with a scene has a lifecycle signal bound to it, so there is nothing to report"
            )
        } else {
            XCTAssertEqual(reported, [.appSwitcherCoverUnavailable])
        }

        // Either way, the cover must actually go up when asked.
        shield.coverNow()
        XCTAssertEqual(shield.alpha, 1)
        XCTAssertFalse(shield.isHidden)
    }

    func testAppSwitcherReportsFailureWhenCoverIsRequestedWithoutInstall() {
        let shield = ScreenGuardAppSwitcherShield()
        var reported: [ScreenGuardProtectionFailure] = []
        shield.onProtectionFailure = { reported.append($0) }

        XCTAssertFalse(shield.isInstalled)
        shield.coverNow()

        XCTAssertEqual(
            reported,
            [.appSwitcherCoverUnavailable],
            "coverNow() on a shield that was never installed covers nothing and must say so"
        )
        XCTAssertEqual(shield.alpha, 0, "and it must not pretend to be covering")
    }

    func testAppSwitcherDoesNotReportFailureWhenItCanCover() {
        let window = makeWindow()
        let shield = ScreenGuardAppSwitcherShield()
        var reported: [ScreenGuardProtectionFailure] = []
        shield.onProtectionFailure = { reported.append($0) }

        shield.install(on: window)
        shield.coverNow()
        shield.uncoverNow()
        shield.coverNow()

        XCTAssertEqual(shield.alpha, 1)
        XCTAssertFalse(shield.isHidden)
        if window.windowScene != nil {
            XCTAssertTrue(reported.isEmpty, "a cover that engages must not report a failure")
        }
    }

    /// The strengthened monitor test F7 asked for: give the monitor a real window and assert the cover
    /// is actually installed on it, instead of only asserting that nothing bad happened.
    ///
    /// The previous version could not fail — it passed identically if no cover was ever installed.
    ///
    /// Measured in this host: `UIApplication.shared.connectedScenes` contains no window at all, so
    /// `ScreenGuardMonitor.resolvedWindow()` returns `nil` and the monitor cannot install a cover here
    /// (it waits for a key-window notification instead). The test therefore asserts installation when
    /// a window exists and SKIPS with that reason when it does not — it never silently degrades back
    /// to a check that proves nothing. The cover's installation and deactivation synchrony are asserted
    /// directly against a window in `ScreenGuardAppSwitcherTests`, and end to end by
    /// `Scripts/verify_capture.sh`, whose app-switcher probe reads back the real installed cover.
    func testMonitorInstallsTheCoverOnTheKeyWindow() throws {
        // The monitor resolves its window from `UIApplication.shared.connectedScenes`, so the test has
        // to supply one. A bare `UIWindow(frame:)` is given a scene by this OS, and making it key makes
        // it the window `ScreenGuardMonitor.resolvedWindow()` selects.
        let candidate = makeWindow()
        candidate.makeKeyAndVisible()
        defer { candidate.isHidden = true }

        // Mirror the monitor's own resolution order (`ScreenGuardMonitor.resolvedWindow()`): the key
        // window of a foreground-active scene, else the first window of any connected scene.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
            ?? scenes.first?.windows.first

        guard let keyWindow else {
            throw XCTSkip(
                "SCENE-REQUIRED: this test host has no key window in a connected scene, so the monitor "
                    + "has nothing to install a cover on. The cover's installation and deactivation "
                    + "synchrony are asserted directly by ScreenGuardAppSwitcherTests, and end to end by "
                    + "Scripts/verify_capture.sh."
            )
        }

        let monitor = ScreenGuardMonitor(
            configuration: ScreenGuardConfiguration(isAppSwitcherShieldEnabled: true)
        )
        monitor.start()
        defer { monitor.stop() }

        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertTrue(
            keyWindow.subviews.contains { $0 is ScreenGuardAppSwitcherShield },
            "the monitor must install the cover on the key window when the configuration enables it"
        )
    }

    // MARK: - Ordinary layer-tree pixel read

    /// Renders a view's ordinary layer tree, the way `ScreenGuardDeviceOnlyTests` does.
    private static func render(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// One normalised sample as `(r, g, b)` in 0...255, normalised to RGBA8 first: the renderer's
    /// output is 16 bpc, so a raw byte read yields noise (`docs/TOOLING.md` §5).
    private static func pixel(in image: UIImage, at normalizedPoint: CGPoint) -> (Int, Int, Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
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
        }) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = min(width - 1, max(0, Int(normalizedPoint.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int(normalizedPoint.y * CGFloat(height))))
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private static func components(_ color: UIColor) -> (Int, Int, Int) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private static func channelDistance(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Int {
        max(abs(lhs.0 - rhs.0), max(abs(lhs.1 - rhs.1), abs(lhs.2 - rhs.2)))
    }

    // MARK: - Trait gate

    /// Skips with the documented reason when the private-API code is not compiled into this build.
    private func requirePrivateTrait() throws {
        guard ScreenGuard.PrivateAPI.isCompiledIn else {
            throw XCTSkip(Self.privateTraitReason)
        }
    }
}
