//
//  DemoApp.swift
//  ScreenGuardDemo
//
//  The example app's entry point.
//
//  It runs in one of two shapes:
//
//    * **Interactive** (no `-ProbeMode`): the demo a human reads — four capability sections plus the
//      package's own capability-status table.
//    * **Probe** (`-ProbeMode noLeak|swiftUIPrivate|watermark|detection|capability|appSwitcher`): a
//      fixed page that writes machine-readable artifacts into the app's Documents directory for
//      `Scripts/verify_capture.sh` to collect with `simctl get_app_container`.
//
//  The probe shape exists so the verification is automated and repeatable rather than "a human looked
//  at it". It is also the only way to run the no-leak pixel check headlessly.
//

import SwiftUI
import UIKit
import ScreenGuard

@main
struct ScreenGuardDemoApp: App {

    init() {
        // The private-API opt-in is granted ONLY when the caller asked for it explicitly, and only
        // before any shield is built. Nothing else in the demo turns it on: the private path is a
        // private API, off by default, non-contract, and an App Review risk
        // (docs/api-contract.md §9).
        if DemoConfig.privateOptIn {
            ScreenGuard.PrivateAPI.isEnabled = true
        }
    }

    var body: some Scene {
        WindowGroup {
            DemoRoot()
        }
    }
}

/// Picks the interactive demo or a probe page.
struct DemoRoot: View {

    var body: some View {
        switch DemoConfig.probeMode {
        case .none:
            DemoRootView()

        case .noLeak:
            ProbeHost {
                DemoNoLeakProbeView(
                    runID: DemoConfig.runID,
                    privateOptIn: DemoConfig.privateOptIn
                )
            }

        case .swiftUIPrivate:
            ProbeHost {
                DemoSwiftUIPrivateProbeView(
                    runID: DemoConfig.runID,
                    privateOptIn: DemoConfig.privateOptIn
                )
            }

        case .watermark:
            ProbeHost {
                DemoWatermarkProbeView(runID: DemoConfig.runID)
            }

        case .detection:
            ProbeHost {
                DemoDetectionProbeView(runID: DemoConfig.runID)
            }

        case .appSwitcher:
            ProbeHost {
                DemoAppSwitcherProbeView(runID: DemoConfig.runID)
            }

        case .capability:
            ProbeHost {
                DemoCapabilityProbeView(runID: DemoConfig.runID)
            }
        }
    }
}

/// Hosts a probe `UIView` full-screen, with the status bar hidden so the probe page's normalised
/// rectangles map to the same fractions the host script samples.
struct ProbeHost: UIViewControllerRepresentable {

    /// Builds the probe view.
    let makeProbe: () -> UIView

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        let probe = makeProbe()
        probe.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(probe)
        NSLayoutConstraint.activate([
            probe.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            probe.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            probe.topAnchor.constraint(equalTo: controller.view.topAnchor),
            probe.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    /// Hide the status bar: it overlays the top region and would put the system clock inside a
    /// sampled rectangle.
    static var statusBarHidden: Bool { true }
}
