//
//  DemoRootView.swift
//  ScreenGuardDemo
//
//  The interactive demo, rebuilt so that a user *verifies* the library rather than looking at a
//  picture of it.
//
//  WHAT WAS WRONG BEFORE
//  ---------------------
//  The first version showed four capability sections whose content was a region on screen plus a
//  state readout. Nothing a user could do produced evidence, and on a Simulator the presentation was
//  inverted: the default `preventsCapture` path paints nothing there, so its region appeared as a
//  black rectangle that reads exactly like success, while the opt-in private path — the only
//  mechanism measured to work — showed its content normally and therefore looked broken. A user
//  comparing the two would conclude the opposite of the truth.
//
//  If a demo cannot be verified by its user, it is a screenshot with extra steps.
//
//  WHAT IT DOES NOW
//  ----------------
//  1. Every capability declares how far a user can get in this environment (`DemoEnvironment`), and
//     the card says so at the top rather than in a caption underneath.
//  2. The verifiable capabilities get a **Capture** button. It takes the app-side read of the window
//     — the same read `Scripts/verify_capture.sh` grades — shows the user the image, and classifies
//     known regions so the result is a verdict, not an impression.
//  3. The capture always includes an **unshielded control**, so a blank protected region cannot be
//     explained away as a dead read path. That ambiguity is an open review finding; the demo closes
//     it by construction instead of asserting past it.
//  4. Capabilities that need hardware are still shown, with the reason and — where a gesture is
//     missing rather than the mechanism — a clearly labelled synthetic stand-in.
//

import SwiftUI
import UIKit
import ScreenGuard

/// The interactive demo screen.
struct DemoRootView: View {

    /// The user-facing settings.
    @StateObject private var settings = DemoSettings()

    /// The ReplayKit session the recording card drives.
    @StateObject private var recorder = DemoRecorder()

    /// The most recent app-side capture, when the user has taken one.
    @State private var captured: DemoCapturedFrame?

    /// Whether the full-size capture sheet is open.
    ///
    /// Deliberately *not* opened automatically by the Capture button. Auto-presenting put a
    /// full-height image over the screen and pushed the verdict — the actual answer — below the fold,
    /// which would have made this a picture viewer again. The result lands inline where the button
    /// is; the sheet is opt-in by tapping the image.
    @State private var showingCaptureSheet = false

    /// How many regions the last capture could not sample because they were off screen.
    @State private var captureOmitted = 0

    /// The card rectangles, in window coordinates, for `DemoCapture` to sample.
    @State private var controlFrame: CGRect = .zero
    @State private var protectedFrame: CGRect = .zero
    @State private var watermarkFrame: CGRect = .zero

    /// The protected shield's real state.
    @State private var shieldState = DemoShieldSummary()

    /// The app-switcher cover the user installed, if any.
    @State private var cover: ScreenGuardAppSwitcherShield?

    /// Whether the status sheet is open.
    @State private var showingStatus = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    environmentBanner
                    verificationStrip
                    noLeakCard
                    watermarkCard
                    detectionCard
                    recordingCard
                    appSwitcherCard
                    statusLink
                }
                .padding(16)
            }
            .navigationTitle("ScreenGuard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Status") { showingStatus = true }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingCaptureSheet) {
            if let captured { CaptureResultSheet(frame: captured) }
        }
        .sheet(isPresented: $showingStatus) {
            DemoCapabilityScreen().ignoresSafeArea()
        }
        .onAppear { ScreenGuard.PrivateAPI.isEnabled = settings.privateOptIn }
    }

    // MARK: - Environment banner

    private var environmentBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: DemoEnvironment.isSimulator ? "desktopcomputer" : "iphone")
                Text("Running on \(DemoEnvironment.name)").font(.headline)
            }
            Text("\(DemoEnvironment.verifiableCount) of \(DemoEnvironment.totalCount) capabilities "
                + "can be fully verified here. The rest need a device, and each card says why.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("ScreenGuard detects captures and keeps sensitive content out of them. iOS does not "
                + "allow an app to prevent a screenshot or a recording, and this demo does not either.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    // MARK: - Verification strip

    private var verificationStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                takeCapture()
            } label: {
                Label("Capture this screen (app-side read)", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let captured {
                captureResult(captured)
            } else {
                Text("This takes the same read of the window that the verification script grades, "
                    + "shows you the image, and says what it found. It always includes an unshielded "
                    + "control card so the result cannot be explained away.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.10))
        .cornerRadius(12)
    }

    /// The inline result of a capture: verdicts, a one-line conclusion, and the image.
    @ViewBuilder
    private func captureResult(_ frame: DemoCapturedFrame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(frame.readings) { reading in
                HStack(spacing: 8) {
                    Text(reading.label).font(.caption.monospaced())
                    Spacer(minLength: 8)
                    Text(reading.verdict.rawValue)
                        .font(.caption.bold().monospaced())
                        .foregroundColor(reading.verdict.indicatesExclusion ? .green : .primary)
                    Text(reading.colour)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
            }

            Text(conclusion(for: frame))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            if captureOmitted > 0 {
                Text("\(captureOmitted) card(s) were off screen and are not in this capture — scroll "
                    + "until the card you want is visible, then capture again.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { showingCaptureSheet = true } label: {
                Image(uiImage: frame.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 130)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5)))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Text("Tap the image to inspect it full size.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("This image is the app-side read — the same one the verification script grades, and "
                + "what a real capture contains on its app side. On a device, a screenshot taken with "
                + "side + volume-up contains the same thing. Do NOT check with the Simulator's own "
                + "screenshot or Cmd+S: that captures the host display and bypasses protection, so it "
                + "will show the content and tell you nothing.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one-line conclusion for a capture, with the control qualifying it.
    private func conclusion(for frame: DemoCapturedFrame) -> String {
        guard frame.readPathIsDemonstrated else {
            return "Inconclusive: the control card did not carry its secret into this image, so a "
                + "blank protected region could simply mean the read path painted nothing. This is "
                + "exactly the ambiguity the control exists to rule out."
        }
        let protectedReading = frame.readings.first { $0.label.hasPrefix("Protected") }
        switch protectedReading?.verdict {
        case .sentinel:
            return "Verified: the control kept its secret while the protected region was excluded "
                + "from the same image. That is the no-leak result, produced by you, just now."
        case .sensitive:
            return "Not protected at this setting: the protected region is present in the capture. "
                + "Change the strategy below and capture again."
        case .black:
            return "Ambiguous: the protected region reads black, which can mean excluded or never "
                + "painted. Choose the private path to get an unambiguous reading."
        default:
            return "Inconclusive: the protected region reads "
                + "\(protectedReading?.verdict.rawValue ?? "nothing")."
        }
    }

    // MARK: - 1. No-leak

    private var noLeakCard: some View {
        CapabilityCard(
            number: 1,
            title: "No-leak shield",
            subtitle: "Protected content must not appear in a capture.",
            reach: DemoEnvironment.reach(of: .noLeak),
            limitation: DemoEnvironment.limitation(of: .noLeak)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Strategy", selection: $settings.protectedStrategy) {
                    Text("Disabled").tag(ScreenGuardNoLeakStrategy.disabled)
                    Text("Public preventsCapture").tag(ScreenGuardNoLeakStrategy.publicPreventsCaptureLayer)
                    Text("Private secure layer").tag(ScreenGuardNoLeakStrategy.privateSecureLayer)
                }
                .pickerStyle(.segmented)

                Toggle("Grant the opt-in private API", isOn: $settings.privateOptIn)

                Text("Private path compiled into this build: "
                    + (ScreenGuard.PrivateAPI.isCompiledIn ? "yes" : "no"))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if settings.protectedStrategy == .privateSecureLayer, !settings.privateOptIn {
                    Text("The private strategy is selected but the opt-in is off, so the shield falls "
                        + "back. Turn the toggle on to use it.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                regionPair
                shieldReadout

                Text("Tap **Capture this screen** above. The control card is unshielded on purpose: if "
                    + "it keeps its secret in the captured image while the protected card does not, "
                    + "the exclusion is real and the read path is proven to work.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("On a device you can also check end to end: press side + volume-up, then open "
                    + "Photos. The protected region comes out blank there while staying visible on "
                    + "screen.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var regionPair: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Control (unshielded)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                secretCard
                    .frame(height: 96)
                    .reportFrame { controlFrame = $0 }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Protected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                protectedRegion
                    .frame(height: 96)
                    .reportFrame { protectedFrame = $0 }
            }
        }
    }

    /// The protected region.
    ///
    /// On Simulator the public strategy is deliberately **not drawn**. It paints nothing there, so a
    /// black rectangle would be indistinguishable from success and would teach the user the wrong
    /// lesson; an explicit placeholder teaches the right one.
    @ViewBuilder
    private var protectedRegion: some View {
        if settings.protectedStrategy == .publicPreventsCaptureLayer, DemoEnvironment.isSimulator {
            notDrawnPlaceholder
        } else {
            DemoShieldRepresentable(
                strategy: settings.protectedStrategy,
                optInGeneration: settings.privateOptInGeneration,
                onStateChange: { shieldState = DemoShieldSummary(shield: $0) },
                content: { AnyView(secretCard) }
            )
            .background(Color(uiColor: DemoGeometry.sentinelColour))
        }
    }

    private var notDrawnPlaceholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "eye.slash")
            Text("Not drawn here")
                .font(.caption.bold())
            Text("On Simulator this layer paints nothing at all, so there is nothing to look at. "
                + "Left empty rather than black on purpose — a black rectangle here is "
                + "indistinguishable from success.")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.secondary)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(.secondary)
        )
        .cornerRadius(6)
    }

    private var shieldReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            readoutRow("isProtecting", shieldState.isProtecting ? "true" : "false")
            readoutRow("shieldMode", shieldState.shieldMode)
            readoutRow("protectionFailure", shieldState.failure)
        }
    }

    // MARK: - 2. Watermark

    private var watermarkCard: some View {
        CapabilityCard(
            number: 2,
            title: "Forensic watermark",
            subtitle: "Deterrent and attribution only. It removes no pixels.",
            reach: DemoEnvironment.reach(of: .watermark),
            limitation: DemoEnvironment.limitation(of: .watermark)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Draw the watermark", isOn: $settings.watermarkEnabled)

                HStack {
                    Text("Text").font(.caption)
                    TextField("CONFIDENTIAL", text: $settings.watermarkText)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }

                HStack {
                    Text("Opacity").font(.caption)
                    Slider(value: $settings.watermarkOpacity, in: 0.05...0.9)
                    Text(String(format: "%.2f", settings.watermarkOpacity))
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }

                markedCard
                    .frame(height: 96)
                    .reportFrame { watermarkFrame = $0 }

                Text("Capture it above: the mark appears inside the capture, which is what makes a "
                    + "leaked image attributable. It is not a protection — it stops nothing and does "
                    + "not survive cropping or downscaling.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var markedCard: some View {
        if let configuration = settings.watermarkConfiguration {
            secretCard.screenGuardWatermarked(configuration).cornerRadius(6)
        } else {
            secretCard
        }
    }

    // MARK: - 3. Detection

    private var detectionCard: some View {
        CapabilityCard(
            number: 3,
            title: "Capture detection",
            subtitle: "Observed and reported — never blocked.",
            reach: DemoEnvironment.reach(of: .screenshotDetection),
            limitation: DemoEnvironment.limitation(of: .screenshotDetection)
        ) {
            DetectionCardBody(configuration: settings.detectionConfiguration)
                .id(settings.detectionGeneration)
        }
    }

    // MARK: - 4. Recording

    private var recordingCard: some View {
        CapabilityCard(
            number: 4,
            title: "Screen recording",
            subtitle: "Not measured on any path. No guarantee is claimed.",
            reach: DemoEnvironment.reach(of: .recording),
            limitation: DemoEnvironment.limitation(of: .recording)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    recorder.isRecording ? recorder.stop() : recorder.start()
                } label: {
                    Label(
                        recorder.isRecording ? "Stop the ReplayKit session" : "Try a real ReplayKit session",
                        systemImage: recorder.isRecording ? "stop.circle" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                readoutRow("isAvailable", recorder.isAvailable ? "true" : "false")
                readoutRow("videoBuffers", "\(recorder.videoBuffers)")
                readoutRow("audioBuffers", "\(recorder.audioBuffers)")

                Text(recorder.status)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Press it and watch the counters. On a Simulator they stay at zero while "
                    + "isAvailable reads true — which is why nothing is claimed for the recording "
                    + "path. On a device the same button is the start of the real check: record, stop, "
                    + "then look at the video.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 5. App-switcher cover

    private var appSwitcherCard: some View {
        CapabilityCard(
            number: 5,
            title: "App-switcher snapshot",
            subtitle: "Covers the window while the scene is inactive.",
            reach: DemoEnvironment.reach(of: .appSwitcherCover),
            limitation: DemoEnvironment.limitation(of: .appSwitcherCover)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Install the cover on the key window", isOn: coverBinding)

                Picker("Style", selection: $settings.coverIsOpaque) {
                    Text("Opaque").tag(true)
                    Text("Blur").tag(false)
                }
                .pickerStyle(.segmented)

                if !settings.coverIsOpaque {
                    Text("A blur is not a redaction: the underlying pixels remain recoverable in "
                        + "principle. Opaque is the honest default.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Cover now") { cover?.coverNow() }
                        .buttonStyle(.bordered)
                        .disabled(cover == nil)
                    Button("Reveal") { cover?.uncoverNow() }
                        .buttonStyle(.bordered)
                        .disabled(cover == nil)
                }

                Text("On a device: background the app (Home) and open the app switcher. The window is "
                    + "covered while inactive, so the snapshot carries no app content. SwiftUI's own "
                    + "privacySensitive() is the system-supported alternative and is worth preferring "
                    + "where it suffices.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Installs or uninstalls the cover when the toggle changes.
    private var coverBinding: Binding<Bool> {
        Binding(
            get: { cover != nil },
            set: { wantsCover in
                if wantsCover {
                    guard let window = Self.keyWindow else { return }
                    let shield = ScreenGuardAppSwitcherShield(
                        style: settings.coverIsOpaque
                            ? .opaque(color: .systemBackground)
                            : .blur(style: .systemMaterial)
                    )
                    shield.install(on: window)
                    cover = shield
                } else {
                    cover?.uninstall()
                    cover = nil
                }
            }
        )
    }

    // MARK: - Status link

    private var statusLink: some View {
        Button { showingStatus = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Capability status table").font(.headline)
                Text("Every capability, its mechanism and its honest status — read from the package's "
                    + "own runtime registry (docs/api-contract.md §4).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building blocks

    /// The secret the demo protects. The sensitive colour fills it so a capture reading is unambiguous.
    private var secretCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DemoGeometry.secretTitle)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(DemoGeometry.secretDetail)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(uiColor: DemoGeometry.sensitiveColour))
        .cornerRadius(6)
    }

    private func readoutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption.monospaced())
            Spacer(minLength: 8)
            Text(value).font(.caption.monospaced()).foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    /// Takes the app-side read and classifies the regions the user is looking at.
    private func takeCapture() {
        guard let window = Self.keyWindow else { return }
        let candidates: [(label: String, frame: CGRect)] = [
            (label: DemoCapture.controlLabel, frame: controlFrame),
            (label: "Protected (\(settings.protectedStrategy.rawValue))", frame: protectedFrame),
            (label: "Watermark", frame: watermarkFrame),
        ]
        // Sample only what is actually on screen. A card below the fold was never laid out, so its
        // frame is empty — reporting it as UNREADABLE would read like a failure rather than a region
        // this capture simply does not contain.
        let onScreen = candidates.filter { !$0.frame.isEmpty && window.bounds.intersects($0.frame) }
        captureOmitted = candidates.count - onScreen.count
        captured = DemoCapture.capture(regions: onScreen)
    }

    /// The window the demo is running in.
    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

// MARK: - Detection body

/// The detection card's body, owning its own monitor.
///
/// Split out so the monitor can be rebuilt when a restart-only setting changes: `ScreenGuardMonitor`
/// takes its `ScreenGuardConfiguration` at construction, so a switch that changes detection must
/// produce a new monitor. The parent forces that with `.id(settings.detectionGeneration)`.
private struct DetectionCardBody: View {

    /// The monitor, built from the configuration the demo settings produced.
    @StateObject private var monitor: ScreenGuardMonitor

    /// The most recent event, rendered as a line.
    @State private var lastEvent = "none yet"

    /// The last synthetic injection, if any.
    @State private var syntheticNote = ""

    /// Builds the body with a monitor for `configuration`.
    ///
    /// - Parameter configuration: The configuration to build the monitor with.
    init(configuration: ScreenGuardConfiguration) {
        _monitor = StateObject(wrappedValue: ScreenGuardMonitor(configuration: configuration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            readout("monitoring", monitor.state.isMonitoring ? "ON" : "OFF")
            readout("captureState", monitor.state.captureState.rawValue)
            readout("detectionSource", monitor.state.detectionSource?.rawValue ?? "none")
            readout("lastScreenshotAt", Self.timestamp(monitor.state.lastScreenshotAt))
            readout("lastEvent", lastEvent)

            HStack(spacing: 10) {
                Button(monitor.state.isMonitoring ? "Stop" : "Start") {
                    if monitor.state.isMonitoring {
                        monitor.stop()
                    } else {
                        startMonitor()
                    }
                }
                .buttonStyle(.bordered)

                if DemoEnvironment.reach(of: .screenshotDetection) == .synthetic {
                    Button("Post a SYNTHETIC screenshot event") {
                        NotificationCenter.default.post(
                            name: UIApplication.userDidTakeScreenshotNotification,
                            object: nil
                        )
                        syntheticNote = "A synthetic notification was posted just now. It exercises "
                            + "the wiring; it is not a real screenshot."
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !syntheticNote.isEmpty {
                Text(syntheticNote)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Screenshot detection is post hoc: by the time the event arrives, the screenshot "
                + "already exists. On a device, press side + volume-up and watch lastScreenshotAt.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { startMonitor() }
        .onDisappear { monitor.stop() }
    }

    /// Starts the monitor and wires its event callback.
    private func startMonitor() {
        monitor.onEvent = { event in
            Task { @MainActor in
                lastEvent = Self.describe(event.kind)
            }
        }
        monitor.start()
    }

    /// Names an event kind. `ScreenGuardEvent.Kind` carries an associated value on one case, so it is
    /// not raw-representable and cannot be interpolated.
    ///
    /// - Parameter kind: The kind to describe.
    /// - Returns: A short label.
    private static func describe(_ kind: ScreenGuardEvent.Kind) -> String {
        switch kind {
        case .screenshotTaken: return "screenshotTaken"
        case .captureBegan: return "captureBegan"
        case .captureEnded: return "captureEnded"
        case .protectionDegraded(let reason): return "protectionDegraded(\(reason.rawValue))"
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption.monospaced())
            Spacer(minLength: 8)
            Text(value).font(.caption.monospaced()).foregroundColor(.secondary)
        }
    }

    /// Formats a date for display, or `"none"`.
    ///
    /// - Parameter date: The date, if any.
    /// - Returns: A short local time, or `"none"`.
    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "none" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Capture result sheet

/// Shows a capture full-screen so the user can inspect it closely.
struct CaptureResultSheet: View {

    /// The frame to show.
    let frame: DemoCapturedFrame

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Verdicts first. The first version of this sheet put a full-height image on top
                    // and pushed the answer below the fold — which is how a verification tool turns
                    // back into a picture viewer.
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(frame.readings) { reading in
                            HStack {
                                Text(reading.label).font(.footnote.monospaced())
                                Spacer(minLength: 8)
                                Text(reading.verdict.rawValue)
                                    .font(.footnote.bold().monospaced())
                                    .foregroundColor(
                                        reading.verdict.indicatesExclusion ? .green : .primary
                                    )
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(8)

                    Text("The control card is unshielded. If it carries its secret while the protected "
                        + "card does not, the read path works and the exclusion is real — that is the "
                        + "whole point of capturing both in one image.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("The image below is the app-side read. Look for the control card keeping its "
                        + "balance while the protected card does not.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(uiImage: frame.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary))
                        .cornerRadius(6)
                }
                .padding(16)
            }
            .navigationTitle("App-side capture")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
