//
//  DemoShieldRepresentable.swift
//  ScreenGuardDemo
//
//  Bridges `DemoShieldContainer` into SwiftUI.
//
//  The SwiftUI modifier `.screenGuardProtected(...)` from the package is the ergonomic entry point.
//  This representable exists for the one case the modifier cannot cover: the private path has to be
//  engaged *after* the view joins a window, and in a specific order (`docs/api-contract.md` §9.2 and
//  `DemoShieldContainer`'s header). Using it here keeps the package untouched and keeps the ordering
//  honest.
//
//  WHY `optInGeneration` EXISTS
//  ----------------------------
//  A shield evaluates the private-API opt-in when it engages, and does not re-evaluate it on its own.
//  So a user who selects the private strategy *first* and turns the opt-in on *second* keeps looking
//  at the failed state — the switch appears to do nothing, which is exactly the sort of dead control
//  a demo must not have. Carrying the opt-in's generation here makes the change re-apply the
//  strategy, without the package needing to poll a global.
//

import ScreenGuard
import SwiftUI
import UIKit

/// Hosts a `DemoShieldContainer` around arbitrary SwiftUI content.
struct DemoShieldRepresentable: UIViewRepresentable {
    /// The strategy to request.
    let strategy: ScreenGuardNoLeakStrategy

    /// Bumped whenever the private-API opt-in changes, so the strategy is re-applied.
    let optInGeneration: Int

    /// Called with the shield after every state synchronisation.
    let onStateChange: (ScreenGuardShieldView) -> Void

    /// The content to protect.
    let content: () -> AnyView

    /// Makes the container and records which generation it has already applied.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: A container hosting the content.
    func makeUIView(context: Context) -> DemoShieldContainer {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        let container = DemoShieldContainer(
            strategy: strategy,
            content: host.view
        )
        container.retainedHost = host
        container.onStateChange = onStateChange
        context.coordinator.appliedGeneration = optInGeneration
        return container
    }

    /// Re-applies the strategy when it changed, or when the opt-in did.
    ///
    /// Two triggers, because either one changes what the shield should be doing — and a control that
    /// changes nothing is worse than no control.
    ///
    /// - Parameters:
    ///   - uiView: The container.
    ///   - context: The representable's context.
    func updateUIView(_ uiView: DemoShieldContainer, context: Context) {
        let strategyChanged = uiView.requestedStrategy != strategy
        let optInChanged = context.coordinator.appliedGeneration != optInGeneration
        guard strategyChanged || optInChanged else {
            return
        }
        context.coordinator.appliedGeneration = optInGeneration
        uiView.request(strategy)
    }

    /// Holds the generation the container has already applied.
    ///
    /// - Returns: A fresh coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Per-representable bookkeeping.
    final class Coordinator {
        /// The `optInGeneration` the container was last asked to apply.
        var appliedGeneration = Int.min
    }
}
