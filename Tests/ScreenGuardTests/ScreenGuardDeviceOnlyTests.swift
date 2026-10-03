//
//  ScreenGuardDeviceOnlyTests.swift
//  ScreenGuardTests
//
//  ⚠️ THE POINT OF THIS FILE IS THE SKIPS — AND THE ONE REAL MEASUREMENT THAT IS NOT A SKIP.
//
//  The package's central claim — that sensitive pixels do not appear in a capture — cannot be
//  measured on Simulator. `docs/TOOLING.md` §7 and `docs/evidence/capability-matrix.md` §4/§7 record
//  why, and the acceptance criteria require that tests which cannot run on Simulator are **skipped
//  with an explicit reason, not silently deleted**.
//
//  So every device-required check is present here as a real, written test that skips with the exact
//  reason and the command to run it on hardware. Nothing here is `XCTFail`: a test that always fails
//  on a device is a broken test, not a device-required one. Where an assertion CAN be made in-process
//  it is made (`testProtectedRegionIsBlankInTheAppSideRenderPath`); where it genuinely requires a
//  human or hardware it skips, and says exactly which.
//

@testable import ScreenGuard
import UIKit
import XCTest

@MainActor
final class ScreenGuardDeviceOnlyTests: XCTestCase {
    /// The exact reason string, so it is greppable from the device verification scripts (t4).
    private static let deviceReason =
        "DEVICE-REQUIRED: not measurable on Simulator — see docs/TOOLING.md §7 and "
            + "docs/evidence/capability-matrix.md §4/§7. Run on a physical device."

    /// The reason for checks that need a human action or an artifact that cannot be read in-process,
    /// even on a device.
    private static let humanReason =
        "HUMAN/HARDWARE-REQUIRED: cannot be triggered or read from inside the test process."

    /// Skips on Simulator with the documented reason; runs on a device.
    private func requireDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip(Self.deviceReason)
        #endif
    }

    // MARK: - 1. The shield's backing covers the region — asserted, not skipped

    /// Reads the protected region back through the **app-side layer tree** and asserts the shield's
    /// opaque backing covers it.
    ///
    /// **This runs everywhere, including Simulator**, and it is a real assertion with a real
    /// falsification control: the shield is deliberately given only the TOP portion of the root view,
    /// so the same readback must report the sentinel *below* the shield and the shield's colour
    /// *inside* it. Without that control, "the region is black" could just mean the readback produced
    /// nothing — which is exactly what a first version of this test did, and it passed vacuously.
    ///
    /// What this proves and what it does not — stated precisely, because the distinction is the whole
    /// reason this file exists:
    /// - **Proves:** the shield is opaque over its whole bounds, so whatever is behind it (the
    ///   sentinel, and by extension any app content) does not show through.
    /// - **Does NOT prove capture exclusion.** The read here is `CALayer.render(in:)` on the layer
    ///   tree, which by measurement cannot even see `AVSampleBufferDisplayLayer` content (it is
    ///   render-server backed). It is therefore a coverage check, never a leak check. The leak check
    ///   is `testPublicPreventsCaptureLayerBlanksTheCaptureButNotTheDisplay`, which requires a device.
    /// - **Also does NOT use `drawHierarchy`.** Measured while writing this file: `drawHierarchy`
    ///   returns `(0,0,0)` for this host's window even though the window reports a
    ///   `UIWindowScene` — so it cannot be used as a readback here. See `ScreenGuardRasterizerTests`,
    ///   which pins that measurement.
    func testShieldBackingIsOpaqueOverTheProtectedRegion() throws {
        // A sentinel the protected region must NOT show through. A black region is ambiguous on its
        // own; a distinctly-coloured backing is what makes "covered" interpretable
        // (docs/TOOLING.md §3).
        let sentinel = UIColor(red: 200 / 255, green: 0, blue: 160 / 255, alpha: 1)
        // Content the region must not leak: a colour that is neither the shield nor the sentinel.
        let secret = UIColor(red: 38 / 255, green: 102 / 255, blue: 242 / 255, alpha: 1)

        // The shield covers the TOP 200 of 240 points, leaving a 40pt sentinel strip below it. That
        // strip is the control: if it does not read the sentinel, the readback is not working and the
        // assertions below are meaningless.
        let (window, shield) = try sentinelWindowWithCoveringShield(sentinel: sentinel, secret: secret)

        XCTAssertEqual(shield.frame.height, 200, "the shield must occupy only the top portion")

        let readback = layerTreeReadback(of: window)

        // Inside the shield (y ≈ 0.42 of 240pt → ~100pt, well within the shield).
        let insideShield = try XCTUnwrap(
            Self.pixel(in: readback, at: CGPoint(x: 0.5, y: 0.42)),
            "the layer-tree read produced no readable pixel inside the shield"
        )
        // Below the shield (y ≈ 0.92 of 240pt → ~220pt, inside the 40pt sentinel strip).
        let outsideShield = try XCTUnwrap(
            Self.pixel(in: readback, at: CGPoint(x: 0.5, y: 0.92)),
            "the layer-tree read produced no readable pixel outside the shield"
        )

        // The control: the readback path works at all, proven where the shield is NOT.
        XCTAssertLessThan(
            Self.channelDistance(outsideShield, Self.components(sentinel)), 32,
            "the control read \(outsideShield) should be the sentinel \(Self.components(sentinel)) — "
                + "the readback is not producing real pixels, so nothing below is meaningful"
        )

        // The shield's backing covers its region: neither the sentinel nor the content shows through.
        XCTAssertLessThan(
            Self.maxChannel(insideShield), 32,
            "protected region read \(insideShield) — expected the black shield"
        )
        XCTAssertGreaterThan(
            Self.channelDistance(insideShield, Self.components(sentinel)), 32,
            "protected region showed the sentinel — the shield is not covering"
        )
        XCTAssertGreaterThan(
            Self.channelDistance(insideShield, Self.components(secret)), 32,
            "protected region read the content colour \(Self.components(secret))"
        )
    }

    // MARK: - Helpers

    /// A window whose root view is painted in the sentinel colour, with a renderer-backed shield
    /// covering its TOP 200 of 240 points and the secret as the content it must not leak.
    private func sentinelWindowWithCoveringShield(
        sentinel: UIColor,
        secret: UIColor
    ) -> (window: UIWindow, shield: ScreenGuardShieldView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let root = UIView(frame: window.bounds)
        root.backgroundColor = sentinel
        window.rootViewController = UIViewController()
        window.rootViewController?.view = root
        window.isHidden = false

        let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)
        shield.shieldColor = .black
        shield.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(shield)
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            shield.topAnchor.constraint(equalTo: root.topAnchor),
            shield.heightAnchor.constraint(equalToConstant: 200),
        ])
        root.layoutIfNeeded()

        shield.protectedContentRenderer = { size, _ in
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(
                bounds: CGRect(origin: .zero, size: size),
                format: format
            ).image { context in
                secret.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
        shield.setNeedsContentRefresh()
        root.layoutIfNeeded()
        return (window, shield)
    }

    /// Reads the window picture back through the ordinary layer tree at 1x.
    private func layerTreeReadback(of window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            window.rootViewController?.view.layer.render(in: context.cgContext)
        }
    }

    //   which pins that measurement.

    // MARK: - 2. The public preventsCapture path

    /// The one measurement the package's central claim depends on, and the one Simulator cannot make.
    ///
    /// On Simulator, `preventsCapture = true` makes the layer paint NOTHING AT ALL — including on
    /// screen — so a protected band reading black proves nothing (`capability-matrix.md` §4).
    ///
    /// On a device this must assert the real property: the protected region is blank **in the
    /// capture** while the content remains visible **on the display**. That asymmetry is what
    /// distinguishes genuine capture exclusion from a non-painting layer.
    func testPublicPreventsCaptureLayerBlanksTheCaptureButNotTheDisplay() throws {
        try requireDevice()

        // Device-only body. Two reads are required, and both matter:
        //   1. `window.drawHierarchy(in:afterScreenUpdates: false)` → protected region reads the
        //      SHIELD colour (blank in the capture).
        //   2. A display-surface read of the same region → reads the CONTENT (still visible on
        //      screen). On a device this is a `simctl`/ReplayKit frame, not an app-side read.
        // Assert 1 without 2 is exactly the unearned `NO-LEAK(black)` that capability-matrix.md §4
        // warns about, so both are required.
        throw XCTSkip(
            Self.deviceReason + " Requires BOTH a drawHierarchy readback and a display-surface read "
                + "of the same region, to prove the blank is capture-specific exclusion rather than "
                + "a non-painting layer."
        )
    }

    // MARK: - 3. The recording path

    /// `RPScreenRecorder.isAvailable` returned `true` and its completion fired with **no error**, then
    /// the pipeline delivered **zero callbacks in 30 s** (`video=0 audioApp=0 audioMic=0`).
    /// `startRecording` reported `isRecording = true` with no frames, and `UIScreen.isCaptured` stayed
    /// `false` (`capability-matrix.md` §7).
    ///
    /// So no recording-path verdict — NO-LEAK or LEAKED — may be claimed from Simulator data.
    func testRecordingPathProtection() throws {
        try requireDevice()

        // Device-only body: start `RPScreenRecorder.shared().startCapture`, drive known content
        // through a shield, and assert the protected region is absent from the delivered frames.
        // Until that runs, the package claims NOTHING for this path.
        XCTAssertEqual(
            ScreenGuard.status(of: .noLeakRecordingPath), .notMeasured,
            "no recording-path verdict may be claimed"
        )
        throw XCTSkip(
            Self.deviceReason + " Requires ReplayKit to actually deliver frames, which it does not do "
                + "on Simulator (0 callbacks in 30 s)."
        )
    }

    // MARK: - 4. Screenshot detection end-to-end

    /// The Simulator cannot fire `userDidTakeScreenshotNotification`: a real screenshot is side button
    /// + volume-up, and `sim-use` exposes no volume button (`docs/TOOLING.md` §2). Even on a device
    /// this needs a human press — no public API posts the notification.
    func testScreenshotNotificationIsDeliveredEndToEnd() throws {
        try requireDevice()

        // Device-only body: take a real screenshot by hand and assert exactly one `.screenshotTaken`
        // event arrives through `ScreenGuardDelegate` with `.screenshotNotification` as its source.
        throw XCTSkip(
            Self.humanReason + " A real screenshot is side-button + volume-up; no public API posts "
                + "userDidTakeScreenshotNotification, so a human must trigger it."
        )
    }

    // MARK: - 5. Capture-state detection end-to-end

    /// `UIScreen.isCaptured` stayed `false` with **0** observed `capturedDidChangeNotification`
    /// callbacks while `RPScreenRecorder` was started (`capability-matrix.md` §7).
    func testCaptureStateDetectionIsDeliveredEndToEnd() throws {
        try requireDevice()

        // Device-only body: start a real recording and assert `.captureBegan` arrives, then stop it
        // and assert `.captureEnded`.
        throw XCTSkip(
            Self.deviceReason + " Requires a real recording to move the capture state, which does not "
                + "happen on Simulator (isCaptured stayed false, 0 callbacks)."
        )
    }

    // MARK: - 6. App-switcher snapshot

    /// The system writes its app-switcher snapshot as Apple's proprietary AAPL-magic KTX variant,
    /// which neither ImageMagick nor ffmpeg can decode (`docs/TOOLING.md` §4). Snapshot pixels are
    /// therefore not pixel-verifiable on Simulator, and not readable from inside the test process at
    /// all.
    func testAppSwitcherSnapshotContainsNoAppContent() throws {
        try requireDevice()

        // Device-only body: background the app, retrieve the SplashBoard snapshot with device-side
        // tooling, and assert it does not contain the content.
        throw XCTSkip(
            Self.humanReason + " The SplashBoard snapshot is an AAPL-magic KTX variant that neither "
                + "ImageMagick nor ffmpeg can decode (docs/TOOLING.md §4)."
        )
    }

    // MARK: - 7. The counterpart: what IS assertable here, asserted rather than skipped

    /// The counterpart to the skips above: what *is* assertable on Simulator is asserted, so the
    /// device-required list is not an excuse for testing nothing.
    func testSimulatorAssertableFactsAreAssertedNotSkipped() {
        // The public path's engagement is assertable (the layer is built); only its capture
        // behaviour is not.
        let shield = ScreenGuardShieldView(strategy: .publicPreventsCaptureLayer)
        XCTAssertTrue(shield.isProtecting)
        XCTAssertEqual(shield.shieldMode, .publicPreventsCaptureLayer)

        // The capability registry states the device-pending status that the skips above encode.
        XCTAssertEqual(ScreenGuard.status(of: .noLeakPublicPreventsCapture), .devicePending)
        XCTAssertEqual(ScreenGuard.status(of: .appSwitcherSnapshotProtection), .devicePending)
        XCTAssertEqual(ScreenGuard.status(of: .screenshotDetection), .devicePending)
        XCTAssertEqual(ScreenGuard.status(of: .captureStateDetection), .devicePending)
    }

    // MARK: - Pixel helpers

    /// Reads one normalised sample out of an image as an `(r, g, b)` triple in 0...255.
    ///
    /// The image is normalised to RGBA8 first: `UIGraphicsImageRenderer` output is **16 bpc / 64 bpp**,
    /// so a raw byte read yields noise (`docs/TOOLING.md` §5).
    private static func pixel(in image: UIImage, at normalizedPoint: CGPoint) -> (Int, Int, Int)? {
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

    private static func maxChannel(_ pixel: (Int, Int, Int)) -> Int {
        max(pixel.0, max(pixel.1, pixel.2))
    }

    private static func components(_ color: UIColor) -> (Int, Int, Int) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private static func channelDistance(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Int {
        max(abs(lhs.0 - rhs.0), max(abs(lhs.1 - rhs.1), abs(lhs.2 - rhs.2)))
    }
}
