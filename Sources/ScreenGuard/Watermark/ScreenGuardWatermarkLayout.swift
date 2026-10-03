//
//  ScreenGuardWatermarkLayout.swift
//  ScreenGuard
//
//  Pure tiling geometry. Separated from the view so it is unit-testable without a window, without a
//  screen, and without UIKit rendering. See docs/api-contract.md §6.6.
//
//  The watermark is a DETERRENT AND FORENSIC measure. It removes NO pixels from any capture and
//  prevents nothing. Nothing in this file is a security control.
//

import CoreGraphics
import Foundation

/// Pure tiling geometry for the forensic watermark.
///
/// Deterministic and independent of screen scale: a caller passes points, and gets points back. That
/// is what makes it testable, and what makes a leaked image attributable to a known layout.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardWatermarkLayout: Equatable, Sendable {
    /// Top-left origins of every tile needed to cover `bounds`, including the partial tiles on the
    /// right and bottom edges.
    ///
    /// Tiles are laid out on a grid anchored at `bounds.origin`, row by row (left to right, top to
    /// bottom). A tile is emitted whenever its origin lies inside `bounds`; the last row and column
    /// may therefore overhang the edge, which is what "cover the bounds" means for a tiled overlay —
    /// a partially visible tile still carries its mark.
    ///
    /// Degenerate inputs are handled without trapping:
    /// - an empty, null or infinite `bounds` yields `[]`;
    /// - a non-positive `tileSize` dimension yields `[]` (there is no meaningful pitch).
    ///
    /// - Note: A negative-extent `CGRect` is **not** rejected. CoreGraphics stores `origin`/`size`
    ///   unstandardised but derives `width`/`minX` standardised, so
    ///   `CGRect(x: 0, y: 0, width: -10, height: -10)` describes a real 10×10 region at `(-10, -10)`
    ///   and is tiled as such. The caller's original intent is not recoverable from the `CGRect`, so
    ///   guessing it would reject legitimate rects too. The guard tests `minX`/`minY` against
    ///   `maxX`/`maxY`, which is what actually distinguishes a real region from an empty one.
    ///
    /// - Parameters:
    ///   - bounds: The rect to cover, in points.
    ///   - tileSize: The tile pitch, in points.
    /// - Returns: The tile origins, in row-major order.
    public static func tileOrigins(in bounds: CGRect, tileSize: CGSize) -> [CGPoint] {
        guard !bounds.isNull, !bounds.isInfinite else {
            return []
        }
        guard bounds.maxX > bounds.minX, bounds.maxY > bounds.minY else {
            return []
        }
        guard tileSize.width > 0, tileSize.height > 0 else {
            return []
        }

        let columns = Int(ceil(bounds.width / tileSize.width))
        let rows = Int(ceil(bounds.height / tileSize.height))

        var origins: [CGPoint] = []
        origins.reserveCapacity(columns * rows)

        for row in 0 ..< rows {
            for column in 0 ..< columns {
                origins.append(
                    CGPoint(
                        x: bounds.minX + CGFloat(column) * tileSize.width,
                        y: bounds.minY + CGFloat(row) * tileSize.height
                    )
                )
            }
        }
        return origins
    }

    /// Number of tiles `tileOrigins(in:tileSize:)` returns.
    ///
    /// - Parameters:
    ///   - bounds: The rect to cover, in points.
    ///   - tileSize: The tile pitch, in points.
    /// - Returns: The tile count.
    public static func tileCount(in bounds: CGRect, tileSize: CGSize) -> Int {
        tileOrigins(in: bounds, tileSize: tileSize).count
    }
}
