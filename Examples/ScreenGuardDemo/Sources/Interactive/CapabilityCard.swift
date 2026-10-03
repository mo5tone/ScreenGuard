//
//  CapabilityCard.swift
//  ScreenGuardDemo
//
//  The demo's card chrome, and the two rules that make it honest.
//
//  RULE 1 — the limitation goes ABOVE the thing it qualifies.
//  The first version put "this proves nothing here" in `caption2` grey underneath a black rectangle.
//  Nobody reads that far. So when a capability cannot be verified in the current environment, the
//  reason appears in a bordered box at the TOP of the card, before any visual the user might
//  misread, and the region itself is not drawn at all.
//
//  RULE 2 — the card says how far the user can get, in the card, not in a caption.
//  Every card carries a reach badge, and it is derived from `DemoEnvironment`, so it cannot drift
//  away from the reason text next to it.
//

import SwiftUI

/// A card for one capability: what it is, how far you can get here, and what you can do about it.
struct CapabilityCard<Content: View>: View {
    /// The section number shown in the badge.
    let number: Int

    /// The capability's name.
    let title: String

    /// One line on what the capability does.
    let subtitle: String

    /// How far a user can get here.
    let reach: DemoEnvironment.Reach

    /// Why the user cannot get all the way, when that is the case. Shown at the top.
    let limitation: String

    /// The card's body: controls, actions and results.
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !limitation.isEmpty, reach != .verifiable {
                limitationBox
            }
            content()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.10))
        .cornerRadius(12)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .clipShape(Circle())
                Text(title).font(.headline)
                Spacer(minLength: 8)
                reachBadge
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var reachBadge: some View {
        Text(reach.badgeText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(reach.badgeColour)
            .cornerRadius(6)
    }

    private var limitationBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: reach == .synthetic ? "exclamationmark.triangle.fill" : "iphone.slash")
                .foregroundColor(reach.badgeColour)
            Text(limitation)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(reach.badgeColour.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(reach.badgeColour.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

extension DemoEnvironment.Reach {
    /// The badge's short label.
    var badgeText: String {
        switch self {
        case .verifiable:
            "VERIFY HERE"
        case .synthetic:
            "SYNTHETIC"
        case .deviceRequired:
            "NEEDS DEVICE"
        }
    }

    /// The badge's colour.
    var badgeColour: Color {
        switch self {
        case .verifiable:
            .green
        case .synthetic:
            .orange
        case .deviceRequired:
            .gray
        }
    }
}

extension View {
    /// Reports this view's frame in global (window) coordinates whenever it changes.
    ///
    /// Used to tell `DemoCapture` where the cards ended up, so it can sample exactly those rectangles
    /// out of the app-side read. Global coordinates in a full-screen window are window coordinates,
    /// which is the space `AppSideReadback.appRender` renders in.
    ///
    /// - Parameter handler: Called with the frame on appear and on every change.
    /// - Returns: A view that draws nothing and reports its position.
    func reportFrame(_ handler: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { handler(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { newValue in handler(newValue) }
            }
        )
    }
}
