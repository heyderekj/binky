import SwiftUI

/// Per-file shim during sort — work is brief, so soft pulse instead of bogus determinate fills.
private struct PulsePinkRowBar: View {
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 35.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let ping = CGFloat(0.52 + sin(t * 5.8) * 0.42)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(binkyTintColor.opacity(0.15 + ping * 0.28))
                    .frame(height: height)
                    .drawingGroup(opaque: false)
            }
            .frame(height: height)
        }
    }
}

/// Sheet listing the file currently moving through routing (and live batch bar).
struct CurrentlySortingSheet: View {
    @ObservedObject private var progress = SortProgressTracker.shared
    @Environment(\.dismiss) private var dismiss
    private let orchestrator = DownloadsSortOrchestrator.shared

    @ViewBuilder
    private var subtitle: some View {
        if progress.bannerCaption.isEmpty {
            Text(String(localized: "Binky's tidying up.", comment: "Currently sorting sheet: generic subtitle when no per-file caption."))
                .foregroundStyle(.secondary)
        } else {
            Text(progress.bannerCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Currently sorting", comment: "Sheet title for live sort summary."))
                        .font(.title2.weight(.semibold))
                    subtitle
                        .font(.callout)
                }
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close", comment: "Dismiss sorting sheet button."))
            }

            VStack(alignment: .leading, spacing: 6) {
                BinkySortProgressBar(
                    fraction: progress.fraction,
                    caption: nil,
                    compact: false,
                    showsCaption: false
                )

                if progress.isActive {
                    HStack(spacing: 8) {
                        Button {
                            if progress.runState == .paused {
                                orchestrator.resumeCurrentSort()
                            } else {
                                orchestrator.pauseCurrentSort()
                            }
                        } label: {
                            Label(
                                progress.runState == .paused
                                    ? String(localized: "Resume", comment: "Resume active sort action.")
                                    : String(localized: "Pause", comment: "Pause active sort action."),
                                systemImage: progress.runState == .paused ? "play.fill" : "pause.fill"
                            )
                        }
                        .glassButton()
                        .controlSize(.small)
                        .disabled(progress.runState == .stopping)

                        Button(role: .destructive) {
                            orchestrator.stopCurrentSort()
                        } label: {
                            Label(
                                String(localized: "Stop", comment: "Stop active sort action."),
                                systemImage: "stop.fill"
                            )
                        }
                        .glassButton()
                        .controlSize(.small)
                        .disabled(progress.runState == .stopping)

                        Spacer(minLength: 0)
                    }
                }

                Divider()
                    .opacity(0.35)
                Text(String(localized: "Working on", comment: "Header above active file rows while sorting."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                if progress.currentItems.isEmpty {
                    if progress.isActive {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "Next file starting…", comment: "Brief gap between per-file phases."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        PulsePinkRowBar(height: 8)
                            .opacity(0.85)
                    } else {
                        Text(String(localized: "No active sorting.", comment: "Sheet fallback when sorting already finished."))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(progress.currentItems) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    PulsePinkRowBar(height: 6)
                                        .accessibilityLabel(String(localized: "Active file progress", comment: "VoiceOver: indeterminate bar for one file."))
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.primary.opacity(0.045))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }

            Spacer(minLength: 0)

            Text(String(localized: "You can dismiss this sheet — sorting continues in the background.", comment: "Footer hint."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 560, maxHeight: 520)
    }
}
