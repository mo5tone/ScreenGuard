//
//  DemoConfig.swift
//  ScreenGuardDemo
//
//  Launch-argument parsing for the scripted probe. Everything here is read-only configuration; the
//  demo has no other hidden state.
//
//  The probe exists so `Scripts/verify_capture.sh` can drive the app headlessly and read back a
//  deterministic page. When no probe mode is passed the app shows the normal interactive demo.
//

import Foundation

/// Launch-argument configuration for the example app.
enum DemoConfig {
    /// What the app should do at launch.
    ///
    /// `none` is the interactive demo a human looks at. Every other case is a scripted probe that
    /// renders a fixed page and writes machine-readable artifacts into the app's Documents
    /// directory, which `Scripts/verify_capture.sh` pulls out with `simctl get_app_container`.
    enum ProbeMode: String {
        /// The interactive demo. Default.
        case none
        /// The three-region no-leak page: an unshielded control, a public-path shield and an
        /// opt-in private-path shield, all over one sentinel background.
        case noLeak
        /// The SwiftUI-route page: the package's own
        /// `.screenGuardProtected(strategy: .privateSecureLayer)` modifier over a sentinel, with an
        /// unshielded SwiftUI control. Measures the route that supplies content only through a render
        /// closure (review round 2, F-R2-1).
        case swiftUIPrivate
        /// The two matched watermark bands: one wearing the tiled mark, one without it. Establishes
        /// that the mark IS drawn into the capture (a deterrent, not a protection) and that the
        /// unmarked control band is flat (the calibration), and emits the tile geometry so the script
        /// can check coverage independently.
        case watermark
        /// Starts `ScreenGuardMonitor` and reports what detection actually observes.
        case detection
        /// Dumps the package's capability registry, so the script can assert the demo does not
        /// imply prevention.
        case capability
        /// Installs `ScreenGuardAppSwitcherShield` and logs every cover transition with a timestamp,
        /// so a host-side Home press can be correlated with the cover engaging.
        case appSwitcher
    }

    /// Reads `-Key value` out of the process arguments, the way `simctl launch` passes them.
    ///
    /// - Parameter key: The argument name, including its leading dash.
    /// - Returns: The following argument, or `nil` when the key is absent or last.
    static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    /// The probe to run.
    /// `-ProbeMode noLeak|swiftUIPrivate|watermark|detection|capability|appSwitcher`.
    static var probeMode: ProbeMode {
        ProbeMode(rawValue: value(for: "-ProbeMode") ?? "") ?? .none
    }

    /// A run identifier supplied by the host script, so artifacts are attributable to one run.
    static var runID: String {
        value(for: "-RunID") ?? "adhoc"
    }

    /// Whether the scripted run should grant the private-API opt-in.
    ///
    /// **This is off unless the caller passes `-PrivateOptIn 1` explicitly.** The private secure-layer
    /// path is a private API: non-contract, fragile across iOS releases, an App Review risk, and never
    /// a security guarantee (`docs/api-contract.md` §9). Nothing in the demo turns it on by itself —
    /// see `DemoRootView`'s toggle, which is the interactive equivalent of this flag.
    static var privateOptIn: Bool {
        value(for: "-PrivateOptIn") == "1"
    }

    /// Whether a scripted probe is running.
    static var isProbing: Bool {
        probeMode != .none
    }
}
