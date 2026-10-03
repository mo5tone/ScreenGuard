import CoreGraphics
import UIKit

/// Verdict vocabulary. The doc's table uses exactly these strings.
enum Verdict: String {
    case noLeak = "NO-LEAK(black)"
    case leaked = "LEAKED(visible)"
    case textBlanked = "TEXT-BLANKED"
    case textLeaked = "TEXT-LEAKED"
    case sentinel = "SENTINEL-SHOWS(transparent)"
    case notApplicable = "N/A(no-colour-signal)"
    case unknown = "UNKNOWN"
}

struct ColourReading {
    let band: Band
    let mean: (r: Double, g: Double, b: Double)
    let median: (r: Double, g: Double, b: Double)
    let maxChannel: Int
    let samples: Int
    let verdict: Verdict
    /// Max per-channel distance from the band's intended colour, for the log line.
    let distance: Double

    var meanString: String {
        "(\(Int(mean.r.rounded())), \(Int(mean.g.rounded())), \(Int(mean.b.rounded())))"
    }
    var medianString: String {
        "(\(Int(median.r.rounded())), \(Int(median.g.rounded())), \(Int(median.b.rounded())))"
    }
}

struct TextReading {
    let band: Band
    let darkPixels: Int
    let totalPixels: Int
    let ratio: Double
    let verdict: Verdict

    var ratioString: String { String(format: "%.2f%%", ratio * 100) }
}

/// Reduces a capture image to per-band verdicts by reading pixels.
///
/// Two independent signals are used, because they can disagree in a way that matters:
///   * the **colour rect** says whether the band's pixels are present, absent, or transparent;
///   * the **text strip** says whether the *system's own* capture protection is active on this
///     path. A path that leaks a secure field's text is a path where every other "NO-LEAK" would
///     be unearned.
enum PixelAnalyzer {

    /// Normalises any incoming bitmap to 8-bit-per-component **sRGB** RGBA.
    ///
    /// Two things are being fixed here, and both have already produced wrong numbers once:
    ///   * `UIGraphicsImageRenderer` hands back 16 bits per component (`bitsPerPixel == 64`);
    ///     reading those bytes as 8-bit components yields noise.
    ///   * The display is P3. A bitmap produced in the display's colour space, read back as raw
    ///     bytes, is *not* comparable to a band's declared sRGB colour - saturated colours shift by
    ///     40+ per channel. Pinning sRGB makes the app-render path and the ReplayKit path
    ///     comparable, and makes the written PNG independently verifiable by any tool.
    static func normalizedRGBA8(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The one colour space every measurement and every artifact is expressed in.
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// A sampled bitmap that **owns** its backing storage.
    ///
    /// This ownership is not cosmetic. The bytes come from a `CGDataProvider`, and if the `CFData`
    /// is only a local in the sampling function it is released the moment that function returns -
    /// leaving `bytes` dangling. That exact bug segfaulted this harness once, in `pixel(x:y:)`, when
    /// a `Bitmap` was returned out of the closure that created it. Holding the `CFData` here makes
    /// the pointer valid for as long as the `Bitmap` is.
    struct Bitmap {
        private let storage: CFData
        private let bytes: UnsafePointer<UInt8>
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let length: Int

        init?(image: CGImage) {
            guard let data = image.dataProvider?.data,
                  let pointer = CFDataGetBytePtr(data) else { return nil }
            storage = data
            bytes = pointer
            width = image.width
            height = image.height
            bytesPerRow = image.bytesPerRow
            length = CFDataGetLength(data)
        }

        func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let offset = y * bytesPerRow + x * 4
            guard offset + 3 < length else { return nil }
            return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
        }
    }

    /// Normalises `image` and hands a storage-owning bitmap to `body`.
    static func withBitmap<T>(_ image: CGImage, _ body: (Bitmap) -> T) -> T? {
        guard let normalized = normalizedRGBA8(image), let bitmap = Bitmap(image: normalized) else { return nil }
        return body(bitmap)
    }

    /// Normalises and returns a bitmap that stays valid after this call returns.
    static func bitmap(_ image: CGImage) -> Bitmap? {
        guard let normalized = normalizedRGBA8(image) else { return nil }
        return Bitmap(image: normalized)
    }

    /// Samples a rect given in normalised (0-1) image coordinates.
    static func sample(_ bitmap: Bitmap, normalizedRect rect: CGRect, step: Int = 3) -> [(Int, Int, Int)] {
        let x0 = Int(rect.minX * Double(bitmap.width))
        let x1 = Int(rect.maxX * Double(bitmap.width))
        let y0 = Int(rect.minY * Double(bitmap.height))
        let y1 = Int(rect.maxY * Double(bitmap.height))
        var pixels: [(Int, Int, Int)] = []
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                if let pixel = bitmap.pixel(x: x, y: y) { pixels.append(pixel) }
                x += step
            }
            y += step
        }
        return pixels
    }

    /// Samples a normalised rect on a **fixed grid**, so two images of different pixel sizes yield
    /// the same number of samples in the same order and can be compared index-by-index.
    ///
    /// This exists because the naive alternative is silently wrong. Sampling a 1061x970 source and a
    /// 353x324 readback with the same pixel `step` produces ~353-wide and ~118-wide sample grids;
    /// zipping them compares unrelated pixels and reported a mean error of ~51 where the true value
    /// was ~8. Any fidelity comparison between images of different scale must go through this.
    static func sampleGrid(_ bitmap: Bitmap, normalizedRect rect: CGRect,
                           columns: Int = 64, rows: Int = 64) -> [(Int, Int, Int)] {
        guard columns > 0, rows > 0 else { return [] }
        var pixels: [(Int, Int, Int)] = []
        pixels.reserveCapacity(columns * rows)
        for row in 0..<rows {
            // Sample at cell centres so both images land on comparable content.
            let fy = rect.minY + rect.height * (Double(row) + 0.5) / Double(rows)
            for column in 0..<columns {
                let fx = rect.minX + rect.width * (Double(column) + 0.5) / Double(columns)
                let x = min(bitmap.width - 1, max(0, Int(fx * Double(bitmap.width))))
                let y = min(bitmap.height - 1, max(0, Int(fy * Double(bitmap.height))))
                if let pixel = bitmap.pixel(x: x, y: y) { pixels.append(pixel) }
            }
        }
        return pixels
    }

    // MARK: - Colour verdict

    static func colourReading(_ bitmap: Bitmap, band: Band) -> ColourReading {
        let rect = Geometry.absolute(Geometry.colorInBand, band: band.rawValue)
        let pixels = sample(bitmap, normalizedRect: rect)
        guard !pixels.isEmpty else {
            return ColourReading(band: band, mean: (0, 0, 0), median: (0, 0, 0), maxChannel: 0,
                                 samples: 0, verdict: .unknown, distance: -1)
        }
        func mean(_ keyPath: KeyPath<(Int, Int, Int), Int>) -> Double {
            Double(pixels.reduce(0) { $0 + $1[keyPath: keyPath] }) / Double(pixels.count)
        }
        let mean = (r: mean(\.0), g: mean(\.1), b: mean(\.2))
        let median = (
            r: Double(median(pixels.map(\.0))),
            g: Double(median(pixels.map(\.1))),
            b: Double(median(pixels.map(\.2)))
        )
        let maxChannel = pixels.map { max($0.0, max($0.1, $0.2)) }.max() ?? 0
        let expected = band.expected
        let distance = max(abs(mean.r - Double(expected.r)),
                           max(abs(mean.g - Double(expected.g)),
                               abs(mean.b - Double(expected.b))))
        // A text band's view is transparent by construction, so its colour rect can only ever
        // report whatever is behind the field. Emitting a colour verdict for it would be inventing
        // a cell; the text strip is its real signal.
        let verdict = band.hasColourSignal
            ? classify(mean: mean, maxChannel: maxChannel, distance: distance)
            : .notApplicable
        return ColourReading(band: band, mean: mean, median: median, maxChannel: maxChannel,
                             samples: pixels.count, verdict: verdict, distance: distance)
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Tolerance is generous (40) because the ReplayKit path re-encodes through a different colour
    /// pipeline; the band colours are far enough apart that 40 cannot confuse two of them.
    private static func classify(mean: (r: Double, g: Double, b: Double), maxChannel: Int,
                                 distance: Double) -> Verdict {
        if distance <= 40 { return .leaked }
        // Transparent-and-showing-the-sentinel is a distinct, worse outcome than black: it means the
        // mechanism removed the pixels from the composite rather than painting them black.
        let sentinelDistance = max(abs(mean.r - Double(sentinelRGB.r)),
                                   max(abs(mean.g - Double(sentinelRGB.g)),
                                       abs(mean.b - Double(sentinelRGB.b))))
        if sentinelDistance <= 40 { return .sentinel }
        if maxChannel < 32 { return .noLeak }
        return .unknown
    }

    // MARK: - Text verdict

    /// Counts dark pixels in the band's text strip. A secure field's dots and a plain field's glyphs
    /// are both dark-on-band-colour, so the same threshold works for both.
    static func textReading(_ bitmap: Bitmap, band: Band) -> TextReading {
        let rect = Geometry.absolute(Geometry.textInBand, band: band.rawValue)
        let pixels = sample(bitmap, normalizedRect: rect, step: 2)
        let total = pixels.count
        let dark = pixels.filter { max($0.0, max($0.1, $0.2)) < 90 }.count
        let ratio = total > 0 ? Double(dark) / Double(total) : 0
        // A field renders either dots or glyphs across a good fraction of its strip; an empty strip
        // reads as pure band colour. 0.5% cleanly separates those two states.
        let threshold = 0.005
        let verdict: Verdict
        switch band {
        case .secureTextField:
            verdict = ratio > threshold ? .textLeaked : .textBlanked
        case .plainTextFieldReference:
            verdict = ratio > threshold ? .textLeaked : .textBlanked
        default:
            verdict = .unknown
        }
        return TextReading(band: band, darkPixels: dark, totalPixels: total, ratio: ratio, verdict: verdict)
    }
}
