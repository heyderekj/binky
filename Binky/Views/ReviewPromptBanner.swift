// ReviewPromptBanner.swift — a quiet line under the update card (same visibility) asking for a GitHub review.

import SwiftUI
import AppKit

struct ReviewPromptBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.circle.fill")
                .symbolRenderingMode(.hierarchical)
            Button(String(localized: "Loving Binky? Leave a review", comment: "Review prompt banner: link to GitHub Discussions reviews.")) {
                NSWorkspace.shared.open(URL(string: "https://github.com/heyderekj/binky/discussions/new?category=reviews")!)
            }
            .buttonStyle(.plain)
            .underline()
            .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss", comment: "Tooltip for dismiss review prompt banner."))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}
