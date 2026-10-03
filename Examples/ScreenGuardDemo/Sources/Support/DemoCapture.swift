//
//  DemoCapture.swift
//  ScreenGuardDemo
//
//  The demo's verification engine: take the app-side read of the window, hand the image to the user,
//  and classify a few known regions so the user gets a verdict instead of an impression.
//
//  WHY THIS IS THE CENTRE OF THE DEMO
//  ----------------------------------
//  `window.drawHierarchy(in:afterScreenUpdates: false)` is the read that a real capture contains on
//  its app side, and it is the read `Scripts/verify_capture.sh` grades (`docs/TOOLING.md` §2). It is
//  available on a Simulator, which means a user can produce genuine no-leak evidence here, by hand,
//  without a device — instead of being told to imagine it.
//
//  What this read is NOT: the host-side display capture. `xcrun simctl io screenshot`, the
//  Simulator's own screenshot and the harness's CONTRAST image all capture the host display surface,
//  which bypasses render-server protection by construction and is never evidence of anything
//  (`docs/TOOLING.md` §2). The demo says so next to the result rather than letting a user confuse the
//  two and conclude the library is broken.
//
//  AND IT CLOSES A KNOWN EVIDENCE GAP
//  ----------------------------------
//  A blank region in a read has two possible explanations: the pixels were excluded, or the read path
//  never painted anything there. A single reading cannot tell them apart — that ambiguity is exactly
//  what review round 2 recorded as an open medium finding (F-R2-1's neighbour, the "unclosed
//  alternative explanation" in `docs/evidence/review-round2.md`).
//
//  The demo closes it in the way the reviewers asked for: **the capture always includes an unshielded
//  control card.** If the control carries its secret in the same image while the protected card does
//  not, the read path demonstrably works and the exclusion is real. If the control is also blank, the
//  reading is uninformative and the demo says so instead of claiming success.
//

import SwiftUI
import UIKit

/// One region's reading out of a captured frame.
struct DemoCaptureReading: Identifiable {

    /// Identity for `ForEach`.
    let id = UUID()

    /// What the region is, in the user's words.
    let label: String

    /// The region's verdict.
    let verdict: DemoCaptureVerdict

    /// The sampled median colour, as `"r,g,b"`.
    let colour: String
}

/// What a sampled region read.
///
/// The vocabulary matches the verification script's on purpose, so a user who later reads
/// `docs/evidence/verification-report.md` is reading the same words.
enum DemoCaptureVerdict: String {

    /// The sensitive content's own colour: it is in the capture.
    case sensitive = "SENSITIVE"

    /// The sentinel behind the region: its pixels were excluded from the read.
    case sentinel = "SENTINEL"

    /// Black and no signal. The region painted nothing, or an opaque black backing was captured —
    /// the two are indistinguishable from one read (`docs/TOOLING.md` §7.1).
    case black = "BLACK"

    /// Neither reference colour and not black.
    case other = "OTHER"

    /// No pixels could be read.
    case unreadable = "UNREADABLE"

    /// Whether this verdict is only explainable by the region being excluded.
    var indicatesExclusion: Bool { self == .sentinel }
}

/// A frame the user captured themselves.
struct DemoCapturedFrame: Identifiable {

    /// Identity for the sheet.
    let id = UUID()

    /// The app-side read, ready to display.
    let image: UIImage

    /// Per-region verdicts, in the order the regions were supplied.
    let readings: [DemoCaptureReading]

    /// The verdict of the unshielded control, or `nil` when no control was sampled.
    ///
    /// This is what makes the other verdicts meaningful: without a control that demonstrably carries
    /// its content into the same image, a blank region proves nothing.
    let controlVerdict: DemoCaptureVerdict?

    /// Whether the read path is demonstrably working, judged from the control alone.
    var readPathIsDemonstrated: Bool {
        guard let controlVerdict else { return false }
        return controlVerdict == .sensitive
    }
}

/// Takes the app-side read and classifies regions on it.
enum DemoCapture {

    /// Tolerance per channel when matching against the demo's reference colours.
    private static let tolerance = 40

    /// The window to read.
    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// Captures the window and classifies `regions`.
    ///
    /// - Parameter regions: `(label, frame)` pairs in window coordinates, sampled in order. Supply
    ///   the unshielded control first so its verdict can be used to qualify the rest.
    /// - Returns: The captured frame, or `nil` when no window or image was available.
    @MainActor
    static func capture(regions: [(label: String, frame: CGRect)]) -> DemoCapturedFrame? {
        guard let window = keyWindow,
              let cgImage = AppSideReadback.appRender(window: window),
              let bitmap = AppSideReadback.Bitmap(image: cgImage)
        else { return nil }

        // `appRender` renders `window.bounds` at `scale = 1`, so image pixels and window points are
        // the same units and a frame can be sampled directly.
        let readings = regions.map { region -> DemoCaptureReading in
            let colour = medianColour(in: bitmap, frame: region.frame)
            let verdict = classify(colour)
            return DemoCaptureReading(
                label: region.label,
                verdict: verdict,
                colour: colour.map { "\($0.r),\($0.g),\($0.b)" } ?? "unreadable"
            )
        }

        let control = readings.first { $0.label == Self.controlLabel }?.verdict

        return DemoCapturedFrame(
            image: UIImage(cgImage: cgImage),
            readings: readings,
            controlVerdict: control
        )
    }

    /// The label the unshielded control region must carry.
    static let controlLabel = "Control (unshielded)"

    /// The median colour over a grid inside `frame`, or `nil` when nothing could be sampled.
    ///
    /// A grid rather than every pixel: the region is flat by construction, and a fixed grid keeps the
    /// cost the same regardless of how large the frame is.
    private static func medianColour(
        in bitmap: AppSideReadback.Bitmap,
        frame: CGRect
    ) -> (r: Int, g: Int, b: Int)? {
        // Inset so a border, a corner radius or a one-pixel seam cannot dominate the reading.
        let inset = frame.insetBy(dx: frame.width * 0.15, dy: frame.height * 0.15)
        guard inset.width >= 2, inset.height >= 2 else { return nil }

        var reds: [Int] = []
        var greens: [Int] = []
        var blues: [Int] = []
        let steps = 9
        for row in 0..<steps {
            for column in 0..<steps {
                let x = inset.minX + inset.width * (CGFloat(column) + 0.5) / CGFloat(steps)
                let y = inset.minY + inset.height * (CGFloat(row) + 0.5) / CGFloat(steps)
                guard let pixel = bitmap.pixel(x: Int(x.rounded()), y: Int(y.rounded())) else {
                    continue
                }
                reds.append(pixel.r)
                greens.append(pixel.g)
                blues.append(pixel.b)
            }
        }
        guard !reds.isEmpty else { return nil }
        return (median(reds), median(greens), median(blues))
    }

    /// The median of `values`. Sorted in place on a local copy.
    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Classifies a sampled colour against the demo's reference colours.
    private static func classify(_ colour: (r: Int, g: Int, b: Int)?) -> DemoCaptureVerdict {
        guard let colour else { return .unreadable }

        if matches(colour, DemoGeometry.sensitiveColour) { return .sensitive }
        if matches(colour, DemoGeometry.sentinelColour) { return .sentinel }
        if colour.r < 12, colour.g < 12, colour.b < 12 { return .black }
        return .other
    }

    /// Whether `colour` is within tolerance of `reference`, per channel.
    private static func matches(
        _ colour: (r: Int, g: Int, b: Int),
        _ reference: UIColor
    ) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard reference.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        let target = (
            r: Int((red * 255).rounded()),
            g: Int((green * 255).rounded()),
            b: Int((blue * 255).rounded())
        )
        return abs(colour.r - target.r) <= tolerance
            && abs(colour.g - target.g) <= tolerance
            && abs(colour.b - target.b) <= tolerance
    }
}
