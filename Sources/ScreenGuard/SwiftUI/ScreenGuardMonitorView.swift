//
//  ScreenGuardMonitorView.swift
//  ScreenGuard
//
//  Reads the shared (or supplied) monitor and rebuilds when its state changes.
//  See docs/api-contract.md §6.8.
//

import SwiftUI

/// Reads the shared (or supplied) monitor and rebuilds when its state changes.
///
/// ```swift
/// ScreenGuardMonitorView { state in
///     // NOTE: display String-raw-valued types through `.rawValue`, never by bare interpolation —
///     // see the display trap in ScreenGuardModifiers.swift.
///     Text("Capture: \(state.captureState.rawValue)")
/// }
/// ```
///
/// **Design note.** The `monitor` parameter is optional rather than defaulted to `ScreenGuard.shared`
/// deliberately: a default argument referencing a `@MainActor` global is not usable from a nonisolated
/// initializer. Resolving it inside `body` (which is main-actor isolated) keeps the call site clean.
///
/// iOS 15-compatible — no availability guard is required.
public struct ScreenGuardMonitorView<Content: View>: View {
    /// The monitor to read, or `nil` to use `ScreenGuard.shared`.
    private let monitor: ScreenGuardMonitor?

    /// Builds the body from the monitor's current state.
    private let content: (ScreenGuardState) -> Content

    /// Creates a monitor view.
    ///
    /// - Parameters:
    ///   - monitor: The monitor to observe. Pass `nil` (the default) to use `ScreenGuard.shared`.
    ///   - content: Builds the view from the monitor's current state.
    public init(
        monitor: ScreenGuardMonitor? = nil,
        @ViewBuilder content: @escaping (ScreenGuardState) -> Content
    ) {
        self.monitor = monitor
        self.content = content
    }

    /// The view's body.
    public var body: some View {
        ScreenGuardMonitorObserver(
            monitor: monitor ?? ScreenGuard.shared,
            content: content
        )
    }
}

/// The observing half, split out so `@ObservedObject` has a stable identity to attach to.
private struct ScreenGuardMonitorObserver<Content: View>: View {
    @ObservedObject var monitor: ScreenGuardMonitor
    let content: (ScreenGuardState) -> Content

    var body: some View {
        content(monitor.state)
    }
}
