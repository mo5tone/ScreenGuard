//
//  ScreenGuardConfiguration.swift
//  ScreenGuard
//
//  Configuration value type for `ScreenGuardMonitor`. See docs/api-contract.md §6.1.
//

import Foundation

/// Configuration for the ScreenGuard monitor. Value type; safe to copy.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardConfiguration: Equatable, Sendable {
    /// Detect screenshot events. Default `true`.
    public var isScreenshotDetectionEnabled: Bool

    /// Detect capture-state changes (recording / mirroring / AirPlay). Default `true`.
    public var isCaptureStateDetectionEnabled: Bool

    /// Install the app-switcher snapshot cover on the app's key window. Default `true`.
    ///
    /// Defaults to `true` because it is the one capability that needs no host action to be useful,
    /// and it is the same behaviour SwiftUI's `privacySensitive()` provides. It is switchable off in
    /// one line for hosts that manage their own scenes.
    public var isAppSwitcherShieldEnabled: Bool

    /// Which mechanism protects views marked with the no-leak shield. Default
    /// `.publicPreventsCaptureLayer`.
    ///
    /// The private path (`.privateSecureLayer`) is never the default. See `docs/api-contract.md` §9.
    public var noLeakStrategy: ScreenGuardNoLeakStrategy

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - isScreenshotDetectionEnabled: Detect screenshot events. Default `true`.
    ///   - isCaptureStateDetectionEnabled: Detect capture-state changes. Default `true`.
    ///   - isAppSwitcherShieldEnabled: Install the app-switcher cover on the key window. Default
    ///     `true`.
    ///   - noLeakStrategy: The no-leak mechanism. Default `.publicPreventsCaptureLayer`.
    public init(
        isScreenshotDetectionEnabled: Bool = true,
        isCaptureStateDetectionEnabled: Bool = true,
        isAppSwitcherShieldEnabled: Bool = true,
        noLeakStrategy: ScreenGuardNoLeakStrategy = .publicPreventsCaptureLayer
    ) {
        self.isScreenshotDetectionEnabled = isScreenshotDetectionEnabled
        self.isCaptureStateDetectionEnabled = isCaptureStateDetectionEnabled
        self.isAppSwitcherShieldEnabled = isAppSwitcherShieldEnabled
        self.noLeakStrategy = noLeakStrategy
    }
}
