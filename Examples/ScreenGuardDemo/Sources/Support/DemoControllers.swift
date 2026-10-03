//
//  DemoControllers.swift
//  ScreenGuardDemo
//
//  Small state holders the cards drive. Kept out of the view so the view stays about presentation
//  and the honest labels, which is where the demo's real difficulty lives.
//

import SwiftUI
import UIKit
import ReplayKit
import ScreenGuard

/// A snapshot of a shield's real state, so a card can report what the shield *is doing* rather than
/// what it was asked to do.
struct DemoShieldSummary: Equatable {

    /// Whether the shield is actually protecting.
    var isProtecting = false

    /// The shield's mode, as its raw value.
    var shieldMode = ScreenGuardShieldMode.disabled.rawValue

    /// The failure reason, as its raw value, or `"none"`.
    var failure = "none"

    /// Creates an empty summary.
    init() {}

    /// Captures a shield's current state.
    ///
    /// `@MainActor` because every public ScreenGuard type is (`docs/api-contract.md` §10) — the
    /// shield's properties cannot be read from anywhere else.
    ///
    /// - Parameter shield: The shield to read.
    @MainActor
    init(shield: ScreenGuardShieldView) {
        isProtecting = shield.isProtecting
        shieldMode = shield.shieldMode.rawValue
        failure = shield.protectionFailure?.rawValue ?? "none"
    }
}

/// Drives a real `RPScreenRecorder` session and counts what it delivers.
///
/// The point is not to record anything useful — it is that the user can press the button and watch
/// the counters. On a Simulator they stay at zero while `isAvailable` reads `true`, which is the
/// honest demonstration of why the recording path is `notMeasured` rather than claimed
/// (`docs/TOOLING.md` §7.2).
@MainActor
final class DemoRecorder: ObservableObject {

    /// Whether a capture session is running.
    @Published private(set) var isRecording = false

    /// Video buffers delivered so far.
    @Published private(set) var videoBuffers = 0

    /// Audio buffers delivered so far.
    @Published private(set) var audioBuffers = 0

    /// What happened, in plain words.
    @Published private(set) var status = "Not started."

    /// Whether ReplayKit reports itself usable here.
    @Published private(set) var isAvailable = RPScreenRecorder.shared().isAvailable

    /// Starts a capture session and begins counting.
    func start() {
        let recorder = RPScreenRecorder.shared()
        isAvailable = recorder.isAvailable
        guard recorder.isAvailable else {
            status = "RPScreenRecorder reports itself unavailable."
            return
        }
        videoBuffers = 0
        audioBuffers = 0
        status = "Starting…"
        recorder.isMicrophoneEnabled = false
        recorder.startCapture { [weak self] sample, type, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "startCapture handler reported: \(error.localizedDescription)"
                    return
                }
                switch type {
                case .video: self.videoBuffers += 1
                case .audioApp, .audioMic: self.audioBuffers += 1
                @unknown default: break
                }
                self.status = "Receiving buffers."
            }
        } completionHandler: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = error == nil
                if let error {
                    self.status = "startCapture failed: \(error.localizedDescription)"
                } else {
                    self.status = "Session started — counting buffers."
                }
            }
        }
    }

    /// Stops the session and reports what arrived.
    func stop() {
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = false
                if let error {
                    self.status = "stopCapture failed: \(error.localizedDescription)"
                    return
                }
                self.status = "Stopped after \(self.videoBuffers) video and "
                    + "\(self.audioBuffers) audio buffers."
            }
        }
    }
}
