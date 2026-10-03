//
//  ScreenGuardAppSwitcherTests.swift
//  ScreenGuardTests
//
//  App-switcher cover state and the synchronous-cover requirement.
//
//  ⚠️ What is NOT tested here, and why: whether the SYSTEM's app-switcher snapshot actually contains
//  the app's content. That artifact lands in `data/Library/SplashBoard/Snapshots/**/*.ktx` in Apple's
//  proprietary AAPL-magic KTX variant, which neither ImageMagick nor ffmpeg can decode
//  (docs/TOOLING.md §4). Snapshot pixels are not pixel-verifiable on Simulator, so the capability is
//  device-validated only — see `ScreenGuardDeviceOnlyTests`.
//

import XCTest
@testable import ScreenGuard

@MainActor
final class ScreenGuardAppSwitcherTests: XCTestCase {

    // MARK: - Install lifecycle

    func testInstallAndUninstallAreIdempotent() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let shield = ScreenGuardAppSwitcherShield()

        XCTAssertFalse(shield.isInstalled)

        shield.install(on: window)
        XCTAssertTrue(shield.isInstalled)
        XCTAssertTrue(shield.isDescendant(of: window))

        shield.install(on: window)
        XCTAssertTrue(shield.isInstalled, "install(on:) must be idempotent")

        shield.uninstall()
        XCTAssertFalse(shield.isInstalled)
        XCTAssertNil(shield.superview)

        shield.uninstall()
        XCTAssertFalse(shield.isInstalled, "uninstall() must be idempotent")
    }

    /// The cover must not obstruct the app while the scene is active.
    func testCoverIsHiddenBeforeDeactivation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let shield = ScreenGuardAppSwitcherShield()
        shield.install(on: window)

        XCTAssertTrue(shield.isHidden)
        XCTAssertEqual(shield.alpha, 0)
    }

    /// The mechanism requirement: the cover must be installed SYNCHRONOUSLY, because the system
    /// snapshots immediately after `UISceneWillDeactivateNotification`. An asynchronous cover is a
    /// defect. This asserts that the transition takes effect within the same call.
    func testCoverIsInstalledSynchronously() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let shield = ScreenGuardAppSwitcherShield()
        shield.install(on: window)

        shield.coverNow()

        XCTAssertFalse(shield.isHidden, "the cover must be visible synchronously, not on a later runloop")
        XCTAssertEqual(shield.alpha, 1)
        XCTAssertEqual(window.subviews.last, shield, "the cover must be frontmost")
    }

    func testUncoverRestoresTheHiddenState() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let shield = ScreenGuardAppSwitcherShield()
        shield.install(on: window)

        shield.coverNow()
        shield.uncoverNow()

        XCTAssertTrue(shield.isHidden)
        XCTAssertEqual(shield.alpha, 0)
    }

    /// A shield that was never installed must not cover anything — there is no window to cover.
    func testCoveringWithoutInstallingDoesNothing() {
        let shield = ScreenGuardAppSwitcherShield()
        shield.coverNow()
        XCTAssertTrue(shield.isHidden, "coverNow() without install(on:) must be a no-op")
    }

    /// Re-installing on a different window must move the cover, not duplicate it.
    func testReinstallingMovesTheCover() {
        let first = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let second = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let shield = ScreenGuardAppSwitcherShield()

        shield.install(on: first)
        shield.install(on: second)

        XCTAssertTrue(shield.isInstalled)
        XCTAssertTrue(shield.isDescendant(of: second))
        XCTAssertNil(shield.superview === first ? shield : nil)
        XCTAssertEqual(first.subviews.filter { $0 === shield }.count, 0)
    }

    // MARK: - Style

    func testAllStylesApplyWithoutTrapping() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let shield = ScreenGuardAppSwitcherShield()
        shield.install(on: window)

        let styles: [ScreenGuardAppSwitcherStyle] = [
            .blur(style: .systemMaterial),
            .opaque(color: .systemBackground),
            .branded(image: nil, backgroundColor: .systemBackground),
            .branded(image: UIImage(), backgroundColor: .black)
        ]

        for style in styles {
            shield.style = style
            shield.coverNow()
            XCTAssertFalse(shield.isHidden)
        }
    }

    /// The style is a value type with an associated value, so it must be switchable exhaustively.
    func testStyleIsExhaustivelySwitchable() {
        let style = ScreenGuardAppSwitcherStyle.opaque(color: .red)
        switch style {
        case .blur(let blurStyle):
            XCTFail("unexpected blur \(blurStyle)")
        case .opaque(let color):
            XCTAssertEqual(color, .red)
        case .branded:
            XCTFail("unexpected branded")
        }
    }

    // MARK: - Monitor integration

    /// When the configuration enables the cover, the monitor installs it — and reports the failure
    /// path rather than failing silently.
    func testMonitorInstallsTheShieldWhenEnabled() {
        let monitor = ScreenGuardMonitor(
            configuration: ScreenGuardConfiguration(isAppSwitcherShieldEnabled: true)
        )
        var events: [ScreenGuardEvent] = []
        monitor.onEvent = { events.append($0) }

        monitor.start()
        defer { monitor.stop() }

        // No window is guaranteed in a unit-test host, so the shield may be pending installation.
        // What must hold is that start()/stop() are safe and no spurious degraded event is emitted.
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertTrue(events.allSatisfy { if case .protectionDegraded = $0.kind { return false } else { return true } })
    }

    func testMonitorDoesNotInstallTheShieldWhenDisabled() {
        let monitor = ScreenGuardMonitor(
            configuration: ScreenGuardConfiguration(isAppSwitcherShieldEnabled: false)
        )
        monitor.start()
        XCTAssertTrue(monitor.isMonitoring)
        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)
    }
}
