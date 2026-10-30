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

/// What the panel's rows do. The controller fills these with the same handlers as the classic menu.
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
    var about: () -> Void
    var quit: () -> Void
}

/// The menu bar panel (macOS 27+, via `NSStatusItem`'s expanded interface), laid out like Slinky's:
/// a header with status and one toggle, then rows that behave like menu items.
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
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 12)

            if progress.isActive {
                sortingSection
                Divider().padding(.horizontal, 12)
            }

            sortRows
                .padding(6)

            if model.reviewCount > 0 {
                Divider().padding(.horizontal, 12)
                PanelMenuRow(
                    icon: "folder.badge.questionmark",
                    title: String(localized: "\(model.reviewCount) want a second look.", comment: "Review popover subtitle."),
                    action: actions.tidyReview
                )
                .padding(6)
            }

            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                PanelMenuRow(icon: "macwindow", title: String(localized: "Show Binky", comment: "Menu bar command."), action: actions.showMainWindow)
                PanelMenuRow(icon: "clock.arrow.circlepath", title: String(localized: "History…", comment: "Menu bar command."), action: actions.showHistory)
                PanelMenuRow(icon: "gearshape", title: String(localized: "Settings…", comment: "Menu bar command."), shortcut: "⌘,", action: actions.openSettings)
                PanelMenuRow(icon: "info.circle", title: String(localized: "About Binky", comment: "Application menu: about panel."), action: actions.about)
                PanelMenuRow(icon: "power", title: String(localized: "Quit Binky", comment: "Menu bar command."), shortcut: "⌘Q", action: actions.quit)
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            mark
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Binky", comment: "Menu bar panel title."))
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        // Paused isn't a warning.
                        .fill(model.watchingPaused ? Color.secondary : Color.green)
                        .frame(width: 6, height: 6)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: actions.togglePauseWatching) {
                Image(systemName: model.watchingPaused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18, height: 18)
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .help(model.watchingPaused
                  ? String(localized: "Resume watching", comment: "Menu bar command.")
                  : String(localized: "Pause watching", comment: "Menu bar command."))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// The app icon in small: pink tile, white pacifier.
    private var mark: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(binkyTintColor.gradient)
            .frame(width: 30, height: 30)
            .overlay {
                Image(nsImage: BinkyMenuBarIcon.image)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    private var statusLine: String {
        if model.watchingPaused {
            return String(localized: "Watching paused.", comment: "Menu bar panel status: folder watching is paused.")
        }
        guard let last = model.lastSort else {
            return String(localized: "Watching. Nothing sorted yet.", comment: "Menu bar panel status: watching, no sort history.")
        }
        let when = Self.relativeFormatter.localizedString(for: last.timestamp, relativeTo: Date())
        return String(
            localized: "Sorted \(last.fileCount) · \(when)",
            comment: "Menu bar panel status: file count from the last sort, then a relative time like '4 min. ago'."
        )
    }

    // MARK: - Sorting

    private var sortingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            BinkySortProgressBar(fraction: progress.fraction, caption: progress.bannerCaption, compact: true)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
            PanelMenuRow(
                icon: progress.runState == .paused ? "play" : "pause",
                title: progress.runState == .paused
                    ? String(localized: "Resume sorting", comment: "Menu bar command.")
                    : String(localized: "Pause sorting", comment: "Menu bar command."),
                disabled: progress.runState == .stopping,
                action: actions.togglePauseSorting
            )
            PanelMenuRow(
                icon: "stop",
                title: String(localized: "Stop sorting", comment: "Menu bar command."),
                disabled: progress.runState == .stopping,
                action: actions.stopSorting
            )
        }
        .padding(6)
    }

    private var sortRows: some View {
        VStack(spacing: 2) {
            if model.routines.count > 1 {
                PanelMenuRow(
                    icon: "tray.and.arrow.down",
                    title: String(localized: "Sort All Folders", comment: "Menu bar: sweep every enabled routine."),
                    disabled: progress.isActive,
                    action: actions.sortAll
                )
                ForEach(model.routines) { routine in
                    PanelMenuRow(
                        icon: "folder",
                        title: String(localized: "Sort \(routine.title)", comment: "Menu bar panel: sort one routine's folder; routine name."),
                        disabled: progress.isActive
                    ) {
                        actions.sortRoutine(routine.id)
                    }
                }
            } else {
                PanelMenuRow(
                    icon: "tray.and.arrow.down",
                    title: String(localized: "Sort Now", comment: "Menu bar command."),
                    disabled: progress.isActive,
                    action: actions.sortAll
                )
            }
        }
    }
}

/// A row that looks and behaves like a Tahoe menu item: icon, title, shortcut, accent highlight on hover.
/// Same as Slinky's `MenuRow`.
struct PanelMenuRow: View {
    let icon: String
    let title: String
    var shortcut: String?
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    private var highlighted: Bool { hovering && !disabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(highlighted ? Color.white : Color.secondary)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(highlighted ? Color.white.opacity(0.75) : Color.secondary)
                }
            }
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(highlighted ? binkyTintColor : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hovering = $0 }
    }
}
