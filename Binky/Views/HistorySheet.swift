import SwiftUI
import AppKit

struct HistorySheet: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @Environment(\.dismiss) private var dismiss
    /// When set, rows with stored batch summary data show “Open Summary…”.
    var onOpenSessionSummary: ((SessionRecord) -> Void)?

    @State private var weeklyDigestPresentation: WeeklyDigestShareModel?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if prefs.sessionHistory.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .background(.ultraThinMaterial)
        .sheet(item: $weeklyDigestPresentation) { model in
            WeeklyDigestActionsSheet(model: model)
        }
    }

    private var header: some View {
        HStack {
            Text(String(localized: "History", comment: "History window title."))
                .font(.headline)
            Spacer()
            if WeeklyDigestShareModel.build(from: prefs.sessionHistory) != nil {
                Button(String(localized: "This week’s digest card…", comment: "History sheet: weekly digest opener.")) {
                    weeklyDigestPresentation = WeeklyDigestShareModel.build(from: prefs.sessionHistory)
                }
                .font(.caption)
                .foregroundStyle(binkyTintColor)
                .buttonStyle(.plain)
            }
            if !prefs.sessionHistory.isEmpty {
                Button(String(localized: "Clear", comment: "Clear session history list.")) {
                    prefs.sessionHistory = []
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            Button(String(localized: "Done", comment: "Dismiss sheet.")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(String(localized: "No sessions yet.", comment: "History empty state."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        List(prefs.sessionHistory) { record in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(dateFormatter.string(from: record.timestamp))
                            .font(.caption.weight(.medium))
                        if let routineNameChip = routineName(for: record) {
                            HStack(spacing: 3) {
                                Image(systemName: "repeat.circle")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(routineNameChip)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(binkyTintColor.opacity(0.12))
                            )
                            .foregroundStyle(binkyTintColor)
                            .accessibilityLabel(String(localized: "Routine: \(routineNameChip)", comment: "VoiceOver: history row chip naming the routine."))
                        }
                    }
                    Text(record.formats.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let statsLine = Self.sessionVoiceStatsLine(for: record), !statsLine.isEmpty {
                        Text(statsLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let originLine = Self.originHostsSummary(for: record), !originLine.isEmpty {
                        Text(originLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let onOpenSessionSummary, record.batchSummaryData != nil {
                        Button(String(localized: "Open Summary…", comment: "History row: reopen stored batch completion dialog.")) {
                            onOpenSessionSummary(record)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(binkyTintColor)
                        .help(String(localized: "Show the move/review summary from this run.", comment: "History Open Summary tooltip."))
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(historySessionFileCountLabel(record.fileCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isSortSessionRecord(record), record.totalBytesMoved > 0 {
                        Text(formattedSize(record.totalBytesMoved) + String(localized: " moved", comment: "Suffix after size in history row."))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowSeparatorTint(.primary.opacity(0.08))
            .contextMenu {
                let urls = sessionCompressibleURLs(record)
                if DinkyBridge.isInstalled, !urls.isEmpty {
                    Button(String(localized: "Send session files to Dinky", comment: "History context menu.")) {
                        _ = DinkyBridge.openFiles(urls)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func routineName(for record: SessionRecord) -> String? {
        guard let data = record.batchSummaryData,
              let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) else { return nil }
        return outcome.matchedRoutine(in: prefs.savedPresets)?.name
    }

    private func sessionCompressibleURLs(_ record: SessionRecord) -> [URL] {
        guard let data = record.batchSummaryData,
              let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) else { return [] }
        let moved = outcome.entries.compactMap { e -> URL? in
            guard e.disposition == .moved, let d = e.destinationPath else { return nil }
            return URL(fileURLWithPath: d)
        }
        return DinkyBridge.compressibleURLs(from: moved)
    }

    private func isSortSessionRecord(_ record: SessionRecord) -> Bool {
        guard let data = record.batchSummaryData else { return false }
        return (try? JSONDecoder().decode(SortBatchOutcome.self, from: data)) != nil
    }

    private func historySessionFileCountLabel(_ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("history_session_file_count", bundle: .main, comment: "History row; plural by file count."),
            count
        )
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.1f MB", mb)
    }

    private static func sessionVoiceStatsLine(for record: SessionRecord) -> String? {
        guard let data = record.batchSummaryData,
              let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) else { return nil }
        return outcome.voiceSessionStatsLine
    }

    /// Comma-separated download sources from stored sort batch, when present.
    private static func originHostsSummary(for record: SessionRecord) -> String? {
        guard let data = record.batchSummaryData,
              let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) else { return nil }
        let hosts = outcome.entries
            .compactMap(\.originHost)
            .filter { !$0.isEmpty }
        guard !hosts.isEmpty else { return nil }
        let unique = Array(Set(hosts)).sorted()
        let preview = unique.prefix(4)
        let suffix = unique.count > 4 ? "…" : ""
        return String(localized: "From: ", comment: "History row: where-from prefix.")
            + preview.joined(separator: ", ")
            + suffix
    }
}
