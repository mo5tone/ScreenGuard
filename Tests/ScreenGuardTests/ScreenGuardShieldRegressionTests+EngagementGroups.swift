//
//  ScreenGuardShieldRegressionTests+EngagementGroups.swift
//  ScreenGuard
//
//  F3 / F8 / F9 — requestedStrategy convergence, frame-pushed reporting, and engagement on join.
//
//  Split out of ScreenGuardShieldRegressionTests.swift to keep that file (and its class body) inside
//  the size limits. The tests are the same tests: an extension adds methods to the same XCTestCase
//  subclass, so the executed test count is unchanged.
//

@testable import ScreenGuard
import UIKit
import XCTest

extension ScreenGuardShieldRegressionTests {
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
            Self.solidImage(size: size, scale: scale)
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
            return Self.solidImage(size: size, scale: scale)
        }
        shield.setNeedsContentRefresh()

        func swiftUIUpdateUIView(strategy: ScreenGuardNoLeakStrategy) {
            // The bridge's decision, verbatim.
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
}
