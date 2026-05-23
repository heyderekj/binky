import SwiftUI

/// Dry-run list of where watched files would land — nothing is moved.
struct SortPreviewSheet: View {
    let rows: [SortPreviewEntry]
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Preview sort", comment: "Sort preview sheet title."))
                .font(.title2)

            Text(String(localized: "Nothing is moved yet. Incomplete downloads are treated as skipped.", comment: "Sort preview disclaimer."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rows.isEmpty {
                // Empty state: an empty table with no explanation made it look like the preview
                // was broken. A plain-language message confirms there's simply nothing to sort.
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Nothing to sort.", comment: "Sort preview empty-state title."))
                        .font(.headline)
                    Text(String(localized: "Every file currently in the watched folder either matched a skip rule or is mid-download.", comment: "Sort preview empty-state subtitle."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                Table(rows) {
                    TableColumn(String(localized: "File", comment: "Sort preview table.")) { row in
                        Text(row.sourceLastPathComponent)
                            .lineLimit(1)
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn(String(localized: "Would move to", comment: "Sort preview table.")) { row in
                        Text(row.proposedDestinationPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn(String(localized: "Why", comment: "Sort preview table: plain-language reason.")) { row in
                        Text(row.whyLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 160, ideal: 220)

                    TableColumn(String(localized: "Summary", comment: "Sort preview table.")) { row in
                        Text(row.summary)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .frame(minHeight: 220)
            }

            HStack {
                Button(role: .cancel) {
                    onDismiss()
                    dismiss()
                } label: {
                    Text(String(localized: "Close", comment: "Dismiss preview sheet."))
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(22)
        .frame(minWidth: 720, minHeight: 360)
    }
}
