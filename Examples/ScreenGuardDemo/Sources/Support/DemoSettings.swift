//
//  DemoSettings.swift
//  ScreenGuardDemo
//
//  Every knob the demo exposes, in one place, so a user can change what the library is asked to do
//  and then re-run the check themselves.
//
//  Two kinds of setting live here and they behave differently on purpose:
//
//    * **Live** settings take effect immediately (`protectedStrategy`, `privateOptIn`, the watermark,
//      the cover style). They are read by the views that use them.
//    * **Restart** settings are baked into `ScreenGuardMonitor` at construction
//      (`ScreenGuardConfiguration` is not mutable after the monitor exists). Changing one bumps
//      `detectionGeneration`, which re-creates the monitor — the UI says so rather than silently
//      ignoring the switch.
//

import ScreenGuard
import SwiftUI

/// The demo's user-facing settings.
@MainActor
final class DemoSettings: ObservableObject {
    // MARK: - No-leak shield

    /// The strategy the protected card requests.
    ///
    /// Defaults to `.disabled` rather than the library's `.publicPreventsCaptureLayer` default. On a
    /// Simulator that default paints nothing, so a user starting there would see a black rectangle,
    /// learn nothing, and be unable to tell it apart from success. The demo therefore starts from a
    /// state where the user can see the *difference* the switch makes.
    @Published var protectedStrategy: ScreenGuardNoLeakStrategy = .disabled

    /// Whether the opt-in private API is granted at runtime.
    ///
    /// Applied straight to `ScreenGuard.PrivateAPI.isEnabled`, which is exactly what a host app would
    /// do — the demo has no private path of its own.
    ///
    /// Flipping it also bumps `privateOptInGeneration`. A shield evaluates the opt-in when it
    /// engages and does not re-evaluate it, so without that signal a user who selects the private
    /// strategy first and grants the opt-in second would watch a switch do nothing.
    @Published var privateOptIn: Bool = false {
        didSet {
            ScreenGuard.PrivateAPI.isEnabled = privateOptIn
            privateOptInGeneration += 1
        }
    }

    /// Bumped whenever `privateOptIn` changes, so shields re-apply their strategy.
    @Published private(set) var privateOptInGeneration: Int = 0

    // MARK: - Watermark

    /// Whether the watermark overlay is applied to the marked card.
    @Published var watermarkEnabled: Bool = true

    /// The primary watermark text.
    @Published var watermarkText: String = "CONFIDENTIAL"

    /// The watermark's opacity, 0...1.
    @Published var watermarkOpacity: Double = 0.28

    // MARK: - App-switcher cover

    /// Whether the cover is opaque or a blur.
    ///
    /// Opaque by default. A blur is not a redaction: it leaves the underlying pixels recoverable in
    /// principle, so offering it as the default would overstate what the cover does.
    @Published var coverIsOpaque: Bool = true

    // MARK: - Detection (restart settings)

    /// Whether screenshot detection is on.
    @Published var screenshotDetectionEnabled: Bool = true

    /// Whether capture-state detection is on.
    @Published var captureStateDetectionEnabled: Bool = true

    /// Whether `ScreenGuardMonitor.start()` also installs the app-switcher cover.
    ///
    /// Off by default *in the demo*, so that installing a cover is something the user asks for on the
    /// cover's own card rather than a side effect of starting detection.
    @Published var coverOnMonitorStart: Bool = false

    /// Bumped whenever a restart setting changes, so the detection card can rebuild its monitor.
    @Published private(set) var detectionGeneration: Int = 0

    /// The configuration the next `ScreenGuardMonitor` will be built with.
    var detectionConfiguration: ScreenGuardConfiguration {
        ScreenGuardConfiguration(
            isScreenshotDetectionEnabled: screenshotDetectionEnabled,
            isCaptureStateDetectionEnabled: captureStateDetectionEnabled,
            isAppSwitcherShieldEnabled: coverOnMonitorStart
        )
    }

    /// Marks the restart settings as changed, so the monitor is rebuilt.
    func applyDetectionSettings() {
        detectionGeneration += 1
    }

    /// The watermark configuration for the marked card, or `nil` when it is switched off.
    var watermarkConfiguration: ScreenGuardWatermarkConfiguration? {
        guard watermarkEnabled else {
            return nil
        }
        return ScreenGuardWatermarkConfiguration(
            text: watermarkText.isEmpty ? "CONFIDENTIAL" : watermarkText,
            secondaryText: "demo session 4417",
            opacity: CGFloat(watermarkOpacity)
        )
    }
}
