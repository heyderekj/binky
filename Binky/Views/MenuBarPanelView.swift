import SwiftUI

/// State for the macOS 27 menu bar panel; ``BinkyMenuBarController`` reloads it on open and on change.
@MainActor
final class MenuBarPanelModel: ObservableObject {
    struct Routine: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    @Published var watchingPaused = false
    @Published var reviewCount = 0
    @Published var lastSort: SortSessionHistoryRecord?
    @Published var routines: [Routine] = []
}

/// What the panel's buttons do. The controller fills these with the same handlers as the classic menu.
struct MenuBarPanelActions {
    var sortAll: () -> Void
    var sortRoutine: (UUID) -> Void
    var togglePauseSorting: () -> Void
    var stopSorting: () -> Void
    var togglePauseWatching: () -> Void
    var tidyReview: () -> Void
    var showHistory: () -> Void
    var showMainWindow: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}

/// Glass panel under the menu bar icon (macOS 27+, via `NSStatusItem` expanded interface).
struct MenuBarPanelView: View {
    @ObservedObject var model: MenuBarPanelModel
    @ObservedObject private var progress = SortProgressTracker.shared
    let actions: MenuBarPanelActions

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if progress.isActive {
                sortingSection
            }
            if model.reviewCount > 0 {
                reviewRow
            }
            sortButton
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .tint(binkyTintColor)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: BinkyMenuBarIcon.image)
                .renderingMode(.template)
                .foregroundStyle(binkyTintColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Binky", comment: "Menu bar panel title."))
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusLine: String {
        if model.watchingPaused {
            return String(localized: "Watching paused.", comment: "Menu bar panel status: folder watching is paused.")
        }
        guard let last = model.lastSort else {
            return String(localized: "Nothing sorted yet.", comment: "Menu bar panel status: no sort history.")
        }
        let when = Self.relativeFormatter.localizedString(for: last.timestamp, relativeTo: Date())
        return String(
            localized: "Sorted \(last.fileCount) · \(when)",
            comment: "Menu bar panel status: file count from the last sort, then a relative time like '4 min. ago'."
        )
    }

    private var sortingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BinkySortProgressBar(fraction: progress.fraction, caption: progress.bannerCaption, compact: true)
            HStack(spacing: 8) {
                Button(
                    progress.runState == .paused
                        ? String(localized: "Resume sorting", comment: "Menu bar command.")
                        : String(localized: "Pause sorting", comment: "Menu bar command."),
                    action: actions.togglePauseSorting
                )
                Button(String(localized: "Stop sorting", comment: "Menu bar command."), action: actions.stopSorting)
            }
            .controlSize(.small)
            .disabled(progress.runState == .stopping)
        }
    }

    private var reviewRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(binkyTintColor)
            Text(String(localized: "\(model.reviewCount) want a second look.", comment: "Review popover subtitle."))
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(String(localized: "Tidy here…", comment: "Open in-app Review triage sheet."), action: actions.tidyReview)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var sortButton: some View {
        if model.routines.count > 1 {
            Menu {
                Button(String(localized: "Sort All Folders", comment: "Menu bar: sweep every enabled routine."), action: actions.sortAll)
                Divider()
                ForEach(model.routines) { routine in
                    Button(routine.title) { actions.sortRoutine(routine.id) }
                }
            } label: {
                Text(String(localized: "Sort Now", comment: "Menu bar command."))
                    .frame(maxWidth: .infinity)
            } primaryAction: {
                actions.sortAll()
            }
            .menuStyle(.button)
            .glassProminentButton()
            .controlSize(.large)
            .disabled(progress.isActive)
        } else {
            Button(action: actions.sortAll) {
                Text(String(localized: "Sort Now", comment: "Menu bar command."))
                    .frame(maxWidth: .infinity)
            }
            .glassProminentButton()
            .controlSize(.large)
            .disabled(progress.isActive)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            footerButton(
                model.watchingPaused
                    ? String(localized: "Resume watching", comment: "Menu bar command.")
                    : String(localized: "Pause watching", comment: "Menu bar command."),
                systemImage: model.watchingPaused ? "play.circle" : "pause.circle",
                action: actions.togglePauseWatching
            )
            footerButton(
                String(localized: "History…", comment: "Menu bar command."),
                systemImage: "clock.arrow.circlepath",
                action: actions.showHistory
            )
            footerButton(
                String(localized: "Show Binky", comment: "Menu bar command."),
                systemImage: "macwindow",
                action: actions.showMainWindow
            )
            footerButton(
                String(localized: "Settings…", comment: "Menu bar command."),
                systemImage: "gearshape",
                action: actions.openSettings
            )
            Spacer(minLength: 0)
            footerButton(
                String(localized: "Quit Binky", comment: "Menu bar command."),
                systemImage: "power",
                action: actions.quit
            )
        }
        .font(.title3)
        .foregroundStyle(.secondary)
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}
