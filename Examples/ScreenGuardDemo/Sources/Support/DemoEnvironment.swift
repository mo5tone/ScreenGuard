//
//  DemoEnvironment.swift
//  ScreenGuardDemo
//
//  What this build can let a user verify, and what it cannot — decided once, here, so that no card
//  has to guess and no honest limit is left to a small grey caption underneath a misleading visual.
//
//  WHY THIS FILE EXISTS
//  --------------------
//  The first version of this demo presented every capability the same way: a region on screen plus a
//  state readout. That is not verification. On a Simulator it was worse than useless, because the
//  DEFAULT `preventsCapture` path makes its layer paint nothing at all there — so its protected
//  region appeared as a black rectangle that looks exactly like success while proving nothing, while
//  the only measured mechanism (the opt-in private path) showed its content normally and therefore
//  looked broken. A user comparing the two would draw the exact opposite conclusion from the truth.
//
//  A demo whose user cannot produce the evidence is a screenshot with extra steps. So every
//  capability declares how far a user can actually get here, and the UI is built from that answer
//  rather than around it.
//

import Foundation

/// The environment this build runs in, and what that permits.
enum DemoEnvironment {
    /// Whether this process is running on a Simulator.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// A short name for the environment, for the banner.
    static var name: String {
        isSimulator ? "Simulator" : "Device"
    }

    /// How far a user can get for one capability, here and now.
    enum Reach {
        /// The user can produce the evidence in this app with a button, and read the result.
        case verifiable

        /// The app can exercise the mechanism, but its real effect cannot occur here — so any result
        /// would prove nothing. The reason is always stated next to the control.
        case deviceRequired

        /// The system gesture cannot be delivered here. The app can inject a synthetic stand-in,
        /// which is labelled as synthetic wherever it appears.
        case synthetic
    }

    /// The capabilities this demo exposes.
    enum Capability: String, CaseIterable, Identifiable {
        /// Sensitive content staying out of a capture.
        case noLeak
        /// A forensic mark drawn into the capture.
        case watermark
        /// The post-hoc screenshot notification.
        case screenshotDetection
        /// Screen recording / mirroring.
        case recording
        /// The app-switcher snapshot.
        case appSwitcherCover
        /// The public `preventsCapture` path, as distinct from the opt-in private one.
        case publicPath

        /// Stable identity.
        var id: String {
            rawValue
        }
    }

    /// How far a user can get for `capability` in this environment.
    ///
    /// Each answer is tied to a measurement recorded in `docs/TOOLING.md`, not to a guess.
    static func reach(of capability: Capability) -> Reach {
        switch capability {
        case .noLeak, .watermark:
            // The app-side read (`drawHierarchy(afterScreenUpdates: false)`) is available in both
            // environments and is the *same* read `Scripts/verify_capture.sh` grades
            // (`docs/TOOLING.md` §2). So the user can produce real evidence here, with a button.
            .verifiable

        case .publicPath:
            // `preventsCapture = true` makes the layer paint nothing at all on a Simulator,
            // including on screen (`docs/TOOLING.md` §7.1). "Absent from the capture" and "absent
            // from the screen" are indistinguishable there, so there is no result to look at.
            isSimulator ? .deviceRequired : .verifiable

        case .screenshotDetection:
            // A real screenshot needs the side and volume buttons together, and the Simulator has no
            // volume button. The app can post a synthetic notification instead — which proves the
            // wiring and nothing else.
            isSimulator ? .synthetic : .verifiable

        case .recording:
            // `RPScreenRecorder.startCapture` reports `isAvailable = true` and fires its completion
            // with no error, then delivers zero callbacks (`docs/TOOLING.md` §7.2).
            isSimulator ? .deviceRequired : .verifiable

        case .appSwitcherCover:
            // The cover installs and engages on a Simulator, but the snapshot it protects lands in a
            // proprietary KTX variant that neither ImageMagick nor ffmpeg can decode, so its effect
            // cannot be read here.
            isSimulator ? .deviceRequired : .verifiable
        }
    }

    /// Why `capability` is limited here, in one sentence. Empty when it is fully verifiable.
    ///
    /// - Parameter capability: The capability to explain.
    /// - Returns: The reason, or an empty string when there is nothing to explain.
    static func limitation(of capability: Capability) -> String {
        guard reach(of: capability) != .verifiable else {
            return ""
        }
        switch capability {
        case .noLeak, .watermark:
            return ""
        case .publicPath:
            return "On Simulator this layer paints nothing at all — not even on screen — so a blank "
                + "region here is unearned and is not shown as a result. Needs a device."
        case .screenshotDetection:
            return "The Simulator has no volume button, so the side + volume-up gesture cannot be "
                + "performed. The button below posts a SYNTHETIC notification: it proves the wiring, "
                + "not end-to-end delivery. Needs a device."
        case .recording:
            return "RPScreenRecorder reports available and then delivers zero callbacks on a "
                + "Simulator, and UIScreen.isCaptured stays false, so nothing can be concluded here. "
                + "Needs a device."
        case .appSwitcherCover:
            return "The cover installs and engages here, but the snapshot's pixels land in a "
                + "proprietary KTX variant, so its effect cannot be read. Needs a device."
        }
    }

    /// How many capabilities a user can fully verify in this environment.
    static var verifiableCount: Int {
        Capability.allCases.filter { reach(of: $0) == .verifiable }.count
    }

    /// The total number of capabilities the demo exposes.
    static var totalCount: Int {
        Capability.allCases.count
    }
}
