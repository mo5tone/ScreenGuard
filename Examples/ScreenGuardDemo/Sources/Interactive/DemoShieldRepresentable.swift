//
//  DemoShieldRepresentable.swift
//  ScreenGuardDemo
//
//  Bridges `DemoShieldContainer` into SwiftUI.
//
//  The SwiftUI modifier `.screenGuardProtected(...)` from the package is the ergonomic entry point
//  and the demo shows it too. This representable exists for the one case the modifier cannot cover:
//  the private path has to be engaged *after* the view joins a window, in a specific order
//  (`docs/api-contract.md` §9.2 and `DemoShieldContainer`'s header). Using it here keeps the package
//  untouched and keeps the ordering honest.
//

import SwiftUI
import UIKit
import ScreenGuard

/// Hosts a `DemoShieldContainer` around arbitrary SwiftUI content.
struct DemoShieldRepresentable: UIViewRepresentable {

    /// The strategy to request.
    let strategy: ScreenGuardNoLeakStrategy

    /// Called with the shield after every state synchronisation.
    let onStateChange: (ScreenGuardShieldView) -> Void

    /// The content to protect.
    let content: () -> AnyView

    func makeUIView(context: Context) -> DemoShieldContainer {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        let container = DemoShieldContainer(
            strategy: strategy,
            content: host.view
        )
        container.retainedHost = host
        container.onStateChange = onStateChange
        return container
    }

    func updateUIView(_ uiView: DemoShieldContainer, context: Context) {
        if uiView.requestedStrategy != strategy {
            uiView.request(strategy)
        }
    }
}
