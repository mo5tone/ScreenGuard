//
//  DemoGeometry.swift
//  ScreenGuardDemo
//
//  The one place the sensitive content's colour, the sentinel's colour and the probe page's
//  normalised region rectangles are defined.
//
//  WHY THESE CONSTANTS ARE SHARED WITH THE HOST SCRIPT
//  --------------------------------------------------
//  `Scripts/verify_capture.sh` samples the same regions out of the PNGs the app writes. If the two
//  sides could drift, a green run could mean "the app moved the region" rather than "protection
//  worked". So the app also *emits* these rectangles in its JSON artifact, and the script fails the
//  run if they disagree with its own copy.
//
//  THE SENTINEL IS NOT DECORATION. A black region is ambiguous: it can mean "protection worked" or
//  "nothing rendered there" (`docs/TOOLING.md` §3). Every protected region therefore sits over a
//  distinctly-coloured sentinel, so a blanked region reads the sentinel rather than an unexplained
//  black — and a *non-painting* region reads black instead, which is a different, diagnosable
//  outcome.
//

import CoreGraphics
import Foundation
import ScreenGuard
import UIKit

/// Colours, copy and geometry shared by the demo and the verification script.
enum DemoGeometry {

    // MARK: - Colours

    /// The colour of the sensitive content itself. A capture that contains this colour inside a
    /// protected region has leaked.
    static let sensitiveColour = UIColor(red: 38 / 255, green: 102 / 255, blue: 242 / 255, alpha: 1)

    /// The colour painted *behind* every protected region. Reading this inside a protected region
    /// means the region's pixels were excluded from the capture (the good outcome for the private
    /// path); reading black means the shield's opaque backing was captured instead.
    static let sentinelColour = UIColor(red: 200 / 255, green: 0, blue: 160 / 255, alpha: 1)

    // MARK: - Copy

    /// The sensitive string shown inside the protected regions, so the region is identifiable to a
    /// human as well as to a pixel check.
    static let secretTitle = "ACCT-9930-SECRET"

    /// A second line, so the region reads as a plausible account panel.
    static let secretDetail = "BALANCE 1,234,567.89"

    // MARK: - Probe page geometry

    /// One band of the scripted probe page.
    ///
    /// `normalizedRect` is the whole region (label included). `bodyRect` is the solid-colour part
    /// **with no text in it**, which is the only part the script samples — sampling across text is a
    /// documented way to produce a false black (`docs/TOOLING.md` §5).
    struct Region {
        /// Stable identifier used in every artifact line.
        let name: String
        /// The whole region, in normalised window coordinates.
        let normalizedRect: CGRect
        /// The text-free sub-rectangle that is actually sampled.
        let bodyRect: CGRect
        /// What this region is for, in one line.
        let purpose: String
    }

    /// The unshielded control. The same content, with no protection at all. It **must** show the
    /// sensitive colour in every capture path — if it does not, the capture path is not imaging
    /// content and no other verdict from that path means anything.
    static let control = Region(
        name: "control",
        normalizedRect: CGRect(x: 0.06, y: 0.10, width: 0.88, height: 0.20),
        bodyRect: CGRect(x: 0.10, y: 0.20, width: 0.80, height: 0.08),
        purpose: "unshielded control — must read the sensitive colour in the capture"
    )

    /// The default public path: `AVSampleBufferDisplayLayer` with `preventsCapture = true` over an
    /// opaque black shield.
    ///
    /// ⚠️ On Simulator this makes the layer paint nothing at all, including on screen, so this region
    /// is **expected to be black on the display too** — which is why its capture result is
    /// unearned and reported as device-required rather than as a pass
    /// (`docs/TOOLING.md` §7.1).
    static let publicShield = Region(
        name: "publicShield",
        normalizedRect: CGRect(x: 0.06, y: 0.36, width: 0.88, height: 0.20),
        bodyRect: CGRect(x: 0.10, y: 0.46, width: 0.80, height: 0.08),
        purpose: "public preventsCapture layer — device-required on Simulator"
    )

    /// The opt-in private path: the shield's layer is reparented into a private
    /// `_UITextLayoutCanvasView` descendant.
    ///
    /// ⚠️ PRIVATE API. Non-contract, fragile across iOS releases, App Review risk, never a security
    /// guarantee (`docs/api-contract.md` §9). It is the only mechanism measured to blank *arbitrary*
    /// content in the app-side render path while still painting on the display.
    static let privateShield = Region(
        name: "privateShield",
        normalizedRect: CGRect(x: 0.06, y: 0.62, width: 0.88, height: 0.20),
        bodyRect: CGRect(x: 0.10, y: 0.72, width: 0.80, height: 0.08),
        purpose: "opt-in private secure-layer swap — measured on the app-side render path"
    )

    /// Every probe region, in page order.
    static let probeRegions: [Region] = [control, publicShield, privateShield]

    // MARK: - SwiftUI-route probe page
    //
    // A THIRD probe page, added by the F-R2-1 repair (`docs/api-contract.md` §13 A3). It exercises
    // the package's own SwiftUI entry point — `.screenGuardProtected(strategy: .privateSecureLayer)`
    // — rather than `ScreenGuardShieldView.protectedContentView`, because that route supplies content
    // only through a RENDER CLOSURE and used to render nothing at all on the private path while
    // reporting `isProtecting = true`.
    //
    // It is a separate page rather than more bands on the no-leak page on purpose: the three-region
    // page is the evidence base for everything measured so far, and adding bands to it would change
    // the geometry every existing verdict was taken against.
    //
    // The two regions are the same control/shield pair, for the same reasons:
    //   control              — unshielded SwiftUI content; MUST read the sensitive colour, or the
    //                          read path is not imaging content and nothing else here means anything;
    //   swiftUIPrivateShield — the modifier on the private strategy: it must be READABLE and must not
    //                          read the sensitive colour in the app-side render, while the host
    //                          contrast still shows the content (exclusion, not a non-painting layer).

    /// Unshielded SwiftUI content, hosted through the same `UIHostingController` route the shielded
    /// region uses, so the calibration differs from the shielded region in exactly one respect.
    static let swiftUIControl = Region(
        name: "swiftUIControl",
        normalizedRect: CGRect(x: 0.06, y: 0.14, width: 0.88, height: 0.24),
        bodyRect: CGRect(x: 0.10, y: 0.24, width: 0.80, height: 0.10),
        purpose: "SwiftUI content with no shield — must read the sensitive colour in the capture"
    )

    /// `screenGuardProtected(strategy: .privateSecureLayer)` — the route F-R2-1 is about.
    static let swiftUIPrivateShield = Region(
        name: "swiftUIPrivateShield",
        normalizedRect: CGRect(x: 0.06, y: 0.46, width: 0.88, height: 0.24),
        bodyRect: CGRect(x: 0.10, y: 0.56, width: 0.80, height: 0.10),
        purpose: "screenGuardProtected(strategy: .privateSecureLayer) — the SwiftUI private route"
    )

    /// Both SwiftUI-route probe regions, in page order.
    static let swiftUIProbeRegions: [Region] = [swiftUIControl, swiftUIPrivateShield]

    // MARK: - Watermark probe page
    //
    // A second, separate probe page. The watermark is a DETERRENT AND FORENSIC measure: it removes no
    // pixels from any capture and prevents nothing (docs/api-contract.md §3.3). The page therefore
    // carries a matched PAIR of plain-colour bands — one wearing the mark and one not — so the check
    // can prove two opposite things at once:
    //
    //   * the marked band is NOT flat: the watermark really is drawn into the app-side capture;
    //   * the unmarked control band IS flat: the measure has discriminating power, so the first
    //     result is not just "this read path shows noise".
    //
    // Neither band is a no-leak claim, and neither is graded as one.

    /// Tile pitch for the watermark probe. Deliberately small enough to put several tiles on a band,
    /// so a single tile failing to draw is visible in the aggregate.
    static let watermarkTileSize = CGSize(width: 140, height: 80)

    /// White over the sensitive blue: a glyph pixel lands far enough from the base colour that a
    /// threshold of 24 per channel cannot confuse the two.
    static let watermarkOpacity: CGFloat = 0.28

    /// Per-channel distance above which a sampled pixel counts as "wearing the mark".
    ///
    /// 24 is comfortably below the ~61-per-channel shift a glyph produces at 0.28 opacity over the
    /// sensitive blue, and comfortably above the few units of noise the capture pipeline introduces —
    /// which the flat control band measures rather than assumes.
    static let watermarkDeviationThreshold = 24

    /// The watermark configuration, built once so the page and the artifact agree.
    ///
    /// The timestamp provider is fixed rather than `Date.init` so a run's artifact is reproducible;
    /// the timestamp's *presence* is what the artifact records, not its value.
    static var watermarkConfiguration: ScreenGuardWatermarkConfiguration {
        let fixed = Date(timeIntervalSince1970: 1_756_000_000)
        return ScreenGuardWatermarkConfiguration(
            text: "CONFIDENTIAL",
            secondaryText: "demo session 4417",
            tileSize: watermarkTileSize,
            opacity: watermarkOpacity,
            color: .white,
            timestampProvider: { fixed }
        )
    }

    /// The band wearing the watermark.
    static let watermarkMarked = Region(
        name: "watermarkMarked",
        normalizedRect: CGRect(x: 0.06, y: 0.16, width: 0.88, height: 0.24),
        bodyRect: CGRect(x: 0.10, y: 0.19, width: 0.80, height: 0.18),
        purpose: "the watermark IS drawn into the capture — deterrent only, removes no pixels"
    )

    /// The matched band with no watermark. Must read a flat colour.
    static let watermarkControl = Region(
        name: "watermarkControl",
        normalizedRect: CGRect(x: 0.06, y: 0.48, width: 0.88, height: 0.24),
        bodyRect: CGRect(x: 0.10, y: 0.51, width: 0.80, height: 0.18),
        purpose: "the same card WITHOUT the watermark — must read a flat colour (calibration)"
    )

    /// Both watermark-probe regions, in page order.
    static let watermarkProbeRegions: [Region] = [watermarkMarked, watermarkControl]

    // MARK: - Helpers

    /// Converts a normalised rect into `view` coordinates.
    ///
    /// - Parameters:
    ///   - normalized: The rect, in 0-1 window space.
    ///   - size: The container size.
    /// - Returns: The rect in points.
    static func absolute(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    /// `"r,g,b"` for an artefact line.
    static func describe(_ colour: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "\(Int((red * 255).rounded())),\(Int((green * 255).rounded())),\(Int((blue * 255).rounded()))"
    }

    /// `"x,y,w,h"` with four decimals, for an artefact line.
    static func describe(_ rect: CGRect) -> String {
        String(format: "%.4f,%.4f,%.4f,%.4f", rect.minX, rect.minY, rect.width, rect.height)
    }

    /// `"x,y"` with two decimals, for an artefact line.
    static func describe(_ point: CGPoint) -> String {
        String(format: "%.2f,%.2f", point.x, point.y)
    }

    /// `"w,h"` with two decimals, for an artefact line.
    static func describe(_ size: CGSize) -> String {
        String(format: "%.2f,%.2f", size.width, size.height)
    }
}
