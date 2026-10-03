import SwiftUI
import UIKit

@main
struct CaptureMatrixApp: App {
    var body: some Scene {
        WindowGroup {
            root
                .statusBarHidden(true)
        }
    }

    @ViewBuilder
    private var root: some View {
        switch Config.mode {
        case .renderSanity:
            RenderSanityView()
        case .replayKit:
            ReplayKitProbeView()
        case .feasibility:
            FeasibilityView()
        default:
            LabRootView(mode: Config.mode)
        }
    }
}
