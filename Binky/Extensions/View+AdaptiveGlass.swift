// View+AdaptiveGlass.swift
// Applies the macOS 26 liquid glass effect where supported, falls back to
// .ultraThinMaterial on macOS 14–25 so the app runs on Sonoma and later.

import SwiftUI

extension View {
    /// Applies `.glassEffect(in:)` on macOS 26+; falls back to
    /// `.background(.ultraThinMaterial, in:)` on earlier releases.
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Count badge for a toolbar button. On macOS 26+ the toolbar draws it inside the
    /// item's glass (a hand-placed overlay gets clipped by the glass shape there); on
    /// earlier releases a small capsule sits inside the button's top-trailing corner.
    @ViewBuilder
    func adaptiveToolbarBadge(_ count: Int, tint: Color) -> some View {
        if #available(macOS 26, *) {
            self.badge(count)
        } else {
            self.overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(tint))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Forces the toolbar background visible. Uses the modern API on macOS 15+,
    /// falls back to `.toolbarBackground(.visible, for: .windowToolbar)` on macOS 14.
    @ViewBuilder
    func adaptiveVisibleWindowToolbarBackground() -> some View {
        if #available(macOS 15, *) {
            self.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            self.toolbarBackground(.visible, for: .windowToolbar)
        }
    }

    /// Repeating rotate for SF Symbols (`SymbolEffect.rotate` is macOS 15+).
    @ViewBuilder
    func symbolRotationRepeatingEffect() -> some View {
        if #available(macOS 15, *) {
            self.symbolEffect(.rotate, options: .repeating)
        } else {
            self.modifier(LegacySymbolRotationModifier())
        }
    }

    /// Keeps action labels readable on liquid glass while preserving normal tint
    /// behavior on older material backdrops.
    @ViewBuilder
    func adaptiveGlassActionForeground() -> some View {
        if #available(macOS 26, *) {
            self.foregroundStyle(.white)
        } else {
            self.foregroundStyle(.primary)
        }
    }
}

/// Spin for Sonoma: `TimelineView` + `rotationEffect` (no `SymbolEffect.rotate`).
private struct LegacySymbolRotationModifier: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let degrees = (t * 400).truncatingRemainder(dividingBy: 360)
            content.rotationEffect(.degrees(degrees))
        }
    }
}
