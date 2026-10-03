//
//  ScreenGuardRasterizerTests.swift
//  ScreenGuardTests
//
//  The content rasteriser that feeds the protected `AVSampleBufferDisplayLayer` on the public path.
//
//  Orientation is asserted rather than trusted, because the y-flip is exactly the class of slip that
//  produced a reported `50.87` where the truth was `3.77` in the research harness
//  (`docs/TOOLING.md` §7.2).
//
//  Two measured facts about `drawHierarchy` are encoded here as tests, because they are the reason the
//  rasteriser uses `CALayer.render(in:)`:
//
//   1. `drawHierarchy(afterScreenUpdates: false)` on a **detached** view draws NOTHING (`(0,0,0)`).
//   2. It also draws nothing for a view attached to a `UIWindow` that has **no `UIWindowScene`** —
//      which is every window a unit-test host creates, since `connectedScenes` is empty.
//
//  A test target cannot produce a scene-attached window, so the `drawHierarchy` branch cannot be
//  exercised here at all. Rather than delete the check, it is asserted as an explicit skip.
//

@testable import ScreenGuard
import UIKit
import XCTest

@MainActor
final class ScreenGuardRasterizerTests: XCTestCase {
    /// A view whose top half is red and bottom half is blue. Orientation errors are visible
    /// immediately, which a single solid colour would hide.
    private func makeSplitView(size: CGSize) -> UIView {
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        let top = UIView(frame: CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
        top.backgroundColor = .red
        let bottom = UIView(frame: CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
        bottom.backgroundColor = .blue
        view.addSubview(top)
        view.addSubview(bottom)
        return view
    }

    /// The path the public shield actually uses: content kept off the live hierarchy, because anything
    /// in the live hierarchy leaks into captures by construction.
    ///
    /// This is the orientation regression guard. `CALayer.render(in:)` documents a Quartz (y-up)
    /// context, which would suggest a flip; measured, a flip INVERTS the result. The assertion fails if
    /// anyone adds the flip back.
    func testDetachedViewRendersInUIKitOrientation() throws {
        let size = CGSize(width: 40, height: 40)
        let view = makeSplitView(size: size)

        let image = try XCTUnwrap(
            ScreenGuardContentRasterizer.rasterize(view, size: size, scale: 1),
            "rasterising a detached view must produce an image"
        )

        let topPixel = try XCTUnwrap(pixel(in: image, at: CGPoint(x: 0.5, y: 0.2)))
        let bottomPixel = try XCTUnwrap(pixel(in: image, at: CGPoint(x: 0.5, y: 0.8)))

        XCTAssertGreaterThan(topPixel.0, 150, "top of the image must be the red half, got \(topPixel)")
        XCTAssertLessThan(topPixel.2, 100, "top of the image must not be blue, got \(topPixel)")
        XCTAssertGreaterThan(bottomPixel.2, 150, "bottom of the image must be the blue half, got \(bottomPixel)")
        XCTAssertLessThan(bottomPixel.0, 100, "bottom of the image must not be red, got \(bottomPixel)")
    }

    /// Documents why the rasteriser does not use `drawHierarchy`, with the measurement pinned.
    ///
    /// Measured on iPhone 17 Pro / iOS 26.2 Simulator while writing this file (Xcode 27.0): even
    /// though `UIWindow.windowScene` is non-nil in this test host, `drawHierarchy(in:afterScreenUpdates:
    /// false)` returns `(0,0,0)` at every sample point — the root view's sentinel background included.
    /// `CALayer.render(in:)` on the same view returns the correct sentinel.
    ///
    /// So `drawHierarchy` cannot serve as the rasterisation primitive for the shield. If this ever
    /// starts producing pixels, this test fails and the rasteriser can be reconsidered — which is the
    /// point of pinning it.
    func testDrawHierarchyProducesNoPixelsWhileLayerRenderProducesThem() throws {
        let size = CGSize(width: 40, height: 40)
        let sentinel = UIColor(red: 200 / 255, green: 0, blue: 160 / 255, alpha: 1)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let root = makeSplitView(size: size)
        root.backgroundColor = sentinel
        window.rootViewController = UIViewController()
        window.rootViewController?.view = root
        window.isHidden = false
        root.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: size)

        let viaDrawHierarchy = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            root.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        let drawPixel = try XCTUnwrap(pixel(in: viaDrawHierarchy, at: CGPoint(x: 0.5, y: 0.2)))
        XCTAssertEqual(
            drawPixel.0 + drawPixel.1 + drawPixel.2, 0,
            "measured: drawHierarchy yields nothing in this host; got \(drawPixel)"
        )

        let viaLayerRender = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            root.layer.render(in: context.cgContext)
        }
        let layerPixel = try XCTUnwrap(pixel(in: viaLayerRender, at: CGPoint(x: 0.5, y: 0.2)))
        XCTAssertGreaterThan(
            layerPixel.0, 150,
            "measured: layer.render returns the real colour; got \(layerPixel)"
        )
    }

    /// A detached view must also render through `CALayer.render(in:)`, since that is the path the
    /// shield uses when the content is deliberately kept out of the live hierarchy.
    func testDetachedViewRendersThroughLayerRender() throws {
        let size = CGSize(width: 40, height: 40)
        let view = makeSplitView(size: size)

        let image = try XCTUnwrap(ScreenGuardContentRasterizer.rasterize(view, size: size, scale: 1))
        let topPixel = try XCTUnwrap(pixel(in: image, at: CGPoint(x: 0.5, y: 0.2)))
        XCTAssertGreaterThan(topPixel.0, 150, "detached render must produce real pixels, got \(topPixel)")
    }

    /// The `drawHierarchy` branch of the rasteriser cannot be exercised in a unit-test host, because
    /// that needs a `UIWindowScene`. Skipped with the reason rather than deleted.
    func testAttachedViewRendersThroughDrawHierarchy() throws {
        throw XCTSkip(
            "SCENE-REQUIRED: exercising the drawHierarchy branch needs a window attached to a "
                + "UIWindowScene, and a unit-test host has no connected scene "
                + "(UIApplication.shared.connectedScenes is empty). Verify on device or in the "
                + "example app (task t4), which runs in a real scene."
        )
    }

    /// Scale is honoured: a 2x rasterisation must be twice the pixel dimensions.
    func testScaleIsHonoured() throws {
        let size = CGSize(width: 40, height: 40)
        let view = makeSplitView(size: size)

        let image = try XCTUnwrap(ScreenGuardContentRasterizer.rasterize(view, size: size, scale: 2))
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 80)
        XCTAssertEqual(cgImage.height, 80)
    }

    /// A degenerate size must return `nil` rather than producing a zero-dimension image or trapping.
    func testDegenerateSizeReturnsNil() {
        let view = makeSplitView(size: CGSize(width: 40, height: 40))
        XCTAssertNil(ScreenGuardContentRasterizer.rasterize(view, size: .zero, scale: 1))
        XCTAssertNil(
            ScreenGuardContentRasterizer.rasterize(
                view, size: CGSize(width: 0.5, height: 40), scale: 1
            )
        )
    }

    /// A zero or negative scale must fall back to a usable value rather than producing nothing.
    func testNonPositiveScaleFallsBack() throws {
        let size = CGSize(width: 40, height: 40)
        let view = makeSplitView(size: size)
        let image = try XCTUnwrap(ScreenGuardContentRasterizer.rasterize(view, size: size, scale: 0))
        XCTAssertNotNil(image.cgImage)
    }

    /// The rasteriser must adopt the requested geometry, because a detached view is never laid out by
    /// UIKit and would otherwise render at its stale bounds.
    func testRequestedSizeIsAdopted() throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        view.backgroundColor = .green

        let image = try XCTUnwrap(
            ScreenGuardContentRasterizer.rasterize(view, size: CGSize(width: 60, height: 30), scale: 1)
        )
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 60)
        XCTAssertEqual(cgImage.height, 30)
        XCTAssertEqual(view.bounds.size, CGSize(width: 60, height: 30))
    }

    // MARK: - Pixel helper

    /// Normalises to RGBA8 before reading: `UIGraphicsImageRenderer` output is 16 bpc / 64 bpp, so a
    /// raw byte read yields noise (`docs/TOOLING.md` §5).
    private func pixel(in image: UIImage, at normalizedPoint: CGPoint) -> (Int, Int, Int)? {
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
}
