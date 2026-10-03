//
//  ScreenGuardRendererContentTests+SwiftUI.swift
//  ScreenGuard
//
//  The REAL SwiftUI modifier: renderer-fed content must actually reach the screen.
//
//  Split out of ScreenGuardRendererContentTests.swift to keep that file (and its class body) inside
//  the size limits. The tests are the same tests: an extension adds methods to the same XCTestCase
//  subclass, so the executed test count is unchanged.
//

@testable import ScreenGuard
import SwiftUI
import UIKit
import XCTest

extension ScreenGuardRendererContentTests {
    // MARK: - The REAL SwiftUI modifier

    /// The first `ScreenGuardShieldView` in a hierarchy.
    func firstShield(in root: UIView) -> ScreenGuardShieldView? {
        if let shield = root as? ScreenGuardShieldView {
            return shield
        }
        for subview in root.subviews {
            if let found = firstShield(in: subview) {
                return found
            }
        }
        return nil
    }

    /// The package's OWN modifier, on a real `UIHostingController` — not a hand-rolled reproduction of
    /// the bridge's call sequence.
    ///
    /// This is the test that would have caught the F-R2-1 defect end to end. The tests above reproduce
    /// `ScreenGuardShieldRepresentable.makeUIView`'s calls by hand; this one lets the package build the
    /// bridge itself, with the real `ImageRenderer`-backed rasteriser behind it, and then asks whether
    /// anything is actually on screen. Measured (round-3 repair): the hand-rolled version passed while
    /// this one still failed, because the real route reaches the shield through SwiftUI's layout and
    /// update cycle rather than through `frame` + `layoutIfNeeded`.
    ///
    /// `.disabled` is used because it needs no private trait: the mode's documented job is to show the
    /// content, so "is the rendered content on screen?" is a complete question in the default build.
    func testTheRealSwiftUIModifierShowsRenderedContent() throws {
        let window = makeWindow(width: 320, height: 240)
        let controller = UIHostingController(
            rootView: Rectangle()
                .fill(Color(uiColor: Self.rendererColour))
                .screenGuardProtected(strategy: .disabled)
        )
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        let shield = try XCTUnwrap(
            firstShield(in: controller.view),
            "the modifier must build a ScreenGuardShieldView"
        )
        XCTAssertEqual(shield.shieldMode, .disabled)

        // Narrow the failure to a STAGE, so a red test says where the content was dropped rather than
        // just "the card is blank". Each assertion below is a precondition of the next.
        let size = shield.bounds.size
        XCTAssertGreaterThan(
            size.width, 1,
            "stage 1 — the shield must have been laid out; bounds are \(shield.bounds)"
        )

        let renderer = try XCTUnwrap(
            shield.protectedContentRenderer,
            "stage 2 — the SwiftUI bridge must install a render function on the shield"
        )
        XCTAssertNotNil(
            renderer(size, 2),
            "stage 3 — the package's own rasteriser must turn the SwiftUI content into an image for a "
                + "\(size) region"
        )

        XCTAssertNotNil(
            displayedRendererImage(in: shield),
            "stage 4 — the package's own SwiftUI modifier must put the rendered content on screen; the "
                + "shield being an opaque black card is the F-R2-1 blank"
        )
    }

    /// The same modifier on the DEFAULT strategy, where the content is pushed into the display layer
    /// rather than hosted live.
    ///
    /// `hasPushedFrame` is driven by the REAL enqueue result and the enqueue is only reached when the
    /// renderer produced a non-nil image, so this is the public path's own proof that the SwiftUI
    /// rasteriser works — and it is the proof that was missing. Before the repair the renderer returned
    /// `nil` for every size, on every strategy, because a `ViewModifier`'s `content` is a
    /// `_ViewModifier_Content` placeholder that does not render on its own. On Simulator that was
    /// invisible on this path: `preventsCapture = true` already makes the layer paint nothing here
    /// (`docs/TOOLING.md` §7.1), so "no frame was ever pushed" and "the layer is blank by design"
    /// looked identical.
    func testTheRealSwiftUIModifierRasterisesOnTheDefaultPublicStrategy() throws {
        let window = makeWindow(width: 320, height: 240)
        let controller = UIHostingController(
            rootView: Rectangle()
                .fill(Color(uiColor: Self.rendererColour))
                .screenGuardProtected() // default: .publicPreventsCaptureLayer
        )
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        let shield = try XCTUnwrap(firstShield(in: controller.view))
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)
        XCTAssertTrue(shield.isProtecting)
        XCTAssertTrue(
            shield.hasPushedFrame,
            "the public path must have rasterised the SwiftUI content and enqueued it; a `false` here "
                + "means the renderer produced no image, which is the rasteriser defect the F-R2-1 "
                + "repair uncovered (see ScreenGuardProtectedView's note)"
        )
    }
}
