import AVFoundation
import SwiftUI
import UIKit

/// Isolates one question: does setting `preventsCapture = true` stop the layer from painting **on
/// screen** at all?
///
/// The matrix cannot answer its own question if the protected band is invisible on the display,
/// because then "absent from the capture" and "absent from the screen" are indistinguishable. This
/// mode renders three identically-built layers that differ only in `preventsCapture` and in the
/// order in which that flag is applied, so the host screenshot (the one ground truth for what the
/// display is actually showing) can separate the explanations.
///
/// This is a diagnostic, not evidence of capture protection.
enum RenderSanityProbe {
    @MainActor
    static func run(window: UIWindow) async {
        let log = RunLog.shared
        let runID = Config.runID
        log.log("=== CaptureMatrix render-sanity \(runID) ===")

        guard let stack = findStack(in: window) else {
            log.log("RENDER-SANITY NOT-MEASURED: case stack not found")
            return
        }

        // Let the host script screenshot the display while these are up.
        let hold = Double(Config.value(for: "-Hold") ?? "20") ?? 20
        log.log("RENDER-SANITY holding \(Int(hold))s for the host screenshot; cases top-to-bottom:")

        for (index, caseView) in stack.arrangedSubviews.enumerated() {
            guard let caseView = caseView as? SanityCaseView else {
                continue
            }
            log.log("RENDER-SANITY case \(index) \(caseView.label) | expectedOnScreen=\(caseView.expectedRGBString) "
                + "| layerFrames=\(caseView.layerFrameSummary) enqueued=\(caseView.enqueueCount) "
                + "rendererStatus=\(caseView.rendererStatus) preventsCapture=\(caseView.preventsCapture)")
        }

        try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
        log.log("RENDER-SANITY hold finished")
        log.log("RENDER-SANITY NOTE: the DISPLAY-ground-truth.png written by the host script is the "
            + "evidence - sample it to see what the display shows, which capture protection cannot "
            + "influence.")
        log.log("WROTE \(log.writeText("rendersanity-\(runID).log").path)")
        log.log("=== CaptureMatrix render-sanity \(runID) done ===")
    }

    private static func findStack(in window: UIWindow) -> UIStackView? {
        func search(_ view: UIView) -> UIStackView? {
            if let stack = view as? UIStackView, stack.arrangedSubviews.contains(where: { $0 is SanityCaseView }) {
                return stack
            }
            for subview in view.subviews {
                if let found = search(subview) {
                    return found
                }
            }
            return nil
        }
        return search(window)
    }
}

/// One diagnostic case: a `preventsCapture` layer over a known backing colour.
final class SanityCaseView: UIView {
    let label: String
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let contentColor: UIColor
    let preventsCapture: Bool
    private(set) var enqueueCount = 0

    /// `applyBeforeAdd` distinguishes the two plausible explanations for an invisible layer:
    /// the flag itself, versus the flag being set after the layer is already in a tree.
    init(label: String, content: UIColor, backing: UIColor, preventsCapture: Bool, applyBeforeAdd: Bool) {
        self.label = label
        contentColor = content
        self.preventsCapture = preventsCapture
        super.init(frame: .zero)
        backgroundColor = backing
        isUserInteractionEnabled = false

        displayLayer.videoGravity = .resize
        if applyBeforeAdd {
            displayLayer.preventsCapture = preventsCapture
            layer.addSublayer(displayLayer)
        } else {
            layer.addSublayer(displayLayer)
            displayLayer.preventsCapture = preventsCapture
        }
        addLabel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func addLabel() {
        let text = UILabel()
        text.text = label
        text.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        text.textColor = .white
        text.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        guard let image = CMSampleBufferFactory.solidImage(color: contentColor, size: 64),
              let buffer = CMSampleBufferFactory.make(from: image)
        else {
            return
        }
        if #available(iOS 18.0, *) {
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed {
                renderer.flush()
            }
            renderer.enqueue(buffer)
        } else {
            if displayLayer.status == .failed {
                displayLayer.flush()
            }
            displayLayer.enqueue(buffer)
        }
        enqueueCount += 1
    }

    var expectedRGBString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        contentColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(Int((r * 255).rounded())),\(Int((g * 255).rounded())),\(Int((b * 255).rounded()))"
    }

    var layerFrameSummary: String {
        "\(Int(displayLayer.frame.width))x\(Int(displayLayer.frame.height))@\(Int(displayLayer.frame.minX)),\(Int(displayLayer.frame.minY))"
    }

    var rendererStatus: String {
        let status: AVQueuedSampleBufferRenderingStatus = if #available(iOS 18.0, *) {
            displayLayer.sampleBufferRenderer.status
        } else {
            displayLayer.status
        }
        switch status {
        case .unknown:
            return "unknown"
        case .rendering:
            return "rendering"
        case .failed:
            return "failed"
        @unknown default:
            return "?"
        }
    }
}

/// Three cases, each a distinct, unmistakable colour, so the host screenshot can be read by eye and
/// by pixel: A = flag set after add, B = flag set before add, C = flag off (must always paint).
struct RenderSanityView: View {
    var body: some View {
        SanityStackRepresentable()
            .ignoresSafeArea()
            .background(ProbeRunner(mode: .renderSanity))
    }
}

private struct SanityStackRepresentable: UIViewRepresentable {
    func makeUIView(context _: Context) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 0

        let cases: [(String, UIColor, Bool, Bool)] = [
            ("A capture=ON set-after-add  expect 229,25,25", UIColor(red: 229 / 255, green: 25 / 255, blue: 25 / 255, alpha: 1), true, false),
            ("B capture=ON set-before-add expect 38,191,64", UIColor(red: 38 / 255, green: 191 / 255, blue: 64 / 255, alpha: 1), true, true),
            ("C capture=OFF (control)     expect 242,216,25", UIColor(red: 242 / 255, green: 216 / 255, blue: 25 / 255, alpha: 1), false, false),
        ]
        for (label, content, protects, beforeAdd) in cases {
            // Magenta backing: if the layer does not paint, the sentinel is what shows.
            stack.addArrangedSubview(SanityCaseView(label: label, content: content,
                                                    backing: sentinelColor, preventsCapture: protects,
                                                    applyBeforeAdd: beforeAdd))
        }
        return stack
    }

    func updateUIView(_: UIStackView, context _: Context) {}
}
