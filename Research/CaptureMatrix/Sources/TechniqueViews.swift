import AVFoundation
import SwiftUI
import UIKit

// MARK: - Band content

/// Paints one band. Every band is built the same way: a sentinel-coloured container that fills the
/// band, optionally with a technique view on top of it, and a top-left label chip. Keeping the
/// container identical across bands is what makes "the pixels are gone" attributable to the
/// technique rather than to layout.
struct BandContent: View {
    let band: Band

    var body: some View {
        ZStack {
            Color(band.backing)
            technique
            Text(band.title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var technique: some View {
        switch band {
        case .plainControl:
            Color(band.uiColor)
        case .sampleBufferProtected, .sampleBufferProtectedShielded:
            SampleBufferHost(color: band.uiColor, preventsCapture: true)
        case .sampleBufferControl:
            SampleBufferHost(color: band.uiColor, preventsCapture: false)
        case .secureLayerSwap:
            SecureLayerSwapHost(enabled: true)
        case .secureLayerSwapControl:
            SecureLayerSwapHost(enabled: false)
        case .secureTextField:
            SecureFieldView(text: Band.secretText)
        case .plainTextFieldReference:
            PlainFieldView(text: Band.secretText)
        }
    }
}

// MARK: - AVSampleBufferDisplayLayer (the only public iOS capture-blocking API)

/// Hosts an `AVSampleBufferDisplayLayer`. `preventsCapture` exists only on this layer class, so this
/// is the only public route to capture exclusion on iOS 13+.
///
/// In `matrix` mode it is handed a solid colour so the verdict is unambiguous. In `feasibility`
/// mode it is handed a real rendered image, which is the question that actually matters: can this
/// layer carry arbitrary app content?
final class SampleBufferHostView: UIView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    let preventsCapture: Bool

    /// Where the content comes from. Replaced in feasibility mode so the same host can carry
    /// arbitrary rendered content instead of a solid colour.
    var contentProvider: (() -> CGImage?)?

    /// What the host was last asked to display, for the fidelity comparison.
    private(set) var lastProvidedImage: CGImage?
    private(set) var enqueueCount = 0
    private(set) var lastEnqueueSucceeded = false

    init(preventsCapture: Bool, contentProvider: (() -> CGImage?)? = nil) {
        self.preventsCapture = preventsCapture
        self.contentProvider = contentProvider
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        displayLayer.videoGravity = .resize
        displayLayer.frame = bounds
        layer.addSublayer(displayLayer)
        displayLayer.preventsCapture = preventsCapture
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
        enqueue()
    }

    /// The display layer only paints once it has a frame.
    func enqueue() {
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        guard let image = contentProvider?() else {
            return
        }
        display(image)
    }

    /// Explicitly push one frame. Returns whether the layer accepted it.
    @discardableResult
    func display(_ image: CGImage) -> Bool {
        lastProvidedImage = image
        guard let buffer = CMSampleBufferFactory.make(from: image) else {
            return false
        }
        // `sampleBufferRenderer` is the modern spelling (iOS 18+); the pre-18 properties are the
        // same objects and remain functional. Branching keeps the harness buildable at iOS 15.
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
        lastEnqueueSucceeded = true
        return true
    }

    var isReadyForMoreMediaData: Bool {
        if #available(iOS 18.0, *) {
            return displayLayer.sampleBufferRenderer.isReadyForMoreMediaData
        }
        return displayLayer.isReadyForMoreMediaData
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

private struct SampleBufferHost: UIViewRepresentable {
    let color: UIColor
    let preventsCapture: Bool

    func makeUIView(context _: Context) -> SampleBufferHostView {
        SampleBufferHostView(preventsCapture: preventsCapture) { [color] in
            CMSampleBufferFactory.solidImage(color: color, size: 64)
        }
    }

    func updateUIView(_: SampleBufferHostView, context _: Context) {}
}

/// Turns a `CGImage` into a `CMSampleBuffer` the display layer will accept.
enum CMSampleBufferFactory {
    static func make(from image: CGImage) -> CMSampleBuffer? {
        let width = image.width
        let height = image.height
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
            let pixelBuffer
        else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer),
           let context = CGContext(
               data: base,
               width: width,
               height: height,
               bitsPerComponent: 8,
               bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                   | CGBitmapInfo.byteOrder32Little.rawValue
           )
        {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                           imageBuffer: pixelBuffer,
                                                           formatDescriptionOut: &format) == noErr,
            let format
        else {
            return nil
        }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                                        presentationTimeStamp: .zero,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: pixelBuffer,
                                                       formatDescription: format,
                                                       sampleTiming: &timing,
                                                       sampleBufferOut: &sampleBuffer) == noErr
        else {
            return nil
        }
        return sampleBuffer
    }

    static func solidImage(color: UIColor, size: Int) -> CGImage? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }
}

// MARK: - Known-good control: secure UITextField

/// A secure text field is the one case iOS documents as capture-protected. If its *text* survives a
/// capture path, that path bypasses capture protection entirely and every other verdict from that
/// path is meaningless. Hence: a control, not a technique.
private struct SecureFieldView: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.text = text
        field.textColor = .black
        field.font = .systemFont(ofSize: 20, weight: .bold)
        field.textAlignment = .center
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.isUserInteractionEnabled = false
        return field
    }

    func updateUIView(_: UITextField, context _: Context) {}
}

/// Harness calibration, not a technique. Identical to the secure field except for the one flag, so
/// it isolates exactly that flag. Without this band, "no dark pixels in the secure field's strip"
/// could equally mean "this capture path cannot resolve text at all".
private struct PlainFieldView: UIViewRepresentable {
    let text: String

    func makeUIView(context _: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = false
        field.text = text
        field.textColor = .black
        field.font = .systemFont(ofSize: 20, weight: .bold)
        field.textAlignment = .center
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.isUserInteractionEnabled = false
        return field
    }

    func updateUIView(_: UITextField, context _: Context) {}
}

// MARK: - The non-contract trick: park this view's own layer inside the secure field's canvas

/// Reproduces the widely copied private trick. `_UITextLayoutCanvasView` is a private class name and
/// nothing here is contract - the point of measuring it is to establish whether the *only* thing
/// that blanks a screenshot path is something Apple can break at any release.
final class SecureLayerSwapView: UIView {
    private let field = UITextField()
    private let enabled: Bool
    private var didApply = false

    private(set) var swapApplied = false
    private(set) var failureReason: String?

    init(enabled: Bool) {
        self.enabled = enabled
        super.init(frame: .zero)
        // The band's content. Once this view's layer is reparented into the secure canvas, this is
        // what the render server should refuse to hand to a capture.
        backgroundColor = Band.secureLayerSwap.uiColor
        isUserInteractionEnabled = false
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didApply else {
            return
        }
        didApply = true
        guard enabled else {
            failureReason = "swap disabled (control band)"
            RunLog.shared.log("secure-layer-swap: control band - swap deliberately NOT applied")
            return
        }
        applyProtection()
    }

    private func applyProtection() {
        guard let canvas = Self.findCanvas(in: field) else {
            failureReason = "no _UITextLayoutCanvasView descendant"
            RunLog.shared.log("secure-layer-swap: canvas NOT found; private trick unavailable")
            return
        }
        RunLog.shared.log("secure-layer-swap: canvas class = \(NSStringFromClass(type(of: canvas)))")
        let original = canvas.layer
        canvas.setValue(layer, forKey: "layer")
        field.isSecureTextEntry = false
        field.isSecureTextEntry = true
        canvas.setValue(original, forKey: "layer")
        swapApplied = true
        RunLog.shared.log("secure-layer-swap: swap applied")
    }

    /// Recursive, because the canvas is not guaranteed to be a direct subview.
    private static func findCanvas(in view: UIView) -> UIView? {
        for subview in view.subviews {
            if NSStringFromClass(type(of: subview)).contains("LayoutCanvasView") {
                return subview
            }
            if let found = findCanvas(in: subview) {
                return found
            }
        }
        return nil
    }
}

private struct SecureLayerSwapHost: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context _: Context) -> SecureLayerSwapView {
        SecureLayerSwapView(enabled: enabled)
    }

    func updateUIView(_: SecureLayerSwapView, context _: Context) {}
}

// MARK: - Root

struct LabRootView: View {
    let mode: RunMode

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Band.allCases, id: \.self) { band in
                BandContent(band: band)
            }
        }
        .ignoresSafeArea()
        .background(ProbeRunner(mode: mode))
    }
}

/// Fires the measurement once the window exists. Zero-size so it never perturbs the layout.
struct ProbeRunner: UIViewRepresentable {
    let mode: RunMode

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let window = view.window else {
                return
            }
            Task { @MainActor in
                switch mode {
                case .matrix:
                    await MatrixProbe.run(window: window)
                case .feasibility:
                    await FeasibilityProbe.run(window: window)
                case .renderSanity:
                    await RenderSanityProbe.run(window: window)
                case .replayKit:
                    await ReplayKitProbe.run(window: window)
                }
            }
        }
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}
