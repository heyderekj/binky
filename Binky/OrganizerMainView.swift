import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main window: slim Binky behavior sidebar + recent sort activity (not a compression dropzone).
struct OrganizerMainView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject var vm: OrganizerViewModel
    @ObservedObject private var sortProgress = SortProgressTracker.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDropTargeted = false
    @State private var showingCurrentlySortingSheet = false
    @State private var showingReviewTriage = false

    /// Same persistence key as Dinky below-update review strip.
    @AppStorage("reviewPromptBelowUpdateDismissed") private var reviewPromptBelowUpdateDismissed = false
    @AppStorage("binky.onboarding.calmDesktopDismissed") private var calmDesktopOnboardingDismissed = false

    /// One-shot sort target folder (sidebar Quick Sort panel only).
    @State private var quickSortFolderURL =
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    @State private var weeklyDigestPresentation: WeeklyDigestShareModel?

    private static let quickSortStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let absoluteTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationSplitView {
            slimOrganizerSidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
                .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
        } detail: {
            activityMainPane
                .frame(minWidth: 440, minHeight: 440)
                .background(.ultraThinMaterial)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if showReviewBanner {
                    reviewToolbarButton
                }
            }
        }
        .task {
            await updater.check()
        }
        .onAppear {
            BinkyMenuBarController.shared.refresh()
            quickSortFolderURL = prefs.downloadsSortRootDirectory()
            expandSidebarIfRoutinesExist()
            if PendingWindowRequest.takeReviewTriage() { showingReviewTriage = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyPendingWindowRequest)) { _ in
            if PendingWindowRequest.takeReviewTriage() { showingReviewTriage = true }
        }
        .onChange(of: prefs.savedPresets) { _, _ in
            expandSidebarIfRoutinesExist()
            // Keeps "Sort <routine> with Binky" phrases in step with renamed or new routines.
            BinkyAppShortcuts.updateAppShortcutParameters()
        }
        .onChange(of: prefs.showMenuBarIcon) { _, _ in
            BinkyMenuBarController.shared.refresh()
        }
        .sheet(isPresented: $showingCurrentlySortingSheet) {
            CurrentlySortingSheet()
        }
        .sheet(isPresented: $showingReviewTriage) {
            ReviewFolderTriageSheet()
                .environmentObject(prefs)
        }
        .sheet(item: $weeklyDigestPresentation, onDismiss: { weeklyDigestPresentation = nil }) { model in
            WeeklyDigestActionsSheet(model: model)
        }
        .onChange(of: prefs.watchedFolderPath) { _, _ in
            quickSortFolderURL = prefs.downloadsSortRootDirectory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkyPrepareQuit)) { _ in
            showingCurrentlySortingSheet = false
            showingReviewTriage = false
        }
    }

    // MARK: - Sidebar (Binky only)

    private var slimOrganizerSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                quickSortSidebarScrollContent
                if !prefs.sidebarSimpleMode {
                    routinesSidebarScrollContent
                }
            }
            .padding(10)
        }
    }

    /// Quick Sort: compact folder well + Sort Now (when **Routines** isn’t showing in the sidebar).
    private var quickSortSidebarScrollContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                settingsSectionHeading(
                    icon: "bolt.fill",
                    title: String(localized: "Quick Sort", comment: "Organizer sidebar: Quick Sort section title.")
                )

                Text(String(localized: "Sort this folder:", comment: "Quick Sort picker label."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                quickSortFolderWellSidebar

                Button {
                    Task { await vm.runInteractiveSweep(in: quickSortFolderURL, prefs: prefs) }
                } label: {
                    Text(String(localized: "Sort Now", comment: "Quick Sort primary button."))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .glassProminentButton()
                .controlSize(.large)
                .keyboardShortcut(KeyEquivalent.return, modifiers: [])
                .tint(binkyTintColor)

                if let last = prefs.sessionHistory.first {
                    quickSortLastSessionSnippet(last)
                } else {
                    Text(String(localized: "Runs show up here after your first sweep.", comment: "Quick Sort empty hint."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.35)

                if WeeklyDigestShareModel.build(from: prefs.sessionHistory) != nil {
                    Button(String(localized: "This week’s digest card…", comment: "Quick Sort weekly digest opener.")) {
                        weeklyDigestPresentation = WeeklyDigestShareModel.build(from: prefs.sessionHistory)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(binkyTintColor)
                }

                if prefs.sidebarSimpleMode {
                    Text(String(localized: "Need routine controls too? Switch Sidebar style to Expanded in Appearance.", comment: "Quick Sort sidebar: hint about enabling expanded mode."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var quickSortFolderWellSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: quickSortFolderIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(quickSortFolderURL.lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(tildeShorten(quickSortFolderURL.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(String(localized: "Choose Folder…", comment: "Quick Sort open panel.")) {
                    chooseQuickSortFolder()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.borderless)
                .foregroundStyle(binkyTintColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }

    private var quickSortFolderIcon: NSImage {
        let path = quickSortFolderURL.path
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .folder)
    }

    private func chooseQuickSortFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = quickSortFolderURL
        panel.prompt = String(localized: "Choose Folder", comment: "Quick Sort choose folder panel.")
        if panel.runModal() == .OK, let url = panel.url {
            quickSortFolderURL = url.standardizedFileURL
        }
    }

    private func quickSortLastSessionSnippet(_ record: SessionRecord) -> some View {
        Button {
            NotificationCenter.default.post(name: .binkyShowHistory, object: nil)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Latest run", comment: "Quick Sort last session caption."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.quickSortStampFormatter.string(from: record.timestamp))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(record.formats.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("history_session_file_count", bundle: .main, comment: "Reuse history pluralization."),
                            record.fileCount
                        )
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .card(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }

    private var routinesSidebarScrollContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    settingsSectionHeading(
                        icon: "repeat.circle",
                        title: String(localized: "Routines", comment: "Organizer sidebar: routines list section.")
                    )
                    Spacer(minLength: 0)
                    Text(routinesCountLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                routinesWatchStatusRow

                profileSelectionRows
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Sidebar footer

    /// Update card, then quiet footer actions, pinned under the sidebar like Slinky's and Dinky's.
    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            if showUpdateBanner {
                VStack(alignment: .leading, spacing: 8) {
                    UpdateBanner(updater: updater, itemCount: updateBannerItemCount)
                    if !reviewPromptBelowUpdateDismissed {
                        ReviewPromptBanner {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                reviewPromptBelowUpdateDismissed = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 14) {
                Button {
                    PreferencesTab.openPreferencesWindow(selecting: .routines)
                } label: {
                    Label(String(localized: "New Routine", comment: "Sidebar footer: opens Settings to add a routine."), systemImage: "plus.circle")
                }
                .help(String(localized: "Add a routine in Settings", comment: "Sidebar footer tooltip."))
                Spacer(minLength: 0)
                Button {
                    NotificationCenter.default.post(name: .binkyShowHistory, object: nil)
                } label: {
                    Label(String(localized: "History", comment: "Sidebar footer: sort history."), systemImage: "clock.arrow.circlepath")
                        .labelStyle(.iconOnly)
                }
                .help(String(localized: "History", comment: "Sidebar footer: sort history."))
                Button {
                    PreferencesTab.openPreferencesWindow(selecting: .generalBehavior)
                } label: {
                    Label(String(localized: "Settings", comment: "Sidebar footer: open Settings."), systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .help(String(localized: "Settings", comment: "Sidebar footer: open Settings."))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .animation(.smooth, value: showUpdateBanner)
    }

    // MARK: - Routines watch status row (inside Routines card)

    private var routinesWatchStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(watchStatusColor)
                .frame(width: 7, height: 7)
                .shadow(color: watchStatusColor.opacity(0.5), radius: 2, x: 0, y: 0)
                .animation(.easeInOut(duration: 0.3), value: watchStatusColor)

            Text(watchStatusLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .animation(.none, value: watchStatusLabel)
                .lineLimit(1)

            if !watchStatusFolderName.isEmpty {
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text(watchStatusFolderName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if prefs.folderWatchEnabled {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        prefs.folderWatchPaused.toggle()
                    }
                } label: {
                    Image(systemName: prefs.folderWatchPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(prefs.folderWatchPaused ? Color.green : binkyTintColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    prefs.folderWatchPaused
                        ? String(localized: "Resume watching", comment: "Watch status: resume button.")
                        : String(localized: "Pause watching", comment: "Watch status: pause button.")
                )
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var watchStatusColor: Color {
        guard prefs.folderWatchEnabled else { return Color.secondary.opacity(0.5) }
        if prefs.folderWatchPaused { return .orange }
        return enabledRoutineCount == 0 ? Color.secondary.opacity(0.5) : .green
    }

    private var watchStatusLabel: String {
        if !prefs.folderWatchEnabled {
            return String(localized: "Watch off", comment: "Sidebar watch status label.")
        }
        if prefs.folderWatchPaused {
            return String(localized: "Paused", comment: "Sidebar watch status label.")
        }
        let n = enabledRoutineCount
        if n == 0 {
            return String(localized: "Idle", comment: "Sidebar watch status: no enabled routines.")
        }
        if n == 1 {
            return String(localized: "Watching", comment: "Sidebar watch status: single routine.")
        }
        return String.localizedStringWithFormat(
            String(localized: "Watching %lld folders", comment: "Sidebar watch status: multiple folders."),
            Int64(n)
        )
    }

    private var watchStatusFolderName: String {
        let enabled = enabledRoutines
        if enabled.isEmpty {
            if prefs.folderWatchEnabled {
                return String(localized: "Nothing enabled yet", comment: "Sidebar watch status subtitle when nothing on yet.")
            }
            return String(localized: "Sorting paused indefinitely", comment: "Sidebar watch status subtitle when watching is off.")
        }
        if enabled.count == 1, let only = enabled.first {
            return tildeShorten(only.watchFolderPath)
        }
        let names = enabled.prefix(2).map { $0.name }.joined(separator: ", ")
        if enabled.count > 2 {
            return String.localizedStringWithFormat(
                String(localized: "%@, +%lld more", comment: "Sidebar watch status subtitle: list overflow."),
                names, Int64(enabled.count - 2)
            )
        }
        return names
    }

    private var enabledRoutines: [CompressionPreset] {
        prefs.savedPresets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var enabledRoutineCount: Int { enabledRoutines.count }

    private var routinesCountLabel: String {
        let total = prefs.savedPresets.count
        let on = enabledRoutineCount
        return String.localizedStringWithFormat(
            String(localized: "%lld of %lld on", comment: "Routines count chip: enabled / total."),
            Int64(on), Int64(total)
        )
    }

    /// Automatically switch the sidebar to Expanded when at least one routine is enabled.
    /// If all routines are disabled the lock releases and Simple becomes available again.
    private func expandSidebarIfRoutinesExist() {
        guard prefs.savedPresets.contains(where: { $0.isEnabled }), prefs.sidebarSimpleMode else { return }
        prefs.applySidebarSimpleMode(false)
    }

    private func tildeShorten(_ path: String) -> String {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if p.hasPrefix(home) {
            return "~" + String(p.dropFirst(home.count))
        }
        return p
    }

    private var activePreset: CompressionPreset? {
        guard let id = UUID(uuidString: prefs.activePresetID) else { return nil }
        return prefs.savedPresets.first(where: { $0.id == id })
    }

    private var profileSelectionRows: some View {
        VStack(spacing: 3) {
            ForEach(Array(prefs.savedPresets.enumerated()), id: \.element.id) { idx, preset in
                routineRow(preset: preset, presetIndex: idx)
            }
        }
    }

    /// Maps a preset's runtime state to the dot color shown in the sidebar row.
    private func presetRuntimeColor(_ preset: CompressionPreset) -> Color {
        let pathSet = !preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !preset.isEnabled || !pathSet {
            return Color.secondary.opacity(0.4)
        }
        if !prefs.folderWatchEnabled || prefs.folderWatchPaused {
            return .orange
        }
        return .green
    }

    /// Short, human source-folder hint displayed under the routine name.
    private func presetPathSubtitle(_ preset: CompressionPreset) -> String {
        let path = preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return String(localized: "No folder yet", comment: "Routine row subtitle when path empty.")
        }
        return tildeShorten(path)
    }

    @ViewBuilder
    private func routineRow(preset: CompressionPreset, presetIndex: Int) -> some View {
        let isActive = prefs.activePresetID == preset.id.uuidString
        let pathEmpty = preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Button {
            prefs.activePresetID = preset.id.uuidString
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(presetRuntimeColor(preset))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(preset.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(presetPathSubtitle(preset))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    var copy = prefs.savedPresets
                    guard copy.indices.contains(presetIndex) else { return }
                    copy[presetIndex].isEnabled.toggle()
                    prefs.savedPresets = copy
                } label: {
                    Image(systemName: preset.isEnabled ? "eye.fill" : "eye.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(preset.isEnabled ? binkyTintColor : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(pathEmpty)
                .opacity(pathEmpty ? 0.35 : 1)
                .help(preset.isEnabled
                      ? String(localized: "Turn this routine off", comment: "Eye icon tooltip when on.")
                      : String(localized: "Turn this routine on", comment: "Eye icon tooltip when off."))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? binkyTintColor.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isActive ? binkyTintColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main: activity feed

    private var sortProgressBanner: some View {
        Group {
            if sortProgress.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Sorting", comment: "Main pane banner title while folder sort runs."))
                                .font(.subheadline.weight(.semibold))
                            if sortProgress.bannerCaption.isEmpty == false {
                                Text(sortProgress.bannerCaption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .accessibilityLabel(sortProgress.bannerCaption)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Button {
                                if sortProgress.runState == .paused {
                                    DownloadsSortOrchestrator.shared.resumeCurrentSort()
                                } else {
                                    DownloadsSortOrchestrator.shared.pauseCurrentSort()
                                }
                            } label: {
                                Image(systemName: sortProgress.runState == .paused ? "play.fill" : "pause.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(binkyTintColor.opacity(sortProgress.runState == .stopping ? 0.5 : 0.9))
                            .accessibilityLabel(
                                sortProgress.runState == .paused
                                    ? String(localized: "Resume sort", comment: "Main banner button to resume paused sort.")
                                    : String(localized: "Pause sort", comment: "Main banner button to pause active sort.")
                            )
                            .disabled(sortProgress.runState == .stopping)

                            Button {
                                DownloadsSortOrchestrator.shared.stopCurrentSort()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(sortProgress.runState == .stopping ? 0.4 : 0.8))
                            .accessibilityLabel(String(localized: "Stop sort", comment: "Main banner button to stop active sort."))
                            .disabled(sortProgress.runState == .stopping)
                        }
                        Button {
                            showingCurrentlySortingSheet = true
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                                .foregroundStyle(binkyTintColor.opacity(0.85))
                                .accessibilityLabel(String(localized: "Show sort details", comment: "Opens per-file sorting sheet."))
                                .accessibilityHint(String(localized: "Shows filenames and activity for this sort.", comment: "VoiceOver hint for sort details button."))
                        }
                        .buttonStyle(.plain)
                    }

                    BinkySortProgressBar(
                        fraction: sortProgress.fraction,
                        caption: nil,
                        compact: false,
                        showsCaption: false
                    )
                    .animation(.easeInOut(duration: 0.42), value: sortProgress.fraction)
                }
                .padding(.horizontal, 20)
                .padding(.top, showCalmDesktopBanner ? 10 : 16)
                .padding(.bottom, 14)
                .background(Color.primary.opacity(0.035))
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.22)
                }
            }
        }
    }

    private var activityMainPane: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                if showCalmDesktopBanner {
                    calmDesktopBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    Divider()
                        .opacity(0.35)
                }

                sortProgressBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.26), value: sortProgress.isActive)

                activitySection
            }
            .overlay(alignment: .bottom) {
                noticeToast
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(binkyTintColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Short notices float up from the bottom as a glass capsule and leave on their own, like Slinky's toasts.
    private var noticeToast: some View {
        ZStack {
            if let msg = vm.transientBannerMessage, !sortProgress.isActive {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.secondary)
                    Text(msg)
                        .font(.callout)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: 560)
                .adaptiveGlass(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .padding(.bottom, 22)
                .padding(.horizontal, 20)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 18)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.32), value: vm.transientBannerMessage)
    }

    private var showCalmDesktopBanner: Bool {
        guard !calmDesktopOnboardingDismissed else { return false }
        let desktopPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .standardizedFileURL.path
        return !prefs.savedPresets.contains { preset in
            let path = preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return false }
            return URL(fileURLWithPath: path).standardizedFileURL.path == desktopPath
        }
    }

    @State private var showReviewPopover = false

    private var reviewToolbarButton: some View {
        Button {
            showReviewPopover.toggle()
        } label: {
            Image(systemName: "folder.badge.questionmark")
        }
        .help(String(localized: "Pending review", comment: "Toolbar button tooltip: pending review files."))
        .adaptiveToolbarBadge(Int(min(reviewBannerCount, 99)), tint: binkyTintColor)
        .popover(isPresented: $showReviewPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundStyle(binkyTintColor)
                        .font(.title3)
                    Text(String(localized: "Pending review", comment: "Review popover title."))
                        .font(.headline)
                }
                Text(String(localized: "\(reviewBannerCount) want a second look.", comment: "Review popover subtitle."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(String(localized: "Tidy here…", comment: "Open in-app Review triage sheet.")) {
                        showReviewPopover = false
                        showingReviewTriage = true
                    }
                    .glassProminentButton()
                    .tint(binkyTintColor)
                    .controlSize(.regular)
                    Button(String(localized: "Open in Finder", comment: "Reveal Review folder in Finder.")) {
                        showReviewPopover = false
                        openReviewInFinder()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(minWidth: 220)
        }
    }

    private var calmDesktopBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Desktop also loud?", comment: "Onboarding banner: suggest Calm my Desktop routine."))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "Same pacifier, different crib.", comment: "Onboarding banner subtitle."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                PreferencesTab.stageRoutinesWithCalmDesktopTemplate()
                PreferencesTab.openPreferencesWindow()
            } label: {
                Text(String(localized: "Calm my Desktop…", comment: "Opens Settings to add Desktop routine."))
            }
            .glassProminentButton()
            .tint(binkyTintColor)
            .controlSize(.small)

            Button(String(localized: "Dismiss", comment: "Dismiss Desktop onboarding banner.")) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    calmDesktopOnboardingDismissed = true
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(binkyTintColor)
        }
        .padding(12)
        .card(cornerRadius: 10)
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(binkyTintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Pending review", comment: "Organizer banner when the Review folder has items."))
                    .font(.subheadline.weight(.semibold))
                Text(
                    String(localized: "\(reviewBannerCount) want a second look.", comment: "Organizer banner: files in Review needing attention; integer count interpolated.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Tidy here…", comment: "Open in-app Review triage sheet.")) {
                showingReviewTriage = true
            }
            .glassProminentButton()
            .tint(binkyTintColor)
            .controlSize(.small)

            Button(String(localized: "Open Review in Finder", comment: "Reveal Review folder in Finder.")) {
                openReviewInFinder()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(binkyTintColor)
        }
        .padding(12)
        .card(cornerRadius: 10)
    }

    @ViewBuilder
    private var activitySection: some View {
        let rows = sortHistoryRows
        if rows.isEmpty {
            emptyActivityState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(String(localized: "Recent activity", comment: "Organizer main section title."))
                        .font(.headline)
                    Spacer(minLength: 0)
                    Button(S.clear) {
                        clearRecentActivity()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(binkyTintColor)
                    .font(.subheadline.weight(.medium))
                    .accessibilityHint(String(localized: "Clears recent activity and returns to the empty state.", comment: "VoiceOver hint for clearing recent activity."))
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            activityRow(row)
                            Divider()
                                .opacity(0.2)
                                .padding(.leading, 20)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var emptyActivityState: some View {
        OrganizerEmptyStateView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activityRow(_ row: SortHistoryRowModel) -> some View {
        let routineChipName = row.outcome.matchedRoutine(in: prefs.savedPresets)?.name
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(Self.absoluteTimeFormatter.string(from: row.record.timestamp))
                        .font(.subheadline.weight(.semibold))
                    if let routineChipName {
                        routineAttributionChip(name: routineChipName)
                    }
                }
                Text(countSummary(for: row.outcome))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                sessionSignalChips(for: row.outcome)
                reviewOriginChipsView(for: row.outcome)
            }
            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Button(String(localized: "Open Summary…", comment: "History row: reopen stored batch completion dialog.")) {
                    vm.presentHistoricalSortOutcome(row.outcome)
                }
                .glassProminentButton()
                .tint(binkyTintColor)
                .controlSize(.small)

                Button(String(localized: "Show in Finder", comment: "Reveal watched folder in Finder.")) {
                    revealHistoricalSource(row.outcome)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(binkyTintColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Tiny pill that names the routine an outcome belongs to. Mirrors the row dot styling so the eye is consistent across sidebar + activity feed.
    private func routineAttributionChip(name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 9, weight: .semibold))
            Text(name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(binkyTintColor.opacity(0.12))
        )
        .foregroundStyle(binkyTintColor)
        .accessibilityLabel(String(localized: "Routine: \(name)", comment: "VoiceOver: chip naming the routine that produced an outcome."))
    }

    private func revealHistoricalSource(_ outcome: SortBatchOutcome) {
        if let url = outcome.sourceRootURL(in: prefs.savedPresets) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        } else {
            openInboxInFinder()
        }
    }

    @ViewBuilder
    private func sessionSignalChips(for outcome: SortBatchOutcome) -> some View {
        let labels = sessionSignalChipLabels(for: outcome)
        if labels.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(width: 16, height: 1)
                }
            }
            .modifier(TrailingChipFadeModifier())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Session summary chips", comment: "VoiceOver: chips for sort session highlights."))
        }
    }

    private func sessionSignalChipLabels(for outcome: SortBatchOutcome) -> [String] {
        var out: [String] = []
        if outcome.alreadyHadCount > 0 {
            out.append(String.localizedStringWithFormat(
                String(localized: "%lld already had", comment: "Activity row chip; duplicate handling."),
                Int64(outcome.alreadyHadCount)
            ))
        }
        if outcome.receiptFiledCount > 0 {
            out.append(String.localizedStringWithFormat(
                String(localized: "%lld receipts filed", comment: "Activity row chip."),
                Int64(outcome.receiptFiledCount)
            ))
        }
        if outcome.reviewQueuedCount > 0 {
            out.append(String.localizedStringWithFormat(
                String(localized: "%lld in review", comment: "Activity row chip."),
                Int64(outcome.reviewQueuedCount)
            ))
        }
        return out
    }

    @ViewBuilder
    private func reviewOriginChipsView(for outcome: SortBatchOutcome) -> some View {
        let hosts = Self.sortedUniqueReviewOriginHosts(in: outcome)
        if !hosts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(hosts, id: \.self) { host in
                        Text(host)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(width: 16, height: 1)
                }
            }
            .modifier(TrailingChipFadeModifier())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Sources for Review items", comment: "VoiceOver: where-from host chips."))
        }
    }

    private static func sortedUniqueReviewOriginHosts(in outcome: SortBatchOutcome) -> [String] {
        let hosts = outcome.entries
            .filter { $0.disposition == .moved && $0.category == .review }
            .compactMap(\.originHost)
            .filter { !$0.isEmpty }
        return Array(Set(hosts)).sorted()
    }

    // MARK: - Models / derived state

    private struct SortHistoryRowModel: Identifiable {
        let id: UUID
        let record: SessionRecord
        let outcome: SortBatchOutcome
    }

    private var sortHistoryRows: [SortHistoryRowModel] {
        prefs.sessionHistory.compactMap { record in
            guard let data = record.batchSummaryData,
                  let outcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) else { return nil }
            return SortHistoryRowModel(id: record.id, record: record, outcome: outcome)
        }
    }

    private var showReviewBanner: Bool {
        reviewFolderItemCount > 0 || (vm.lastSortOutcome?.reviewQueuedCount ?? 0) > 0
    }

    /// Match Dinky: show when an update is due, and keep the strip visible through download/install/failure
    /// so manual “Install Update” from the alert isn’t silent when the same version was previously dismissed.
    private var showUpdateBanner: Bool {
        switch updater.installState {
        case .downloading, .installing, .failed:
            return true
        case .idle:
            return updater.shouldShow(dismissedVersion: prefs.dismissedUpdateVersion)
        }
    }

    /// Organizer parallel to Dinky `vm.items.count` — warn before relaunch clears in-flight sort / pending summary.
    private var updateBannerItemCount: Int {
        var n = 0
        if vm.pendingSortOutcome != nil { n += 1 }
        if sortProgress.isActive {
            let remaining = sortProgress.total - sortProgress.completed
            n += max(remaining, 1)
        }
        return n
    }

    private var reviewBannerCount: Int64 {
        max(
            Int64(reviewFolderItemCount),
            Int64(vm.lastSortOutcome?.reviewQueuedCount ?? 0)
        )
    }

    private var reviewFolderItemCount: Int {
        prefs.reviewFolderItemCount()
    }

    private func countSummary(for outcome: SortBatchOutcome) -> String {
        String.localizedStringWithFormat(
            String(localized: "%1$lld moved · %2$lld kept · %3$lld skipped · %4$lld review", comment: "Organizer activity row; four integer counts."),
            Int64(outcome.movedCount),
            Int64(outcome.keptCount),
            Int64(outcome.skippedCount),
            Int64(outcome.reviewQueuedCount)
        )
    }

    // MARK: - Actions

    private func openInboxInFinder() {
        let root = prefs.activeSortSweepRootDirectory()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root.path)
    }

    private func openReviewInFinder() {
        let root = prefs.activeSortSweepRootDirectory()
        let reviewURL = root.appendingPathComponent(FileSortCategory.review.downloadsSubfolder, isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: reviewURL.path)
    }

    private func clearRecentActivity() {
        prefs.sessionHistory = []
        vm.lastSortOutcome = nil
        vm.pendingSortOutcome = nil
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var collected: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var resolved: URL?
                if let url = item as? URL { resolved = url }
                else if let url = item as? NSURL { resolved = url as URL }
                else if let data = item as? Data { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                guard let url = resolved else { return }
                lock.lock()
                collected.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            Task {
                await vm.sortIncomingFiles(collected, prefs: prefs)
            }
        }
        return true
    }
}

/// Soft trailing fade for horizontal chip scrollers so clipped chips read as intentionally
/// trimmed instead of mid-character cut-offs. The leading edge stays sharp because content
/// always starts flush-left.
private struct TrailingChipFadeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}
