//
//  ScreenGuardSampleBufferFactory.swift
//  ScreenGuard
//
//  Turns a CGImage into a CMSampleBuffer and enqueues it into a display layer.
//  Split out of ScreenGuardShieldView.swift so the availability guard around the deprecated
//  pre-iOS-18 AVSampleBufferDisplayLayer members lives in exactly one place
//  (docs/api-contract.md §7.2), and to keep that file inside the size limit.
//

import AVFoundation
import CoreGraphics
import UIKit

// MARK: - CMSampleBuffer plumbing

/// Turns a `CGImage` into a `CMSampleBuffer` and enqueues it into a display layer.
///
/// Split out so the availability guard around the deprecated pre-iOS-18 `AVSampleBufferDisplayLayer`
/// members lives in exactly one place (docs/api-contract.md §7.2).
@MainActor
enum ScreenGuardSampleBufferFactory {
    /// Enqueues `image` into `layer`, flushing a failed renderer first.
    ///
    /// - Parameters:
    ///   - image: The frame to display.
    ///   - layer: The protected display layer.
    /// - Returns: `true` when a sample buffer was produced and enqueued.
    @discardableResult
    static func enqueue(_ image: CGImage, into layer: AVSampleBufferDisplayLayer) -> Bool {
        guard let buffer = makeSampleBuffer(from: image) else {
            return false
        }
        if #available(iOS 17.0, *) {
            // `sampleBufferRenderer` is the modern spelling. The pre-iOS-18 members are hard-
            // deprecated in iOS 18.0, so they are used ONLY in the else branch, which keeps this
            // clean at an iOS 26 deployment target (docs/api-contract.md §7.2).
            let renderer = layer.sampleBufferRenderer
            if renderer.status == .failed {
                renderer.flush()
            }
            renderer.enqueue(buffer)
        } else {
            if layer.status == .failed {
                layer.flush()
            }
            layer.enqueue(buffer)
        }
        return true
    }

    /// Builds a `CMSampleBuffer` around a BGRA `CVPixelBuffer` holding `image`.
    ///
    /// - Parameter image: The source frame.
    /// - Returns: A ready sample buffer, or `nil` if the pixel buffer could not be created.
    static func makeSampleBuffer(from image: CGImage) -> CMSampleBuffer? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let context = makeBitmapContext(for: pixelBuffer, width: width, height: height) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &format
        ) == noErr, let format else {
            return nil
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            return nil
        }

        return sampleBuffer
    }

    /// A BGRA bitmap context over the pixel buffer base address, or nil when it cannot be addressed.
    ///
    /// Extracted so the caller needs no wrapped condition (whose brace the formatter puts on its own
    /// line, which the opening_brace rule rejects). Call it only while the base address is locked.
    private static func makeBitmapContext(for pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> CGContext? {
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        return CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
