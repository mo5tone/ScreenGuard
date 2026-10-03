//
//  DemoEvidence.swift
//  ScreenGuardDemo
//
//  The evidence plumbing. Everything a scripted probe measures is written to the app's Documents
//  directory, because that is the only place `Scripts/verify_capture.sh` can read back from with
//  `xcrun simctl get_app_container`.
//
//  TWO RULES THIS FILE EXISTS TO ENFORCE
//  -------------------------------------
//  1. **The app-side read is the only in-process capture path worth anything.** The readback here is
//     `window.drawHierarchy(in:afterScreenUpdates: false)` — the screenshot-like read that the
//     measurement in `docs/evidence/capability-matrix.md` used. `afterScreenUpdates` MUST stay
//     `false`: `true` forces a CATransaction commit mid-render and UIKit asserts in
//     `_UIRenderViewImageAfterCommit` (SIGABRT, reproduced — `docs/TOOLING.md` §5).
//  2. **Bitmaps are normalised to sRGB before anything reads them.** `UIGraphicsImageRenderer`
//     returns 16 bits per component, and the display is Display P3; reading either as raw 8-bit sRGB
//     bytes produces numbers that disagree with the host by 20-40 per channel
//     (`docs/TOOLING.md` §7.4).
//

import CoreGraphics
import Foundation
import ImageIO
import os
import UIKit

/// Writes every probe line to the unified log *and* to a file the host script can collect.
final class DemoLog: @unchecked Sendable {
    /// The process-wide log for the current run.
    static let shared = DemoLog()

    private let logger = Logger(subsystem: "com.screenguard.demo", category: "probe")
    private let lock = NSLock()
    private var lines: [String] = []

    /// The app's Documents directory.
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Appends a line to the log and the unified log.
    ///
    /// - Parameter message: The line. No trailing newline.
    func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        lock.lock()
        lines.append(message)
        lock.unlock()
    }

    /// The accumulated log text.
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    /// Writes the log to `name` in Documents.
    ///
    /// - Parameter name: The file name.
    /// - Returns: The written URL.
    @discardableResult
    func writeLog(named name: String) -> URL {
        let url = Self.documents.appendingPathComponent(name)
        try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes a JSON object to `name` in Documents.
    ///
    /// - Parameters:
    ///   - object: A JSON-serialisable object.
    ///   - name: The file name.
    /// - Returns: The written URL, or `nil` when the object was not serialisable.
    @discardableResult
    func writeJSON(_ object: [String: Any], named name: String) -> URL? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
              )
        else {
            log("ERROR: could not serialise \(name)")
            return nil
        }
        let url = Self.documents.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            log("ERROR writing \(name): \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes a `CGImage` as a PNG explicitly tagged sRGB.
    ///
    /// The explicit profile is what makes the file agree with the in-app numbers and with any host
    /// tool that ignores ICC profiles — see the file header.
    ///
    /// - Parameters:
    ///   - image: The image, already normalised to sRGB.
    ///   - name: The file name.
    /// - Returns: The written URL, or `nil` on failure.
    @discardableResult
    func writePNG(_ image: CGImage, named name: String) -> URL? {
        let url = Self.documents.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            log("ERROR creating PNG destination for \(name)")
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName: "sRGB IEC61966-2.1",
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            log("ERROR finalising PNG \(name)")
            return nil
        }
        return url
    }
}

// MARK: - The app-side read

/// The app-side capture read, and the sampling that turns it into per-region colour verdicts.
enum AppSideReadback {
    /// One region's reading from one capture path.
    struct Reading {
        /// The region's stable name.
        let region: String
        /// The sampled body rectangle, in normalised coordinates.
        let bodyRect: CGRect
        /// Mean RGB over the sampled pixels.
        let mean: (r: Double, g: Double, b: Double)
        /// Median RGB over the sampled pixels.
        let median: (r: Int, g: Int, b: Int)
        /// The largest single channel value seen — a blank region reads 0.
        let maxChannel: Int
        /// How many pixels were sampled.
        let samples: Int
        /// A one-word classification of what the region reads.
        let verdict: Verdict

        /// `"r,g,b"` for the mean.
        var meanString: String {
            "\(Int(mean.r.rounded())),\(Int(mean.g.rounded())),\(Int(mean.b.rounded()))"
        }

        /// `"r,g,b"` for the median.
        var medianString: String {
            "\(median.r),\(median.g),\(median.b)"
        }
    }

    /// What a sampled region reads, classified against the demo's two reference colours.
    ///
    /// The vocabulary is deliberately small and literal. There is no "PASS" here: whether a reading
    /// is good depends on which region it is and which capture path produced it, and that judgement
    /// belongs to the script (and, for the public path, to a device run).
    enum Verdict: String {
        /// The sensitive content's own colour — the region leaked.
        case sensitive = "SENSITIVE"
        /// The sentinel behind the region — the region's pixels were excluded from the read.
        case sentinel = "SENTINEL"
        /// Black and no signal at all — the region painted nothing, or an opaque black backing was
        /// captured. The two are indistinguishable from a single read, which is exactly the
        /// Simulator confound (`docs/TOOLING.md` §7.1).
        case black = "BLACK"
        /// Neither reference colour and not black.
        case other = "OTHER"
        /// The read produced no pixels at all.
        case unreadable = "UNREADABLE"
    }

    /// Tolerance, per channel, when matching a reading against a reference colour.
    ///
    /// Generous on purpose: the capture path re-encodes through a different colour pipeline, and the
    /// reference colours are far enough apart (blue / magenta / black) that 40 cannot confuse two of
    /// them.
    private static let tolerance: Double = 40

    /// Normalises any incoming bitmap to 8-bit-per-component sRGB RGBA.
    ///
    /// - Parameter image: The source image, in whatever colour space it arrived in.
    /// - Returns: An sRGB image, or `nil` when the context could not be built.
    static func normalizedSRGB(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Reads the window through `drawHierarchy` and returns an sRGB image.
    ///
    /// - Parameter window: The window to read. Must already be laid out.
    /// - Returns: The normalised read, or `nil` when no image could be produced.
    static func appRender(window: UIWindow) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            // afterScreenUpdates MUST be false. See this file's header.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let cgImage = image.cgImage else {
            return nil
        }
        return normalizedSRGB(cgImage)
    }

    /// A sampled bitmap that owns its backing storage.
    ///
    /// The ownership matters: the bytes come from a `CGDataProvider`, and if the `CFData` is only a
    /// local, the pointer dangles the moment the creating function returns. Holding the `CFData`
    /// here keeps it valid for as long as the `Bitmap` is. (This exact bug segfaulted the t1 harness
    /// once — see `Research/CaptureMatrix/Sources/PixelAnalyzer.swift`.)
    struct Bitmap {
        private let storage: CFData
        private let bytes: UnsafePointer<UInt8>
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let length: Int

        /// Wraps an 8-bit RGBA image.
        ///
        /// - Parameter image: An image whose backing store is 8 bits per component.
        init?(image: CGImage) {
            guard let data = image.dataProvider?.data, let pointer = CFDataGetBytePtr(data) else {
                return nil
            }
            storage = data
            bytes = pointer
            width = image.width
            height = image.height
            bytesPerRow = image.bytesPerRow
            length = CFDataGetLength(data)
        }

        /// The RGB triple at `x`,`y`, or `nil` when out of range.
        func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
            guard x >= 0, y >= 0, x < width, y < height else {
                return nil
            }
            let offset = y * bytesPerRow + x * 4
            guard offset + 3 < length else {
                return nil
            }
            return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
        }
    }

    /// Samples a normalised rect on a fixed grid and classifies it.
    ///
    /// A fixed grid rather than a pixel step, so two images of different pixel sizes yield the same
    /// sample count in the same order and can be compared index by index. (Sampling with a pixel step
    /// compared unrelated pixels between a 1061-wide source and a 353-wide readback and reported an
    /// error of ~51 where the truth was ~8 — `PixelAnalyzer.sampleGrid`.)
    ///
    /// - Parameters:
    ///   - bitmap: The read to sample.
    ///   - region: The region, whose `bodyRect` is used.
    ///   - columns: Grid width. Default 32.
    ///   - rows: Grid height. Default 32.
    /// - Returns: The region's reading.
    static func read(
        _ bitmap: Bitmap,
        region: DemoGeometry.Region,
        columns: Int = 32,
        rows: Int = 32
    ) -> Reading {
        let rect = region.bodyRect
        var pixels: [(Int, Int, Int)] = []
        pixels.reserveCapacity(columns * rows)
        for row in 0 ..< rows {
            // Sample at cell centres so both images land on comparable content.
            let fy = rect.minY + rect.height * (Double(row) + 0.5) / Double(rows)
            for column in 0 ..< columns {
                let fx = rect.minX + rect.width * (Double(column) + 0.5) / Double(columns)
                let x = min(bitmap.width - 1, max(0, Int(fx * Double(bitmap.width))))
                let y = min(bitmap.height - 1, max(0, Int(fy * Double(bitmap.height))))
                if let pixel = bitmap.pixel(x: x, y: y) {
                    pixels.append(pixel)
                }
            }
        }

        guard !pixels.isEmpty else {
            return Reading(
                region: region.name, bodyRect: rect, mean: (0, 0, 0), median: (0, 0, 0),
                maxChannel: 0, samples: 0, verdict: .unreadable
            )
        }

        let count = Double(pixels.count)
        let mean = (
            r: Double(pixels.reduce(0) { $0 + $1.0 }) / count,
            g: Double(pixels.reduce(0) { $0 + $1.1 }) / count,
            b: Double(pixels.reduce(0) { $0 + $1.2 }) / count
        )
        func median(_ values: [Int]) -> Int {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        let medianTriple = (
            r: median(pixels.map(\.0)),
            g: median(pixels.map(\.1)),
            b: median(pixels.map(\.2))
        )
        let maxChannel = pixels.map { max($0.0, max($0.1, $0.2)) }.max() ?? 0

        let verdict = classify(mean: mean, maxChannel: maxChannel)
        return Reading(
            region: region.name, bodyRect: rect, mean: mean, median: medianTriple,
            maxChannel: maxChannel, samples: pixels.count, verdict: verdict
        )
    }

    /// Classifies a reading against the demo's reference colours.
    private static func classify(mean: (r: Double, g: Double, b: Double), maxChannel: Int) -> Verdict {
        if distance(mean, DemoGeometry.sensitiveColour) <= tolerance {
            return .sensitive
        }
        if distance(mean, DemoGeometry.sentinelColour) <= tolerance {
            return .sentinel
        }
        if maxChannel < 32 {
            return .black
        }
        return .other
    }

    /// The fraction of sampled pixels that differ from a reference colour by more than `threshold`
    /// on some channel, plus the sample count.
    ///
    /// This exists for the watermark page, where the question is the opposite of the shield's. A
    /// watermark is a **deterrent**: its whole job is to ADD marks to the capture, so the honest
    /// check is "the marked band is NOT flat" — with a matched un-marked band proving the measure has
    /// discriminating power. It is deliberately not a no-leak measure, and nothing here produces a
    /// no-leak verdict.
    ///
    /// A per-pixel count rather than a mean, because a sparse mark over a large area barely moves the
    /// mean while still being clearly drawn.
    ///
    /// - Parameters:
    ///   - bitmap: The read to sample.
    ///   - region: The region, whose `bodyRect` is used.
    ///   - reference: The flat colour the region would have without any mark.
    ///   - threshold: Per-channel distance above which a pixel counts as marked.
    ///   - columns: Grid width. Default 32.
    ///   - rows: Grid height. Default 32.
    /// - Returns: The marked fraction (0…1) and how many pixels were sampled.
    static func deviationFraction(
        _ bitmap: Bitmap,
        region: DemoGeometry.Region,
        from reference: UIColor,
        threshold: Int = 24,
        columns: Int = 32,
        rows: Int = 32
    ) -> (fraction: Double, samples: Int, maxChannel: Int) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        reference.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let base = (Double(red) * 255, Double(green) * 255, Double(blue) * 255)

        let rect = region.bodyRect
        var total = 0
        var marked = 0
        var maxChannel = 0
        for row in 0 ..< rows {
            let fy = rect.minY + rect.height * (Double(row) + 0.5) / Double(rows)
            for column in 0 ..< columns {
                let fx = rect.minX + rect.width * (Double(column) + 0.5) / Double(columns)
                let x = min(bitmap.width - 1, max(0, Int(fx * Double(bitmap.width))))
                let y = min(bitmap.height - 1, max(0, Int(fy * Double(bitmap.height))))
                guard let pixel = bitmap.pixel(x: x, y: y) else {
                    continue
                }
                total += 1
                maxChannel = max(maxChannel, max(pixel.r, max(pixel.g, pixel.b)))
                let delta = max(
                    abs(Double(pixel.r) - base.0),
                    max(abs(Double(pixel.g) - base.1), abs(Double(pixel.b) - base.2))
                )
                if delta > Double(threshold) {
                    marked += 1
                }
            }
        }
        guard total > 0 else {
            return (0, 0, 0)
        }
        return (Double(marked) / Double(total), total, maxChannel)
    }

    /// The maximum per-channel distance between `mean` and `reference`.
    private static func distance(_ mean: (r: Double, g: Double, b: Double), _ reference: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        reference.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return max(
            abs(mean.r - Double(red) * 255),
            max(abs(mean.g - Double(green) * 255), abs(mean.b - Double(blue) * 255))
        )
    }
}
