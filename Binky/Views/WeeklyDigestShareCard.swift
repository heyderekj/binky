import SwiftUI

/// Fixed aspect share card (~2:1) for Reddit / screenshots.
struct WeeklyDigestShareCard: View {
    let model: WeeklyDigestShareModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(1),
                    Color(nsColor: .controlBackgroundColor).opacity(1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(binkyTintColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            String.localizedStringWithFormat(
                                String(
                                    localized: "%lld files sorted this week",
                                    comment: "Weekly digest share card headline; count of file rows touched."
                                ),
                                Int64(model.filesProcessed)
                            )
                        )
                        .font(.system(size: 28, weight: .bold))
                        Text(
                            String(
                                localized: "Your rules. Your Mac. No guessing.",
                                comment: "Weekly digest tagline."
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 22) {
                    statPill(value: model.movesCount, label: String(localized: "Moved", comment: "Weekly digest stat."))
                    statPill(value: model.sessionCount, label: String(localized: "Runs", comment: "Weekly digest stat."))
                    Spacer(minLength: 0)
                }

                if !model.topCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Top destinations", comment: "Weekly digest section."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            ForEach(Array(model.topCategories.prefix(3).enumerated()), id: \.offset) { _, pair in
                                let category = pair.0
                                let count = pair.1
                                HStack(spacing: 6) {
                                    Image(systemName: Self.symbol(for: category))
                                        .foregroundStyle(binkyTintColor)
                                    Text(category.rawValue.capitalized)
                                        .font(.caption.weight(.medium))
                                    Text("\(count)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.primary.opacity(0.05)))
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 600, minHeight: 200, idealHeight: 300, alignment: .topLeading)

            Text("Binky — binkyfiles.com")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func statPill(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private static func symbol(for category: FileSortCategory) -> String {
        switch category {
        case .images, .screenshots: return "photo"
        case .pdf, .documents: return "doc"
        case .video: return "film"
        case .audio: return "music.note.list"
        case .archives: return "shippingbox"
        case .apps: return "applelogo"
        case .misc: return "ellipsis.circle"
        case .review: return "eyes"
        case .duplicates: return "square.on.square"
        case .receipts: return "creditcard"
        case .folders: return "folder"
        }
    }
}

/// Toolbar actions wrapping the share card.
struct WeeklyDigestActionsSheet: View {
    let model: WeeklyDigestShareModel
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "This week’s digest", comment: "Weekly digest sheet title."))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Done", comment: "Dismiss digest sheet.")) { dismiss() }
            }
            .padding()
            Divider()
            ScrollView {
                WeeklyDigestShareCard(model: model)
                    .shadow(color: .black.opacity(0.12), radius: 22, y: 10)
                    .padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                Button(didCopy ? String(localized: "Copied PNG", comment: "Digest copy feedback.") : String(localized: "Copy PNG", comment: "Copy digest image.")) {
                    if WeeklyDigestExporter.copyPNG(of: model) {
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            didCopy = false
                        }
                    }
                }
                .keyboardShortcut("c", modifiers: [.command])
                Button(String(localized: "Save PNG…", comment: "Save digest image panel.")) {
                    WeeklyDigestExporter.presentSavePNGPanel(for: model)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(minWidth: 640, idealWidth: 660, maxWidth: .infinity)
        .frame(minHeight: 520)
        .background(.ultraThinMaterial)
    }
}
