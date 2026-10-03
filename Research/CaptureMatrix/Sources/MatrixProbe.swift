import AVFoundation
import ReplayKit
import UIKit

/// Runs the technique x capture-path matrix and writes the raw evidence.
///
/// The output contract is deliberately boring: one line per (path, band) with the sampled RGB and
/// the verdict, plus a PNG per path. The evidence doc quotes those lines verbatim.
enum MatrixProbe {
    @MainActor
    static func run(window: UIWindow) async {
        let runID = Config.runID
        let log = RunLog.shared
        log.log("=== CaptureMatrix \(runID) ===")
        log.log("METHOD window=\(Int(window.bounds.width))x\(Int(window.bounds.height)) scale=\(UIScreen.main.scale)")
        log.log("METHOD bands=\(Band.allCases.count) equal height; colour rect=\(Geometry.colorInBand) of band; text strip=\(Geometry.textInBand) of band")
        log.log("METHOD sentinel colour rgb=\(sentinelRGB.r),\(sentinelRGB.g),\(sentinelRGB.b) painted behind every technique view")
        for band in Band.allCases {
            let e = band.expected
            log.log("METHOD band \(band.rawValue) \(band.title) expected rgb=\(e.r),\(e.g),\(e.b)\(band.hasText ? " text=\"\(Band.secretText)\"" : "")")
        }
        log.log("METHOD environment device=\(UIDevice.current.model) system=\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")

        var summary: [String: Any] = [
            "runID": runID,
            "window": ["width": window.bounds.width, "height": window.bounds.height],
            "device": "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "paths": [String: Any](),
        ]

        // Path A - app-side render (the screenshot-like read).
        let render = CapturePaths.appRender(window: window)
        record(render, summary: &summary)

        // Path B - system capture pipeline (what a screen recording uses).
        let replay = await CapturePaths.replayKit()
        record(replay, summary: &summary)

        // Supplementary - the other public app-side read, kept separate from the required two.
        let layer = CapturePaths.layerRender(window: window)
        record(layer, summary: &summary)

        if let url = log.writeJSON(summary, name: "matrix-\(runID).json") {
            log.log("WROTE \(url.path)")
        }
        log.log("WROTE \(log.writeText("matrix-\(runID).log").path)")
        log.log("=== CaptureMatrix \(runID) done ===")
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    // MARK: - Per-path recording

    private static func record(_ result: CapturePaths.Result, summary: inout [String: Any]) {
        let log = RunLog.shared
        log.log("--- PATH \(result.path) ---")
        log.log("PATH \(result.path) | \(result.note)")

        guard let image = result.image else {
            log.log("PATH \(result.path) | NOT-MEASURED: \(result.note)")
            var paths = summary["paths"] as? [String: Any] ?? [:]
            paths[result.path] = ["status": "not-measured", "note": result.note, "detail": result.detail]
            summary["paths"] = paths
            return
        }

        // Normalise ONCE, to sRGB, and use that single image for both the written artifact and the
        // pixel sampling.
        //
        // This is not a detail. The capture paths hand back bitmaps in the display's colour space
        // (Display P3 here). Writing those P3-encoded pixels into a file tagged sRGB produces a PNG
        // whose numbers match neither the display nor the in-app reading - the first version of this
        // harness did exactly that and an independent host reader disagreed with the app by 20-40 per
        // channel on saturated colours. Normalising first means the artifact, the in-app verdicts,
        // and any host tool all see identical bytes.
        let oriented = orient(image, toMatch: UIScreen.main.bounds.size)
        guard let normalized = PixelAnalyzer.normalizedRGBA8(oriented) else {
            log.log("PATH \(result.path) | NOT-MEASURED: sRGB normalisation failed")
            return
        }
        if let url = log.writePNG(normalized, name: "capture-\(sanitize(result.path)).png") {
            log.log("PATH \(result.path) | WROTE \(url.path)")
        }

        guard let bitmap = PixelAnalyzer.bitmap(normalized) else {
            log.log("PATH \(result.path) | NOT-MEASURED: bitmap normalisation failed")
            return
        }
        let colours = Band.allCases.map { PixelAnalyzer.colourReading(bitmap, band: $0) }
        let texts = Band.allCases.filter(\.hasText).map { PixelAnalyzer.textReading(bitmap, band: $0) }
        for reading in colours {
            log.log("SAMPLE \(result.path) | band \(reading.band.rawValue) \(reading.band.title) | "
                + "meanRGB=\(reading.meanString) medianRGB=\(reading.medianString) "
                + "maxChannel=\(reading.maxChannel) samples=\(reading.samples) "
                + "deltaFromExpected=\(String(format: "%.1f", reading.distance)) -> \(reading.verdict.rawValue)")
        }
        for reading in texts {
            log.log("TEXT \(result.path) | band \(reading.band.rawValue) \(reading.band.title) | "
                + "darkPixels=\(reading.darkPixels)/\(reading.totalPixels) (\(reading.ratioString)) -> \(reading.verdict.rawValue)")
        }

        var paths = summary["paths"] as? [String: Any] ?? [:]
        paths[result.path] = [
            "status": "measured",
            "note": result.note,
            "detail": result.detail,
            "colours": colours.map { [
                "band": $0.band.rawValue,
                "title": $0.band.title,
                "meanRGB": [$0.mean.r, $0.mean.g, $0.mean.b],
                "maxChannel": $0.maxChannel,
                "verdict": $0.verdict.rawValue,
            ] as [String: Any] },
            "texts": texts.map { [
                "band": $0.band.rawValue,
                "title": $0.band.title,
                "darkPixels": $0.darkPixels,
                "totalPixels": $0.totalPixels,
                "ratio": $0.ratio,
                "verdict": $0.verdict.rawValue,
            ] as [String: Any] },
        ]
        summary["paths"] = paths
    }

    // MARK: - Helpers

    private static func sanitize(_ path: String) -> String {
        path.replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "-")
    }

    /// ReplayKit can hand back a frame transposed relative to the window. Rotating to the window's
    /// aspect ratio is what makes the band fractions line up with the same bands on screen.
    private static func orient(_ image: CGImage, toMatch size: CGSize) -> CGImage {
        guard size.width > 0, size.height > 0 else {
            return image
        }
        let windowIsPortrait = size.height >= size.width
        let imageIsPortrait = image.height >= image.width
        guard windowIsPortrait != imageIsPortrait else {
            return image
        }
        RunLog.shared.log("NOTE rotating capture \(image.width)x\(image.height) to match portrait window")
        let width = image.height
        let height = image.width
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return image
        }
        context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
        context.rotate(by: .pi / 2)
        context.draw(image, in: CGRect(x: -Double(image.width) / 2, y: -Double(image.height) / 2,
                                       width: Double(image.width), height: Double(image.height)))
        return context.makeImage() ?? image
    }
}
