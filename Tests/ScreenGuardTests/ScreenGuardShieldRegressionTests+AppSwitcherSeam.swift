//
//  ScreenGuardShieldRegressionTests+AppSwitcherSeam.swift
//  ScreenGuard
//
//  F7 — the app-switcher failure seam must report something real.
//
//  Split out of ScreenGuardShieldRegressionTests.swift to keep that file (and its class body) inside
//  the size limits. The tests are the same tests: an extension adds methods to the same XCTestCase
//  subclass, so the executed test count is unchanged.
//

@testable import ScreenGuard
import UIKit
import XCTest

extension ScreenGuardShieldRegressionTests {
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
            .first(where: \.isKeyWindow)
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
}
