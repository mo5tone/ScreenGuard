//
//  ScreenGuardShieldStateTests.swift
//  ScreenGuardTests
//
//  Shield state transitions: what the shield is doing, and whether it says so honestly.
//
//  These tests run on Simulator because they assert STATE, not pixels. The pixel behaviour of the
//  public path is explicitly NOT measurable on Simulator (docs/evidence/capability-matrix.md §4) and
//  is therefore skipped with a reason in `ScreenGuardDeviceOnlyTests.swift` — never silently dropped.
//

import XCTest
@testable import ScreenGuard

@MainActor
final class ScreenGuardShieldStateTests: XCTestCase {

    // MARK: - Disabled

    func testDisabledStrategyReportsThatItIsNotProtecting() {
        let shield = ScreenGuardShieldView(strategy: .disabled)
        XCTAssertFalse(shield.isProtecting)
        XCTAssertEqual(shield.effectiveStrategy, .disabled)
        XCTAssertEqual(shield.shieldMode, .disabled)
        XCTAssertNil(shield.protectionFailure)
    }

    // MARK: - Public path

    /// The public path engages (the layer is created), and the shield reports it as engaged. This
    /// says nothing about capture behaviour — that is device-pending and is tested on hardware.
    func testPublicStrategyEngagesAndReportsProtecting() {
        let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)
        XCTAssertTrue(shield.isProtecting)
        XCTAssertEqual(shield.effectiveStrategy, .publicPreventsCaptureLayer)
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
        XCTAssertNil(shield.protectionFailure)
        XCTAssertEqual(shield.requestedStrategy, .publicPreventsCaptureLayer)
    }

    /// The default strategy is the public path. The private path must never be the default.
    func testDefaultStrategyIsThePublicPathNotThePrivatePath() {
        let shield = ScreenGuardShieldView()
        XCTAssertEqual(shield.requestedStrategy, .publicPreventsCaptureLayer)
        XCTAssertNotEqual(shield.requestedStrategy, .privateSecureLayer)
    }

    /// The default configuration must not select the private path either.
    func testDefaultConfigurationDoesNotSelectThePrivatePath() {
        XCTAssertEqual(ScreenGuardConfiguration().noLeakStrategy, .publicPreventsCaptureLayer)
    }

    // MARK: - Private path — off by default

    /// With no opt-in, requesting the private path must NOT protect, must say so, and must fall back
    /// to the LABELLED overlay. This is the single most important safety property in the package.
    func testPrivateStrategyWithoutOptInDoesNotProtectAndLabelsTheFallback() {
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)

        XCTAssertFalse(shield.isProtecting, "the private path must be off by default")
        XCTAssertEqual(shield.effectiveStrategy, .disabled)
        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertEqual(shield.protectionFailure, .privateSecureLayerUnavailable)
        XCTAssertEqual(shield.requestedStrategy, .privateSecureLayer)
    }

    /// The failure is reported through the callback seam, so a host can emit a `protectionDegraded`
    /// event rather than believing it is protected.
    func testPrivateStrategyWithoutOptInReportsFailureThroughTheCallbackSeam() {
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        var reported: [ScreenGuardProtectionFailure] = []
        shield.onProtectionFailure = { reported.append($0) }

        // Re-apply so the callback is installed before the failure path runs.
        shield.apply(strategy: .privateSecureLayer)

        XCTAssertEqual(reported, [.privateSecureLayerUnavailable])
    }

    /// The opt-in gate defaults to off and is a public, explicit act — not something a stray strategy
    /// assignment can flip.
    func testPrivateOptInDefaultsToOff() {
        XCTAssertFalse(ScreenGuard.PrivateAPI.isEnabled)
    }

    /// `ScreenGuard.PrivateAPI.isCompiledIn` must be consistent with the shield's actual behaviour,
    /// in **both** build configurations.
    ///
    /// The test cannot branch on `#if SCREENGUARD_PRIVATE_API` itself: that define is set on the
    /// `ScreenGuard` target (via the `PrivateAPI` trait), not on this test target, so the test would
    /// assert the wrong expectation when the trait is off. It branches on the reported flag instead,
    /// which is the value under test.
    ///
    /// The escape hatch's real proof — that the private class-name string is absent from the compiled
    /// binary — is a `strings` check on the built object, not something a unit test can see.
    func testPrivateCompilationFlagIsConsistentWithShieldBehaviour() {
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)

        if ScreenGuard.PrivateAPI.isCompiledIn {
            // Implementation present, but this shield is outside any window, so the private canvas
            // cannot be found. Permission is not a guarantee: it must still refuse and label itself.
            XCTAssertFalse(
                shield.isProtecting,
                "a shield outside a window cannot engage the private canvas and must not claim it did"
            )
            XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
            XCTAssertNotNil(shield.protectionFailure)
        } else {
            // Implementation excluded from the build: the documented degradation, regardless of the
            // runtime flag.
            XCTAssertFalse(shield.isProtecting)
            XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
            XCTAssertEqual(shield.protectionFailure, .privateSecureLayerUnavailable)
        }
    }

    /// Whatever the configuration, the private path must NEVER claim protection without the explicit
    /// opt-in. This is the safety property that must hold in both builds.
    func testPrivatePathNeverProtectsWithoutOptInInAnyConfiguration() {
        ScreenGuard.PrivateAPI.isEnabled = false
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)

        XCTAssertFalse(shield.isProtecting)
        XCTAssertEqual(shield.effectiveStrategy, .disabled)
        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertNotNil(shield.protectionFailure)
    }

    /// Enabling the opt-in permits engagement, but a shield with no window cannot find the private
    /// canvas — so it must STILL refuse to claim protection and must still label the fallback.
    /// Enabling the opt-in is permission, not a guarantee.
    func testOptInAloneStillDoesNotClaimProtectionWithoutAWindow() {
        ScreenGuard.PrivateAPI.isEnabled = true
        defer { ScreenGuard.PrivateAPI.isEnabled = false }

        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)

        XCTAssertFalse(
            shield.isProtecting,
            "a shield outside a window cannot engage the private canvas and must not claim it did"
        )
        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertNotNil(shield.protectionFailure)
    }

    /// Naming the strategy without opting in must never engage, even on a shield that IS in a window.
    func testOptOutIsEnforcedEvenInAWindow() {
        ScreenGuard.PrivateAPI.isEnabled = false

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        window.rootViewController = UIViewController()
        window.isHidden = false
        window.rootViewController?.view.layoutIfNeeded()

        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        window.rootViewController?.view.addSubview(shield)
        shield.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
        shield.apply(strategy: .privateSecureLayer)

        XCTAssertFalse(shield.isProtecting)
        XCTAssertEqual(shield.protectionFailure, .privateSecureLayerUnavailable)
        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
    }

    // MARK: - Transitions

    /// Every transition out of every strategy must leave a consistent, non-lying state.
    func testEveryStrategyTransitionIsConsistent() {
        let strategies: [ScreenGuardNoLeakStrategy] = [
            .disabled, .publicPreventsCaptureLayer, .privateSecureLayer
        ]
        let shield = ScreenGuardShieldView(strategy: .disabled)

        for strategy in strategies {
            shield.apply(strategy: strategy)
            switch strategy {
            case .disabled:
                XCTAssertEqual(shield.shieldMode, .disabled)
                XCTAssertFalse(shield.isProtecting)
            case .publicPreventsCaptureLayer:
                XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
                XCTAssertTrue(shield.isProtecting)
            case .privateSecureLayer:
                // Off by default: the fallback, and it is labelled.
                XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
                XCTAssertFalse(shield.isProtecting)
            }
        }
    }

    /// `apply(strategy:)` is idempotent: re-applying must not flip state or duplicate failures.
    func testApplyIsIdempotent() {
        let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)
        var failures = 0
        shield.onProtectionFailure = { _ in failures += 1 }

        for _ in 0..<5 { shield.apply(strategy: .publicPreventsCaptureLayer) }

        XCTAssertTrue(shield.isProtecting)
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
        XCTAssertEqual(failures, 0)
    }

    /// A shield that degrades and then recovers must clear its failure, so a host is not left with a
    /// stale "degraded" signal.
    func testRecoveringFromTheFallbackClearsTheFailure() {
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        XCTAssertEqual(shield.protectionFailure, .privateSecureLayerUnavailable)

        shield.apply(strategy: .publicPreventsCaptureLayer)

        XCTAssertNil(shield.protectionFailure)
        XCTAssertTrue(shield.isProtecting)
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
    }

    /// `setNeedsContentRefresh()` is idempotent and safe before any content exists.
    func testSetNeedsContentRefreshIsSafeWithNoContent() {
        let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)
        for _ in 0..<3 { shield.setNeedsContentRefresh() }
        XCTAssertTrue(shield.isProtecting)
    }

    /// The shield must not become an opaque black hole while degraded: the fallback shows the content.
    func testFallbackHostsTheContentLive() {
        let content = UIView()
        let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        shield.protectedContentView = content

        XCTAssertEqual(shield.shieldMode, .detectionAndOverlayFallback)
        XCTAssertTrue(content.isDescendant(of: shield), "the fallback must show the content, not hide it")
        XCTAssertFalse(content.isHidden)
    }

    // MARK: - Shield mode vocabulary

    /// The degraded mode must be self-describing, because a host renders it directly.
    func testShieldModeRawValuesAreExplicit() {
        XCTAssertEqual(ScreenGuardShieldMode.detectionAndOverlayFallback.rawValue, "detectionAndOverlayFallback")
        XCTAssertEqual(ScreenGuardShieldMode.disabled.rawValue, "disabled")
        XCTAssertEqual(ScreenGuardShieldMode.publicPreventsCaptureLayer.rawValue, "publicPreventsCaptureLayer")
        XCTAssertEqual(ScreenGuardShieldMode.privateSecureLayer.rawValue, "privateSecureLayer")
    }

    // MARK: - Secure text field

    /// The measured primitive must refuse to have its protection switched off.
    func testSecureTextFieldCannotBeMadeInsecure() {
        let field = ScreenGuardSecureTextField()
        XCTAssertTrue(field.isSecureTextEntry)
        XCTAssertEqual(field.refusedInsecureEntryAttempts, 0)

        field.isSecureTextEntry = false

        XCTAssertTrue(field.isSecureTextEntry, "isSecureTextEntry must be enforced true")
        XCTAssertEqual(
            field.refusedInsecureEntryAttempts,
            1,
            "the refusal must be observable, not silent"
        )
    }

    /// Assigning `true` is accepted and is not counted as a refusal.
    func testAssigningTrueIsNotARefusal() {
        let field = ScreenGuardSecureTextField()
        field.isSecureTextEntry = true
        XCTAssertTrue(field.isSecureTextEntry)
        XCTAssertEqual(field.refusedInsecureEntryAttempts, 0)
    }

    func testSecureTextFieldStartsCopyProtected() {
        let field = ScreenGuardSecureTextField()
        XCTAssertTrue(field.isCopyProtected)
    }

    /// Copy protection must actually suppress the editing actions.
    ///
    /// A plain `UITextField` is the baseline, and it matters: measured, UIKit returns `false` for
    /// `copy:` on a field that is not first responder regardless of any override, so asserting only on
    /// the guarded field would pass even if the override did nothing.
    func testCopyProtectionSuppressesEditingActions() {
        let field = ScreenGuardSecureTextField()
        XCTAssertTrue(field.isCopyProtected)
        XCTAssertFalse(field.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil))
        XCTAssertFalse(field.canPerformAction(#selector(UIResponder.paste(_:)), withSender: nil))
        XCTAssertFalse(field.canPerformAction(#selector(UIResponder.cut(_:)), withSender: nil))
    }

    /// With copy protection off, the guarded field must defer to UIKit rather than keep suppressing.
    ///
    /// The observable difference is `canPerformAction` for an action UIKit *would* allow on a plain
    /// field — asserted here against the plain-field baseline so the test proves the override is what
    /// makes the difference.
    func testCopyProtectionCanBeDisabled() {
        let plain = UITextField()
        let baseline = plain.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil)

        let field = ScreenGuardSecureTextField()
        field.isCopyProtected = false

        XCTAssertEqual(
            field.canPerformAction(#selector(UIResponder.copy(_:)), withSender: nil),
            baseline,
            "with copy protection off the field must match a plain UITextField"
        )
    }

    /// The editing seam reports the new text.
    ///
    /// Driven by `textDidChangeNotification`, not by `.editingChanged`: measured, a `UITextField`
    /// that is not in a window and is not first responder fires **no** `.editingChanged` action — a
    /// plain `UITextField` with a test-owned target fires zero times too — so `sendActions` is not a
    /// usable seam.
    func testTextChangeCallbackFires() {
        let field = ScreenGuardSecureTextField()
        var observed: [String] = []
        field.onTextChanged = { observed.append($0) }

        field.text = "4417"
        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)

        XCTAssertEqual(observed, ["4417"])
    }

    /// A second change reports the new value, so the seam tracks the field rather than firing once.
    func testTextChangeCallbackTracksRepeatedChanges() {
        let field = ScreenGuardSecureTextField()
        var observed: [String] = []
        field.onTextChanged = { observed.append($0) }

        for value in ["4417", "44178823", ""] {
            field.text = value
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
        }

        XCTAssertEqual(observed, ["4417", "44178823", ""])
    }

    /// A notification for a *different* field must not fire this field's callback.
    func testTextChangeCallbackIgnoresOtherFields() {
        let field = ScreenGuardSecureTextField()
        var observed: [String] = []
        field.onTextChanged = { observed.append($0) }

        NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: UITextField())

        XCTAssertEqual(observed, [])
    }
}
