// ReviewPromptBanner.swift — optional strip below the update banner (same visibility) asking for a GitHub review.

import SwiftUI
import AppKit

struct ReviewPromptBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Button(String(localized: "Loving Binky? Leave a review", comment: "Review prompt banner: link to GitHub Discussions reviews.")) {
                NSWorkspace.shared.open(URL(string: "https://github.com/heyderekj/binky/discussions/new?category=reviews")!)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .underline()
            .multilineTextAlignment(.leading)

            Spacer(minLength: 16)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss", comment: "Tooltip for dismiss review prompt banner."))
            .accessibilityLabel(String(localized: "Dismiss review prompt", comment: "VoiceOver label for the review prompt banner xmark button."))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
}
