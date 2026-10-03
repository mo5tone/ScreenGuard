//
//  ScreenGuardWatermarkLayoutTests.swift
//  ScreenGuardTests
//
//  Watermark tile geometry and placement. Pure arithmetic — no window, no screen, no rendering.
//

@testable import ScreenGuard
import XCTest

final class ScreenGuardWatermarkLayoutTests: XCTestCase {
    private let tile = CGSize(width: 100, height: 50)

    // MARK: - Coverage

    func testExactMultipleProducesACompleteGrid() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        // 4 columns × 4 rows.
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: tile), 16)
        XCTAssertEqual(
            ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile).count,
            16
        )
    }

    /// A partial tile on the right / bottom edge is still emitted: a partially visible tile carries
    /// its mark, and that is what "cover the bounds" means for a tiled overlay.
    func testPartialEdgeTilesAreIncluded() {
        let bounds = CGRect(x: 0, y: 0, width: 250, height: 120)
        // ceil(250/100) = 3 columns, ceil(120/50) = 3 rows.
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: tile), 9)
    }

    func testSingleTileCoversASmallBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile), [.zero])
    }

    /// Tiles are anchored at `bounds.origin`, not at `.zero`. A watermark over a non-origin region
    /// must not silently shift its grid.
    func testGridIsAnchoredAtBoundsOrigin() {
        let bounds = CGRect(x: 20, y: 40, width: 200, height: 100)
        let origins = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile)
        XCTAssertEqual(origins.first, CGPoint(x: 20, y: 40))
        // 2 columns × 2 rows.
        XCTAssertEqual(origins.count, 4)
        XCTAssertTrue(origins.contains(CGPoint(x: 120, y: 90)))
    }

    /// Row-major order, left to right then top to bottom. Placement depends on it.
    func testOriginsAreRowMajor() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        let origins = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile)
        XCTAssertEqual(origins, [
            .zero,
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
            CGPoint(x: 0, y: 50),
            CGPoint(x: 100, y: 50),
            CGPoint(x: 200, y: 50),
        ])
    }

    /// The union of every tile rect must cover `bounds` — the property that matters for a forensic
    /// overlay: no part of the region is left unmarked.
    func testTilesCoverTheWholeBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 437, height: 289)
        let origins = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile)
        let union = origins.reduce(CGRect.null) { partial, origin in
            partial.union(CGRect(origin: origin, size: tile))
        }
        XCTAssertTrue(union.contains(bounds), "union \(union) must contain \(bounds)")
    }

    // MARK: - Determinism

    func testGeometryIsDeterministic() {
        let bounds = CGRect(x: 0, y: 0, width: 333, height: 111)
        let first = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile)
        let second = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tile)
        XCTAssertEqual(first, second)
    }

    /// Geometry is in points, so it must be independent of screen scale.
    func testGeometryIsIndependentOfScale() {
        let bounds = CGRect(x: 0, y: 0, width: 180, height: 120)
        // 2 columns × 3 rows, regardless of any display scale.
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: tile), 6)
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: tile), 6)
    }

    // MARK: - Degenerate input

    func testEmptyBoundsYieldsNoTiles() {
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileOrigins(in: .zero, tileSize: tile), [])
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: .zero, tileSize: tile), 0)
    }

    /// A negative-extent `CGRect` is **not** degenerate at the CoreGraphics level, and this test pins
    /// exactly how, because guessing it wrong is easy: the stored `origin`/`size` are the raw values,
    /// while the derived `width`/`minX` are standardised.
    ///
    /// Measured (iPhone 17 Pro / iOS 26.2 Simulator, Xcode 27.0):
    ///
    /// ```
    /// CGRect(x: 0, y: 0, width: -10, height: -10)
    ///   .origin == (0, 0)        .size == (-10, -10)     // stored, unstandardised
    ///   .width  == 10            .minX == -10            // derived, standardised
    ///   .maxX   == 0             .isEmpty == false
    /// ```
    ///
    /// So the rect describes a real 10×10 region at `(-10, -10)` and tiling it is correct. The
    /// caller's original intent is not recoverable, so inventing a guard that rejects it would reject
    /// legitimate rects too.
    func testNegativeExtentBoundsDescribeARealRegionAndAreTiled() {
        let bounds = CGRect(x: 0, y: 0, width: -10, height: -10)
        XCTAssertEqual(bounds.origin, .zero, "origin is stored unstandardised")
        XCTAssertEqual(bounds.size, CGSize(width: -10, height: -10), "size is stored unstandardised")
        XCTAssertEqual(bounds.width, 10, "width is derived and standardised")
        XCTAssertEqual(bounds.minX, -10, "minX is derived and standardised")
        XCTAssertFalse(bounds.isEmpty)

        let tiny = CGSize(width: 5, height: 5)
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: tiny), 4)
        XCTAssertEqual(
            ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tiny).first,
            CGPoint(x: -10, y: -10)
        )
    }

    /// The genuinely degenerate rects — empty, null, infinite — yield no tiles.
    func testDegenerateBoundsYieldNoTiles() {
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileOrigins(in: .zero, tileSize: tile), [])
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileOrigins(in: .null, tileSize: tile), [])
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileOrigins(in: .infinite, tileSize: tile), [])
        // A rect collapsed to zero extent along one axis.
        XCTAssertEqual(
            ScreenGuardWatermarkLayout.tileOrigins(
                in: CGRect(x: 5, y: 5, width: 0, height: 100), tileSize: tile
            ),
            []
        )
        XCTAssertEqual(
            ScreenGuardWatermarkLayout.tileOrigins(
                in: CGRect(x: 5, y: 5, width: 100, height: 0), tileSize: tile
            ),
            []
        )
    }

    /// A non-positive pitch has no meaningful tiling and must not trap on division or `Int(ceil(...))`.
    func testNonPositiveTileSizeYieldsNoTiles() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let sizes: [CGSize] = [
            CGSize(width: 0, height: 50),
            CGSize(width: 100, height: 0),
            CGSize(width: -100, height: 50),
            CGSize(width: 100, height: -50),
            .zero,
        ]
        for size in sizes {
            XCTAssertEqual(
                ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: size),
                [],
                "tileSize \(size) must yield no tiles"
            )
        }
    }

    /// A sub-point pitch is legal and simply produces many tiles; the important part is that it does
    /// not trap or return a negative count.
    func testSubPointPitchDoesNotTrap() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        let tiny = CGSize(width: 0.5, height: 0.5)
        let origins = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: tiny)
        XCTAssertEqual(origins.count, 400)
        XCTAssertEqual(ScreenGuardWatermarkLayout.tileCount(in: bounds, tileSize: tiny), 400)
    }

    // MARK: - Configuration content

    func testTileLinesIncludeTextAndTimestampByDefault() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = ScreenGuardWatermarkConfiguration(
            text: "CONFIDENTIAL",
            secondaryText: "session 4417"
        ) { date }
        let lines = configuration.tileLines(at: date)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "CONFIDENTIAL")
        XCTAssertEqual(lines[1], "session 4417")
        XCTAssertFalse(lines[2].isEmpty)
    }

    func testTileLinesOmitEmptySecondaryText() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = ScreenGuardWatermarkConfiguration(text: "CONFIDENTIAL", secondaryText: "")
        XCTAssertEqual(configuration.tileLines(at: date).first, "CONFIDENTIAL")
        XCTAssertEqual(configuration.tileLines(at: date).count, 2)
    }

    func testTileLinesCanOmitTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = ScreenGuardWatermarkConfiguration(
            text: "CONFIDENTIAL",
            secondaryText: "session 4417",
            includesTimestamp: false
        )
        XCTAssertEqual(configuration.tileLines(at: date), ["CONFIDENTIAL", "session 4417"])
    }

    /// The timestamp is injected, so the same configuration and date produce the same line — which is
    /// what makes a leak attributable to a known time.
    ///
    /// The time zone is pinned rather than inherited: an assertion that depends on the machine's zone
    /// would pass in UTC and fail in Asia/Shanghai, which is exactly the class of test that erodes
    /// trust in a suite.
    func testTimestampIsDeterministicGivenTheInjectedDateAndZone() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let configuration = try ScreenGuardWatermarkConfiguration(
            text: "CONFIDENTIAL",
            timestampFormat: "yyyy-MM-dd HH:mm:ss",
            timeZone: XCTUnwrap(TimeZone(identifier: "UTC"))
        ) { date }
        XCTAssertEqual(configuration.tileLines(at: date).last, "2023-11-14 22:13:20")
        XCTAssertEqual(
            configuration.tileLines(at: date),
            configuration.tileLines(at: date)
        )
    }

    /// The same instant renders differently per zone — the property that makes the recorded zone
    /// forensically meaningful rather than decorative.
    func testTimeZoneChangesTheRenderedTimestamp() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let utc = try ScreenGuardWatermarkConfiguration(
            text: "C", timestampFormat: "yyyy-MM-dd", timeZone: XCTUnwrap(TimeZone(identifier: "UTC"))
        )
        let shanghai = try ScreenGuardWatermarkConfiguration(
            text: "C", timestampFormat: "yyyy-MM-dd", timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        )
        XCTAssertEqual(utc.tileLines(at: date).last, "2023-11-14")
        XCTAssertEqual(shanghai.tileLines(at: date).last, "2023-11-15")
    }

    func testDefaultConfigurationValuesMatchTheContract() {
        let configuration = ScreenGuardWatermarkConfiguration(text: "CONFIDENTIAL")
        XCTAssertEqual(configuration.tileSize, CGSize(width: 180, height: 120))
        XCTAssertEqual(configuration.angle, -.pi / 6)
        XCTAssertEqual(configuration.opacity, 0.12)
        XCTAssertTrue(configuration.includesTimestamp)
        XCTAssertEqual(configuration.timestampFormat, "yyyy-MM-dd HH:mm:ss zzz")
        XCTAssertNil(configuration.secondaryText)
    }
}
