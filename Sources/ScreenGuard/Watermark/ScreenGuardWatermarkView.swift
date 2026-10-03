//
//  ScreenGuardWatermarkView.swift
//  ScreenGuard
//
//  Appearance and content of the forensic watermark. See docs/api-contract.md §3.3 / §6.6.
//
//  ⚠️ THE WATERMARK IS NOT A NO-LEAK CONTROL. It removes NO pixels from any capture — not a
//  screenshot, not a recording, not a mirror. It is a DETERRENT AND FORENSIC measure: it makes a leak
//  ATTRIBUTABLE to a session, user or time. It does not survive cropping, blurring, downscaling or
//  occlusion, and it stops nothing. It must never be described as protection.
//

import UIKit

// MARK: - Configuration

/// Appearance and content of the forensic watermark.
///
/// A watermark is a **DETERRENT AND FORENSIC** measure. It removes no pixels from any capture and
/// prevents nothing. See `docs/api-contract.md` §3.3.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardWatermarkConfiguration {

    /// Primary mark, e.g. `"CONFIDENTIAL"`.
    public var text: String

    /// Optional second line, e.g. a session or user identifier used for attribution.
    public var secondaryText: String?

    /// Tile pitch in points. Default `CGSize(width: 180, height: 120)`.
    public var tileSize: CGSize

    /// Tile rotation in radians. Default `-.pi / 6`.
    public var angle: CGFloat

    /// Tile opacity. Default `0.12`. Low values stay legible under the content.
    public var opacity: CGFloat

    /// The mark's colour. Default `.label`.
    public var color: UIColor

    /// The mark's font. Default `.systemFont(ofSize: 11, weight: .medium)`.
    public var font: UIFont

    /// Include a timestamp in each tile. Default `true`.
    public var includesTimestamp: Bool

    /// Date format for the timestamp. Default `"yyyy-MM-dd HH:mm:ss zzz"`.
    public var timestampFormat: String

    /// Time zone the timestamp is rendered in. Default `TimeZone.current`.
    ///
    /// Explicit rather than ambient on purpose: the whole point of the timestamp is forensic
    /// attribution, and a stamp whose time zone is implicit in the device's locale at leak time is
    /// ambiguous to an investigator. Recording the zone alongside the mark removes that ambiguity, and
    /// making it injectable is what lets the geometry be tested deterministically.
    public var timeZone: TimeZone

    /// Supplies "now". Injectable so the layout is testable.
    public var timestampProvider: () -> Date

    /// Creates a watermark configuration.
    ///
    /// - Parameters:
    ///   - text: Primary mark, e.g. `"CONFIDENTIAL"`.
    ///   - secondaryText: Optional attribution line.
    ///   - tileSize: Tile pitch in points. Default `CGSize(width: 180, height: 120)`.
    ///   - angle: Tile rotation in radians. Default `-.pi / 6`.
    ///   - opacity: Tile opacity. Default `0.12`.
    ///   - color: The mark's colour. Default `.label`.
    ///   - font: The mark's font. Default `.systemFont(ofSize: 11, weight: .medium)`.
    ///   - includesTimestamp: Include a timestamp in each tile. Default `true`.
    ///   - timestampFormat: Date format for the timestamp. Default
    ///     `"yyyy-MM-dd HH:mm:ss zzz"`.
    ///   - timeZone: Time zone for the timestamp. Default `TimeZone.current`.
    ///   - timestampProvider: Supplies "now". Default `Date.init`.
    public init(
        text: String,
        secondaryText: String? = nil,
        tileSize: CGSize = CGSize(width: 180, height: 120),
        angle: CGFloat = -.pi / 6,
        opacity: CGFloat = 0.12,
        color: UIColor = .label,
        font: UIFont = .systemFont(ofSize: 11, weight: .medium),
        includesTimestamp: Bool = true,
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss zzz",
        timeZone: TimeZone = .current,
        timestampProvider: @escaping () -> Date = Date.init
    ) {
        self.text = text
        self.secondaryText = secondaryText
        self.tileSize = tileSize
        self.angle = angle
        self.opacity = opacity
        self.color = color
        self.font = font
        self.includesTimestamp = includesTimestamp
        self.timestampFormat = timestampFormat
        self.timeZone = timeZone
        self.timestampProvider = timestampProvider
    }

    /// The lines drawn inside one tile, in order, for `date`.
    ///
    /// Pure: the same configuration and date always produce the same lines. Exposed so a host app
    /// (and the package's own tests) can assert what a tile actually contains without rendering.
    ///
    /// - Parameter date: The date to stamp, when `includesTimestamp` is `true`.
    /// - Returns: The non-empty lines of one tile.
    public func tileLines(at date: Date) -> [String] {
        var lines: [String] = [text]
        if let secondaryText, !secondaryText.isEmpty { lines.append(secondaryText) }
        if includesTimestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = timestampFormat
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            lines.append(formatter.string(from: date))
        }
        return lines.filter { !$0.isEmpty }
    }
}

// MARK: - View

/// Draws a tiled forensic watermark over its own bounds. Non-interactive.
///
/// Place it as an overlay above the content it attributes. It removes **no** pixels from any capture.
///
/// ```swift
/// let mark = ScreenGuardWatermarkView(
///     configuration: .init(text: "CONFIDENTIAL", secondaryText: "session 4417")
/// )
/// ```
///
/// iOS 15-compatible — no availability guard is required.
@MainActor
public final class ScreenGuardWatermarkView: UIView {

    /// Changing this re-draws the watermark.
    ///
    /// The configuration is not `Equatable` (it carries a `timestampProvider` closure), so a change
    /// always triggers a re-draw. A watermark draw is cheap and idempotent, and re-drawing
    /// unconditionally is the behaviour a caller expects from `var configuration`.
    public var configuration: ScreenGuardWatermarkConfiguration {
        didSet { setNeedsDisplay() }
    }

    /// Creates a watermark view.
    ///
    /// - Parameter configuration: The mark's appearance and content.
    public init(configuration: ScreenGuardWatermarkConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    /// Unavailable. Use `init(configuration:)`.
    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ScreenGuardWatermarkView must be created programmatically") }

    /// Forces a re-draw (e.g. to advance the timestamp).
    public func refresh() {
        setNeedsDisplay()
    }

    /// Draws the tiles. Called by UIKit; not part of the package's API surface.
    ///
    /// - Parameter rect: The rect being drawn.
    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let origins = ScreenGuardWatermarkLayout.tileOrigins(in: bounds, tileSize: configuration.tileSize)
        guard !origins.isEmpty else { return }

        let date = configuration.timestampProvider()
        let lines = configuration.tileLines(at: date)
        guard !lines.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: configuration.font,
            .foregroundColor: configuration.color.withAlphaComponent(configuration.opacity),
            .paragraphStyle: paragraph
        ]

        context.saveGState()
        for origin in origins {
            context.saveGState()
            // Rotate about the tile's centre so neighbouring tiles stay on a consistent grid.
            context.translateBy(
                x: origin.x + configuration.tileSize.width / 2,
                y: origin.y + configuration.tileSize.height / 2
            )
            context.rotate(by: configuration.angle)

            let textRect = CGRect(
                x: -configuration.tileSize.width / 2,
                y: -configuration.tileSize.height / 2,
                width: configuration.tileSize.width,
                height: configuration.tileSize.height
            )
            let string = lines.joined(separator: "\n") as NSString
            let size = string.size(withAttributes: attributes)
            let drawOrigin = CGPoint(
                x: textRect.midX - size.width / 2,
                y: textRect.midY - size.height / 2
            )
            string.draw(at: drawOrigin, withAttributes: attributes)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
