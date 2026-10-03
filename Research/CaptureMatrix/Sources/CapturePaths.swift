import AVFoundation
import ReplayKit
import UIKit

/// The capture paths under test. Each returns a normalised RGBA8 `CGImage` plus a one-line
/// provenance string that goes into the evidence doc.
enum CapturePaths {

    struct Result {
        let path: String
        let image: CGImage?
        let note: String
        let detail: [String: Any]
    }

    // MARK: - Path A: app-side render

    /// `window.drawHierarchy(in:afterScreenUpdates: false)` - the app rendering its own hierarchy
    /// into a bitmap. This is the app-side read a "screenshot-like" API takes.
    ///
    /// `afterScreenUpdates` MUST stay `false`: `true` forces a CATransaction commit mid-render and
    /// UIKit asserts inside `_UIRenderViewImageAfterCommit` (already reproduced as SIGABRT).
    static func appRender(window: UIWindow) -> Result {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let cgImage = image.cgImage else {
            return Result(path: "app-render(drawHierarchy)", image: nil,
                          note: "no CGImage produced", detail: [:])
        }
        let detail: [String: Any] = [
            "bitsPerComponent": cgImage.bitsPerComponent,
            "bitsPerPixel": cgImage.bitsPerPixel,
            "bytesPerRow": cgImage.bytesPerRow,
            "width": cgImage.width,
            "height": cgImage.height,
        ]
        let note = "\(cgImage.width)x\(cgImage.height) bpc=\(cgImage.bitsPerComponent) bpp=\(cgImage.bitsPerPixel)"
        return Result(path: "app-render(drawHierarchy)", image: cgImage, note: note, detail: detail)
    }

    // MARK: - Path B: system capture pipeline

    /// `RPScreenRecorder.shared().startCapture` - the system capture pipeline a screen recording
    /// uses. This is the path that matters for "does a recording leak content".
    ///
    /// Bounded to 12s: ReplayKit may present a consent prompt or simply never deliver a frame, and
    /// the run must record "unavailable" honestly rather than hang.
    static func replayKit(timeout: Double = 12) async -> Result {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            return Result(path: "system-capture(RPScreenRecorder)", image: nil,
                          note: "recorder.isAvailable == false", detail: ["isAvailable": false])
        }

        let box = FrameBox()
        RunLog.shared.log("system-capture: isAvailable=\(recorder.isAvailable) isRecording=\(recorder.isRecording) isMicrophoneEnabled=\(recorder.isMicrophoneEnabled)")
        let started = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            recorder.startCapture { sampleBuffer, type, error in
                if let error {
                    RunLog.shared.log("system-capture: handler error: \(error.localizedDescription)")
                    box.fail(error.localizedDescription)
                    if box.claimContinuation() { continuation.resume(returning: false) }
                    return
                }
                // Log the first buffer of every type, so a "no video frame" result can be told apart
                // from "the pipeline never called back at all".
                box.note(type: type)
                guard type == .video else { return }
                guard let frame = FrameBox.describe(sampleBuffer) else { return }
                if box.store(frame), box.claimContinuation() {
                    continuation.resume(returning: true)
                }
            } completionHandler: { error in
                if let error {
                    RunLog.shared.log("system-capture: startCapture failed: \(error.localizedDescription)")
                    box.fail(error.localizedDescription)
                    if box.claimContinuation() { continuation.resume(returning: false) }
                } else {
                    RunLog.shared.log("system-capture: startCapture completion fired with no error (pipeline is live)")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if box.claimContinuation() {
                    RunLog.shared.log("system-capture: no frame within \(Int(timeout))s; "
                        + "bufferTypesSeen=\(box.bufferTypesSeen) callbackInvocations=\(box.callbackInvocations)")
                    continuation.resume(returning: false)
                }
            }
        }

        // Give the pipeline a moment to actually deliver a frame after startCapture returns.
        if started, box.frame == nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        recorder.stopCapture { error in
            if let error { RunLog.shared.log("system-capture: stopCapture error: \(error.localizedDescription)") }
        }

        guard let frame = box.frame else {
            return Result(path: "system-capture(RPScreenRecorder)", image: nil,
                          note: box.failure ?? "started but no video frame arrived (bounded \(Int(timeout))s wait)",
                          detail: ["isAvailable": true, "frameReceived": false])
        }
        let detail: [String: Any] = [
            "isAvailable": true,
            "frameReceived": true,
            "pixelFormat": frame.pixelFormat,
            "width": frame.image.width,
            "height": frame.image.height,
        ]
        return Result(path: "system-capture(RPScreenRecorder)", image: frame.image,
                      note: "\(frame.image.width)x\(frame.image.height) pixelFormat=\(frame.pixelFormat) codec=\(frame.codecType)",
                      detail: detail)
    }

    /// Holds the first video frame and makes "resume exactly once" thread-safe.
    private final class FrameBox: @unchecked Sendable {
        struct Frame {
            let image: CGImage
            let pixelFormat: OSType
            let codecType: String
        }

        private let lock = NSLock()
        private var claimed = false
        private var stored: Frame?
        private(set) var failure: String?
        private(set) var bufferTypesSeen: [String] = []
        private(set) var callbackInvocations = 0

        var frame: Frame? {
            lock.lock(); defer { lock.unlock() }
            return stored
        }

        /// Records that the capture callback fired and with what, so "no video frame" is
        /// distinguishable from "the pipeline never called back".
        func note(type: RPSampleBufferType) {
            lock.lock(); defer { lock.unlock() }
            callbackInvocations += 1
            let name: String
            switch type {
            case .video: name = "video"
            case .audioApp: name = "audioApp"
            case .audioMic: name = "audioMic"
            @unknown default: name = "unknown(\(type.rawValue))"
            }
            if !bufferTypesSeen.contains(name) { bufferTypesSeen.append(name) }
        }

        func claimContinuation() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }

        func store(_ frame: Frame) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard stored == nil else { return false }
            stored = frame
            return true
        }

        func fail(_ message: String) {
            lock.lock(); defer { lock.unlock() }
            failure = message
        }

        static func describe(_ sampleBuffer: CMSampleBuffer) -> Frame? {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
            let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let image = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
            var codec = "unknown"
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let subtype = CMFormatDescriptionGetMediaSubType(format) as FourCharCode? {
                codec = fourCC(subtype)
            }
            return Frame(image: image, pixelFormat: pixelFormat, codecType: codec)
        }

        private static func fourCC(_ value: FourCharCode) -> String {
            let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
            return String(bytes: bytes, encoding: .ascii) ?? "\(value)"
        }
    }

    // MARK: - Supplementary: layer-tree render

    /// `CALayer.render(in:)` - the *other* public app-side read. It walks the layer tree directly
    /// instead of going through the render server, so it is worth knowing whether it bypasses
    /// protection that `drawHierarchy` honours. Supplementary column, not a required path.
    ///
    /// `CALayer.render(in:)` draws with a **bottom-left origin** and flips vertically relative to
    /// UIKit's top-left coordinate space. Without the flip, every band is sampled in the wrong place
    /// - which is exactly what made the first run of this harness report nonsense for this path.
    static func layerRender(window: UIWindow) -> Result {
        let width = Int(window.bounds.width)
        let height = Int(window.bounds.height)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: PixelAnalyzer.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Result(path: "app-render(layer.render)", image: nil, note: "no context", detail: [:])
        }
        // Match UIKit's top-left origin so band fractions mean the same thing on every path.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        window.layer.render(in: context)
        guard let image = context.makeImage() else {
            return Result(path: "app-render(layer.render)", image: nil, note: "no CGImage", detail: [:])
        }
        return Result(path: "app-render(layer.render)", image: image,
                      note: "\(image.width)x\(image.height) via CALayer.render(in:) (flipped to top-left origin)",
                      detail: ["width": image.width, "height": image.height, "origin": "top-left after flip"])
    }
}
