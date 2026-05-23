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
///
/// The timeline drives a 30 fps redraw loop. We pause it when the modified view is off-screen so
/// hidden / occluded spinners don't burn cycles in the background.
private struct LegacySymbolRotationModifier: ViewModifier {
    @State private var isVisible: Bool = false

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isVisible)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let degrees = (t * 400).truncatingRemainder(dividingBy: 360)
            content.rotationEffect(.degrees(degrees))
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
