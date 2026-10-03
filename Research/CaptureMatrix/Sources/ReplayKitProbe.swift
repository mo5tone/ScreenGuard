import AVFoundation
import ReplayKit
import SwiftUI
import UIKit

/// Focused diagnostic for the system capture pipeline, because "ReplayKit delivered nothing" is only
/// an honest result if every alternative was actually tried.
///
/// Tries, in order, and logs exactly how far each got:
///   1. `RPScreenRecorder.startCapture` with a long bound
///   2. `RPScreenRecorder.startRecording` (the other public entry point)
///   3. `UIScreen.isCaptured` / `capturedDidChangeNotification` - does the OS even consider the
///      screen to be under capture?
///
/// The point is to be able to say *why* the recording path is unmeasurable, not merely that it was.
enum ReplayKitProbe {

    @MainActor
    static func run(window: UIWindow) async {
        let log = RunLog.shared
        let runID = Config.runID
        log.log("=== CaptureMatrix replaykit \(runID) ===")

        let recorder = RPScreenRecorder.shared()
        log.log("RK recorder isAvailable=\(recorder.isAvailable) isRecording=\(recorder.isRecording) "
            + "isMicrophoneEnabled=\(recorder.isMicrophoneEnabled)")
        log.log("RK UIScreen.main.isCaptured=\(UIScreen.main.isCaptured)")

        // Observe capture-state changes for the whole run; if the OS ever thinks a capture is live,
        // that is the single most useful signal about whether the pipeline engages at all.
        var observations = 0
        let token = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main
        ) { _ in
            observations += 1
            RunLog.shared.log("RK capturedDidChange fired; isCaptured=\(UIScreen.main.isCaptured)")
        }

        // --- 1. startCapture -------------------------------------------------
        log.log("RK attempting startCapture (bound 30s)")
        let captureResult = await attemptCapture(recorder: recorder, bound: 30)
        log.log("RK startCapture result: \(captureResult)")

        recorder.stopCapture { error in
            RunLog.shared.log("RK stopCapture completion error=\(error?.localizedDescription ?? "none")")
        }

        // --- 2. startRecording ----------------------------------------------
        log.log("RK attempting startRecording (bound 15s)")
        let recordingResult = await attemptRecording(recorder: recorder, bound: 15)
        log.log("RK startRecording result: \(recordingResult)")

        // --- 3. capture state -------------------------------------------------
        NotificationCenter.default.removeObserver(token)
        log.log("RK capturedDidChange observations=\(observations) finalIsCaptured=\(UIScreen.main.isCaptured)")
        log.log("RK CONCLUSION: \(captureResult) | \(recordingResult)")

        log.log("WROTE \(log.writeText("replaykit-\(runID).log").path)")
        log.log("=== CaptureMatrix replaykit \(runID) done ===")
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    private static func attemptCapture(recorder: RPScreenRecorder, bound: Double) async -> String {
        let box = Counter()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            recorder.startCapture { sampleBuffer, type, error in
                box.record(type: type, sampleBuffer: sampleBuffer, error: error)
                if box.isFirstVideo, box.claim() {
                    continuation.resume(returning: "DELIVERED video frame after \(box.videoFrames) video buffers")
                }
            } completionHandler: { error in
                box.completionError = error?.localizedDescription
                RunLog.shared.log("RK startCapture completion error=\(error?.localizedDescription ?? "none")")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + bound) {
                if box.claim() {
                    continuation.resume(returning: "NO FRAME in \(Int(bound))s "
                        + "(callbacks=\(box.callbacks) video=\(box.videoFrames) "
                        + "audioApp=\(box.audioApp) audioMic=\(box.audioMic) "
                        + "nilImageBuffer=\(box.nilImageBuffer) completionError=\(box.completionError ?? "none"))")
                }
            }
        }
    }

    private static func attemptRecording(recorder: RPScreenRecorder, bound: Double) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish: () -> Void = {
                if !resumed { resumed = true; continuation.resume() }
            }
            recorder.startRecording { error in
                RunLog.shared.log("RK startRecording completion error=\(error?.localizedDescription ?? "none") "
                    + "isRecording=\(recorder.isRecording)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + bound) {
                RunLog.shared.log("RK after \(Int(bound))s isRecording=\(recorder.isRecording)")
                recorder.stopRecording { preview, error in
                    RunLog.shared.log("RK stopRecording completion error=\(error?.localizedDescription ?? "none") "
                        + "previewVC=\(preview != nil ? "present" : "nil")")
                    finish()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish() }
            }
        }
        return "see RK startRecording/stopRecording lines above"
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        private(set) var callbacks = 0
        private(set) var videoFrames = 0
        private(set) var audioApp = 0
        private(set) var audioMic = 0
        private(set) var nilImageBuffer = 0
        private(set) var isFirstVideo = false
        var completionError: String?

        func record(type: RPSampleBufferType, sampleBuffer: CMSampleBuffer, error: Error?) {
            lock.lock(); defer { lock.unlock() }
            callbacks += 1
            if let error {
                RunLog.shared.log("RK handler error type=\(type.rawValue): \(error.localizedDescription)")
                return
            }
            switch type {
            case .video:
                videoFrames += 1
                if CMSampleBufferGetImageBuffer(sampleBuffer) == nil { nilImageBuffer += 1 }
                else if videoFrames == 1 {
                    isFirstVideo = true
                    let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
                    RunLog.shared.log("RK FIRST VIDEO FRAME \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) "
                        + "format=\(CVPixelBufferGetPixelFormatType(buffer))")
                }
            case .audioApp: audioApp += 1
            case .audioMic: audioMic += 1
            @unknown default: break
            }
        }

        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }
}

struct ReplayKitProbeView: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .background(ProbeRunner(mode: .replayKit))
    }
}
