//
//  DemoRootView.swift
//  ScreenGuardDemo
//
//  The interactive demo. Four capability sections, plus the package's own capability-status page.
//
//  TWO BINDING RULES THIS FILE FOLLOWS
//  ----------------------------------
//  1. **Never claim prevention.** `docs/api-contract.md` §0.2 forbids the words "prevents", "blocks",
//     "disables" or "stops" applied to the user's screenshot or recording action. The copy below says
//     what the package does (detect, and keep content out of captures) and what iOS does not permit
//     (blocking the action).
//  2. **Never interpolate a non-`String` into `Text`.** `ScreenGuardCaptureState`,
//     `ScreenGuardDetectionSource` and `ScreenGuardProtectionFailure` are String-raw-valued and do
//     not conform to `CustomStringConvertible`; `Text("\(state)")` is a deprecation **error** at an
//     iOS 15 deployment target (`docs/api-contract.md` §6.9). Every one of them is rendered through
//     `.rawValue` here.
//

import SwiftUI
import ScreenGuard

/// The interactive demo screen.
struct DemoRootView: View {

    /// The shared monitor, started when the view appears.
    @StateObject private var monitor = ScreenGuardMonitor()

    /// The most recent event, rendered as the live detection line.
    @State private var lastEvent: String = "none yet"

    /// Whether the private-API opt-in is granted. Off by default, and it stays off until the user
    /// flips this switch — which is the interactive equivalent of `-PrivateOptIn 1`.
    @State private var privateOptIn = DemoConfig.privateOptIn

    /// The public shield's real state, so the demo reports what the shield *is doing* rather than
    /// what it was asked to do.
    @State private var publicShieldState = DemoShieldSummary()

    /// The private shield's real state.
    @State private var privateShieldState = DemoShieldSummary()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    honestyBanner
                    detectionSection
                    noLeakSection
                    watermarkSection
                    appSwitcherSection
                    capabilityLink
                }
                .padding(16)
            }
            .navigationTitle("ScreenGuard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: DemoCapabilityScreen().ignoresSafeArea()) {
                        Text("Status")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { startMonitor() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - 0. Honesty banner

    private var honestyBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this does, and what it does not")
                .font(.headline)
            // Deliberately worded. See the file header.
            Text(
                "ScreenGuard detects captures and keeps sensitive content out of them. "
                    + "A protected region coming out black in a capture is the success case. "
                    + "iOS does not allow an app to prevent a screenshot or a recording, and this "
                    + "demo does not either."
            )
            .font(.footnote)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.red.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    // MARK: - 1 & 2. Detection

    private var detectionSection: some View {
        section(
            number: 1,
            title: "Detection",
            subtitle: "Live capture state, observed — never blocked."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // `.rawValue`, never bare interpolation. See the file header.
                stateRow("monitoring", monitor.state.isMonitoring ? "ON" : "OFF")
                stateRow("captureState", monitor.state.captureState.rawValue)
                stateRow("detectionSource", monitor.state.detectionSource?.rawValue ?? "none")
                stateRow("lastScreenshotAt", Self.timestamp(monitor.state.lastScreenshotAt))
                stateRow("lastEvent", lastEvent)

                Text(
                    "Screenshot detection is post hoc: by the time the event arrives, the screenshot "
                        + "already exists. The Simulator cannot fire a real screenshot notification "
                        + "(it needs the side and volume buttons together), so end-to-end screenshot "
                        + "detection is device-pending."
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                Button("Start / restart monitor") { startMonitor() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 3. No-leak shield

    private var noLeakSection: some View {
        section(
            number: 2,
            title: "No-leak shield",
            subtitle: "Protected content must not appear in a capture. Black is the success case."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("The card below carries a secret. It sits on a magenta sentinel, so a blank region "
                    + "is distinguishable from a region that never painted.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // The actionable version of the success bar. Without this the demo shows the
                // mechanism but never tells a reader how to make the outcome observable, which is
                // the whole point of an example.
                Text("HOW TO SEE THE NO-LEAK OUTCOME: turn on the opt-in private path below, then "
                    + "take a screenshot (side + volume-up) or start a screen recording on a device. "
                    + "Protected content comes out blank in the capture while staying visible on the "
                    + "screen. A black region is the success case, not a bug.")
                    .font(.caption)
                    .foregroundColor(.primary)

                // The sentinel behind the protected region, and the reason a blank reading is
                // interpretable at all (docs/TOOLING.md §3).
                DemoShieldRepresentable(
                    strategy: .publicPreventsCaptureLayer,
                    onStateChange: { shield in
                        publicShieldState = DemoShieldSummary(shield: shield)
                    },
                    content: { AnyView(secretCard) }
                )
                .frame(height: 120)
                .background(Color(red: 200 / 255, green: 0, blue: 160 / 255))

                shieldStateRow("public path", publicShieldState)

                Text(
                    "The public path is AVSampleBufferDisplayLayer.preventsCapture over an opaque "
                        + "black shield. On Simulator this layer paints NOTHING AT ALL — on screen "
                        + "included — so its capture behaviour is unverified and needs a device. "
                        + "A black region here is expected and is NOT proof of protection."
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                Divider()

                Toggle("Enable the opt-in private path", isOn: $privateOptIn)
                    .onChange(of: privateOptIn) { newValue in
                        ScreenGuard.PrivateAPI.isEnabled = newValue
                    }

                Text(
                    "PRIVATE API — off by default. Non-contract, may stop working in any iOS "
                        + "release, App Review risk, and never a security guarantee. Read "
                        + "docs/api-contract.md §9 before enabling it. It is the only mechanism "
                        + "measured to blank arbitrary content in the app-side render path while "
                        + "still painting on the display."
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                DemoShieldRepresentable(
                    strategy: privateOptIn ? .privateSecureLayer : .disabled,
                    onStateChange: { shield in
                        privateShieldState = DemoShieldSummary(shield: shield)
                    },
                    content: { AnyView(secretCard) }
                )
                .frame(height: 120)
                .background(Color(red: 200 / 255, green: 0, blue: 160 / 255))

                shieldStateRow("private path", privateShieldState)

                Text("Private path available in this build: "
                    + (ScreenGuard.PrivateAPI.isCompiledIn ? "yes" : "no (file excluded)"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 4. Watermark

    private var watermarkSection: some View {
        section(
            number: 3,
            title: "Forensic watermark",
            subtitle: "Deterrent and attribution only. It removes no pixels."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                secretCard
                    .frame(height: 110)
                    // The package's own SwiftUI modifier — the ergonomic path a consumer would use.
                    .screenGuardWatermarked(
                        ScreenGuardWatermarkConfiguration(
                            text: "CONFIDENTIAL",
                            secondaryText: "demo session 4417",
                            opacity: 0.28
                        )
                    )
                    .cornerRadius(8)

                Text(
                    "A watermark makes a leaked image attributable to a session or a time. It is "
                        + "NOT a no-leak control: it removes no pixels from any capture and stops "
                        + "nothing. It does not survive cropping, blurring or downscaling."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 5. App-switcher cover

    private var appSwitcherSection: some View {
        section(
            number: 4,
            title: "App-switcher snapshot protection",
            subtitle: "Covers the window while the scene is inactive."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Background the app (Home) and reopen it. The window is covered while it is "
                        + "inactive, so the system's app-switcher snapshot does not contain app "
                        + "content. SwiftUI's own privacySensitive() is the system-supported, "
                        + "zero-configuration alternative and is worth preferring where it suffices."
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Text(
                    "DEVICE-PENDING: the snapshot's pixels land in a proprietary KTX variant that "
                        + "neither ImageMagick nor ffmpeg can decode, so the cover can be shown to "
                        + "install and engage on Simulator, but its effect on the snapshot can only "
                        + "be confirmed on a device."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Capability status link

    private var capabilityLink: some View {
        NavigationLink(destination: DemoCapabilityScreen().ignoresSafeArea()) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Capability status table").font(.headline)
                Text("Every capability, its mechanism and its honest status — read from the package's "
                    + "own runtime registry (docs/api-contract.md §4).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Building blocks

    /// The secret the demo protects.
    private var secretCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DemoGeometry.secretTitle)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            Text(DemoGeometry.secretDetail)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(red: 38 / 255, green: 102 / 255, blue: 242 / 255))
    }

    private func section<Content: View>(
        number: Int,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            content()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    private func stateRow(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func shieldStateRow(_ name: String, _ summary: DemoShieldSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            stateRow("\(name) isProtecting", summary.isProtecting ? "TRUE" : "FALSE")
            stateRow("\(name) shieldMode", summary.shieldMode)
            stateRow("\(name) failure", summary.failure)
        }
    }

    // MARK: - Actions

    private func startMonitor() {
        monitor.onEvent = { event in
            lastEvent = Self.describe(event.kind)
        }
        monitor.start()
        lastEvent = "monitoring started"
    }

    private static func describe(_ kind: ScreenGuardEvent.Kind) -> String {
        switch kind {
        case .screenshotTaken:                return "screenshotTaken"
        case .captureBegan:                   return "captureBegan"
        case .captureEnded:                   return "captureEnded"
        case .protectionDegraded(let reason): return "protectionDegraded(\(reason.rawValue))"
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "none" }
        return formatter.string(from: date)
    }
}

/// A render-friendly snapshot of a shield's real state.
///
/// Built from `ScreenGuardShieldView` but stored as plain `String`/`Bool`, so SwiftUI can render it
/// without interpolating a non-`String` enum (`docs/api-contract.md` §6.9).
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
