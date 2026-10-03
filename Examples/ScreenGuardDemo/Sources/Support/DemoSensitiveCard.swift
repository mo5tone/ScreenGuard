//
//  DemoSensitiveCard.swift
//  ScreenGuardDemo
//
//  The clearly identifiable sensitive content the demo protects.
//
//  DESIGN CONSTRAINT THAT IS NOT COSMETIC
//  --------------------------------------
//  The card's **lower half is deliberately text-free**, and that is the region the pixel checks
//  sample. Sampling across glyphs produces false blacks — a documented trap that has already
//  produced one wrong number in this project (`docs/TOOLING.md` §5). Keeping the text at the top and
//  the solid colour below means a blank reading cannot be explained by anti-aliased text.
//

import UIKit

/// A card carrying an account-like secret, with a text-free lower half.
final class DemoSensitiveCard: UIView {

    /// The card's title line.
    private let titleLabel = UILabel()

    /// The card's detail line.
    private let detailLabel = UILabel()

    /// How much of the card's height the text block occupies. The remainder is pure colour.
    static let textBlockFraction: CGFloat = 0.42

    /// Creates the card.
    ///
    /// - Parameter scale: Reserved for future type scaling; the card uses fixed point sizes so the
    ///   probe's sampled rectangle stays text-free at any Dynamic Type setting.
    init() {
        super.init(frame: .zero)
        backgroundColor = DemoGeometry.sensitiveColour
        isUserInteractionEnabled = false

        titleLabel.text = DemoGeometry.secretTitle
        titleLabel.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.text = DemoGeometry.secretDetail
        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.6
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    /// Unavailable. Use `init()`.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DemoSensitiveCard must be created programmatically") }
}

/// Builds the small label chips the probe page uses to identify each region.
enum DemoLabelFactory {

    /// A dark chip with white monospaced text, sized to its content.
    ///
    /// - Parameters:
    ///   - text: The label text.
    ///   - colour: The text colour. Default `.white`.
    /// - Returns: A configured label. It still needs a frame or constraints.
    static func chip(_ text: String, colour: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        label.textColor = colour
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }
}
