//
//  DemoCapabilityListView.swift
//  ScreenGuardDemo
//
//  Renders `ScreenGuard.capabilityStatuses` — the package's own runtime capability registry — rather
//  than a table transcribed into the demo.
//
//  WHY THE DEMO MUST SHOW THIS
//  ---------------------------
//  `docs/api-contract.md` §11 binds t4: "The demo must show the no-leak outcome **and** the capability
//  status table from §4, so the demo cannot imply prevention." A demo that showed only a black
//  rectangle would invite the reader to conclude the package stops screenshots — which iOS does not
//  permit an app to do (§0.2).
//
//  Reading the registry from the package rather than hard-coding it means the demo cannot drift from
//  the contract: if a status changes, the demo changes with it. A unit test in `Tests/` asserts the
//  registry matches §4, so the two cannot silently diverge.
//

import SwiftUI
import UIKit
import ScreenGuard

/// A scrolling list of every capability the package models, with its honest status.
final class DemoCapabilityListView: UIView {

    /// The banner that has to be read before any of the rows.
    private static let bannerText = """
        iOS does not allow an app to prevent a screenshot or a screen recording.

        This package DETECTS captures and keeps sensitive content OUT of them. \
        A protected region appearing black in a capture is the success case. \
        Nothing here blocks the user's action — no public API can.
        """

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    /// Creates the list.
    init() {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 16, leading: 16, bottom: 32, trailing: 16
        )
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        build()
    }

    /// Unavailable. Use `init()`.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DemoCapabilityListView must be created programmatically") }

    // MARK: - Building

    private func build() {
        stack.addArrangedSubview(headline("Capability status"))
        stack.addArrangedSubview(body(
            "ScreenGuard \(ScreenGuard.version) — read from ScreenGuard.capabilityStatuses, "
                + "the package's own runtime registry. The source of truth is "
                + "docs/api-contract.md §4."
        ))
        stack.addArrangedSubview(banner(Self.bannerText))
        stack.addArrangedSubview(spacer(4))

        for (index, status) in ScreenGuard.capabilityStatuses.enumerated() {
            stack.addArrangedSubview(row(index: index + 1, status: status))
        }

        stack.addArrangedSubview(spacer(4))
        stack.addArrangedSubview(headline("What the statuses mean"))
        for (name, meaning) in Self.statusVocabulary {
            stack.addArrangedSubview(vocabularyRow(name: name, meaning: meaning))
        }

        stack.addArrangedSubview(spacer(4))
        stack.addArrangedSubview(body(
            "A note on the private path (row 5): it is off by default, is non-contract, may stop "
                + "working in any iOS release, carries App Review risk, and is never a security "
                + "guarantee. See docs/api-contract.md §9."
        ))
    }

    /// The status vocabulary, copied from `docs/api-contract.md` §4.
    private static let statusVocabulary: [(String, String)] = [
        ("measured", "Demonstrated by a measurement, with a control that rules out the obvious false positive."),
        ("device-pending", "Designed and implemented, but not measurable on Simulator. Not a working guarantee today."),
        ("notMeasured", "No measurement attempted; no claim made."),
        ("notPossible", "The platform does not permit it."),
    ]

    // MARK: - Row construction

    private func row(index: Int, status: ScreenGuardCapabilityStatus) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 10

        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inner)

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .top

        let title = UILabel()
        title.text = "\(index). \(Self.displayName(for: status.capability))"
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.numberOfLines = 0
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(title)

        let badge = UILabel()
        badge.text = " \(status.status.rawValue) "
        badge.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = Self.colour(for: status.status)
        badge.layer.cornerRadius = 5
        badge.layer.masksToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleRow.addArrangedSubview(badge)

        inner.addArrangedSubview(titleRow)

        let summary = UILabel()
        summary.text = status.summary
        summary.font = .preferredFont(forTextStyle: .caption1)
        summary.textColor = .label
        summary.numberOfLines = 0
        inner.addArrangedSubview(summary)

        let evidence = UILabel()
        evidence.text = status.evidence
        evidence.font = .preferredFont(forTextStyle: .caption2)
        evidence.textColor = .secondaryLabel
        evidence.numberOfLines = 0
        inner.addArrangedSubview(evidence)

        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            inner.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        return container
    }

    private func headline(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .title2)
        label.numberOfLines = 0
        return label
    }

    private func body(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func banner(_ text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.4).cgColor

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        return container
    }

    private func vocabularyRow(name: String, meaning: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .top

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(nameLabel)

        let meaningLabel = UILabel()
        meaningLabel.text = meaning
        meaningLabel.font = .preferredFont(forTextStyle: .caption1)
        meaningLabel.textColor = .secondaryLabel
        meaningLabel.numberOfLines = 0
        row.addArrangedSubview(meaningLabel)

        return row
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    // MARK: - Presentation helpers

    /// A human-readable name for a capability case.
    ///
    /// - Parameter capability: The capability.
    /// - Returns: Its display name.
    private static func displayName(for capability: ScreenGuardCapability) -> String {
        switch capability {
        case .screenshotDetection:            return "Screenshot detection"
        case .captureStateDetection:          return "Capture detection (recording / mirroring / AirPlay)"
        case .noLeakSecureTextEntry:          return "No-leak — a text field's own content"
        case .noLeakPublicPreventsCapture:    return "No-leak — arbitrary content, public path"
        case .noLeakPrivateSecureLayer:       return "No-leak — arbitrary content, private path"
        case .noLeakRecordingPath:            return "No-leak — recording path, any technique"
        case .watermark:                      return "Forensic watermark"
        case .appSwitcherSnapshotProtection:  return "App-switcher snapshot protection"
        case .preventUserScreenshot:          return "Prevent a screenshot"
        case .preventUserRecording:           return "Prevent a recording"
        }
    }

    /// The badge colour for a verification status.
    ///
    /// - Parameter status: The status.
    /// - Returns: Its colour. `notPossible` is red because it is a *refusal to claim*, which is the
    ///   most important thing on this page to notice.
    private static func colour(for status: ScreenGuardVerificationStatus) -> UIColor {
        switch status {
        case .measured:      return .systemGreen
        case .devicePending: return .systemOrange
        case .notMeasured:   return .systemGray
        case .notPossible:   return .systemRed
        }
    }
}

/// Hosts `DemoCapabilityListView` for SwiftUI.
///
/// `UIViewControllerRepresentable` rather than `UIViewRepresentable`: a representable's view is not
/// attached to a view controller, and the capability page is a pushed screen with its own navigation
/// bar and scrolling behaviour.
struct DemoCapabilityScreen: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let list = DemoCapabilityListView()
        list.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            list.topAnchor.constraint(equalTo: controller.view.topAnchor),
            list.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        controller.title = "Capability status"
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
