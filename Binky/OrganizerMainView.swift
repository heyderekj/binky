import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main window: slim Binky behavior sidebar + recent sort activity (not a compression dropzone).
struct OrganizerMainView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject var vm: OrganizerViewModel
    @ObservedObject private var sortProgress = SortProgressTracker.shared

    @State private var isDropTargeted = false
    @State private var showingCurrentlySortingSheet = false
    @State private var showingSortPreview = false
    @State private var sortPreviewRows: [SortPreviewEntry] = []
    @State private var showInlineSortPreview = false
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
        .sheet(isPresented: $showingSortPreview) {
            SortPreviewSheet(rows: sortPreviewRows)
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
            showingSortPreview = false
            showingCurrentlySortingSheet = false
            showInlineSortPreview = false
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
                sidebarSettingsCard
                sidebarAdditionalSettingsCard
                sidebarStyleFooterCard
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
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
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

                Text(
                    prefs.sidebarSimpleMode
                        ? String(localized: "Need routine controls too? Switch Sidebar style to Expanded in Appearance.", comment: "Quick Sort sidebar: hint about enabling expanded mode.")
                        : String(localized: "Expanded mode keeps both Quick Sort and Routines controls in one sidebar.", comment: "Quick Sort sidebar: hint while expanded mode is active.")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(tildeShorten(quickSortFolderURL.path))
                        .font(.system(size: 10))
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
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
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
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                routinesWatchStatusRow

                profileSelectionRows
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))

        }
    }

    private var sidebarSettingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsSectionHeading(
                icon: "slider.horizontal.3",
                title: String(localized: "Settings", comment: "Organizer sidebar settings header.")
            )

            Toggle(String(localized: "Slow mode", comment: "Settings UI."), isOn: $prefs.sortSlowModeEnabled)
                .font(.system(size: 11))

            Toggle(String(localized: "Notify when done", comment: "Settings UI."), isOn: Binding(
                get: { prefs.notifyWhenDone },
                set: { prefs.notifyWhenDone = $0 }
            ))
            .font(.system(size: 11))

            Toggle(String(localized: "Show summaries after sorting", comment: "Settings UI."), isOn: Binding(
                get: { prefs.showBatchSummaryDialog },
                set: { prefs.showBatchSummaryDialog = $0 }
            ))
            .font(.system(size: 11))

            Toggle(String(localized: "Open watch folder in Finder when done", comment: "Settings UI."), isOn: Binding(
                get: { prefs.openFolderWhenDone },
                set: { prefs.openFolderWhenDone = $0 }
            ))
            .font(.system(size: 11))

            sidebarShortcutRow(
                title: String(localized: "Open full history…", comment: ""),
                systemImage: "clock"
            ) {
                NotificationCenter.default.post(name: .binkyShowHistory, object: nil)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
    }

    private var sidebarAdditionalSettingsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            settingsSectionHeading(
                icon: "arrow.up.right.square",
                title: String(localized: "Additional settings", comment: "Organizer sidebar extra settings header.")
            )
            organizerSettingsSidebarLink(
                tab: .routines,
                title: String(localized: "Routines", comment: "Organizer sidebar shortcut to routines."),
                systemImage: "repeat.circle"
            )
            organizerSettingsSidebarLink(
                tab: .generalBehavior,
                title: String(localized: "All settings", comment: "Organizer sidebar shortcut to general settings tab."),
                systemImage: "gearshape"
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
    }

    /// Footer card that points to Appearance where sidebar style is configured.
    private var sidebarStyleFooterCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Want to change this layout?", comment: "Sidebar footer heading for style setting link."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            organizerSettingsSidebarLink(
                tab: .appearance,
                title: String(localized: "Sidebar style in Appearance…", comment: "Sidebar footer link to appearance tab."),
                systemImage: "sidebar.left"
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .animation(.none, value: watchStatusLabel)
                .lineLimit(1)

            if !watchStatusFolderName.isEmpty {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(watchStatusFolderName)
                    .font(.system(size: 11))
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
                        .font(.system(size: 18))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(preset.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(presetPathSubtitle(preset))
                        .font(.system(size: 10))
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
                        .font(.system(size: 11, weight: .semibold))
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

    /// Opens the preferences window and matches the row styling of legacy sidebar links.
    private func organizerSettingsSidebarLink(tab: PreferencesTab, title: String, systemImage: String) -> some View {
        Button {
            PreferencesTab.openPreferencesWindow(selecting: tab)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(binkyTintColor)
    }

    /// Dinky-style sidebar row: leading SF Symbol, accent label, trailing chevron, plain hit area.
    private func sidebarShortcutRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(binkyTintColor)
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
                                    .font(.system(size: 14, weight: .semibold))
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
                                    .font(.system(size: 14, weight: .semibold))
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
                                .font(.system(size: 24))
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
                .padding(.top, (showCalmDesktopBanner || showUpdateBanner) ? 10 : 16)
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
                if showUpdateBanner {
                    VStack(spacing: 8) {
                        UpdateBanner(updater: updater, itemCount: updateBannerItemCount)
                            .environmentObject(prefs)
                        if !reviewPromptBelowUpdateDismissed {
                            ReviewPromptBanner {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    reviewPromptBelowUpdateDismissed = true
                                }
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: updater.availableVersion)
                    Divider()
                        .opacity(0.35)
                }

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

                transientNoticeBanner

                activitySection
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(binkyTintColor.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The path the active routine sorts. Falls back to the global default when no preset is selected.
    private var activeFolderURL: URL {
        prefs.activeSortSweepRootDirectory()
    }

    /// macOS uses special icons for `~/Downloads`, `~/Desktop`, etc. — fetching the live Finder icon makes the card unmistakable.
    private var activeFolderIcon: NSImage {
        let path = activeFolderURL.path
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .folder)
    }

    private var activeFolderName: String {
        let name = activeFolderURL.lastPathComponent
        return name.isEmpty ? String(localized: "Folder", comment: "Fallback folder name.") : name
    }

    private var activeFolderShortPath: String {
        tildeShorten(activeFolderURL.path)
    }

    private var activeFolderCard: some View {
        Button {
            openInboxInFinder()
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: activeFolderIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(activeFolderName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(activeFolderShortPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(binkyTintColor.opacity(0.7))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Reveal \(activeFolderName) in Finder", comment: "VoiceOver: active folder card opens Finder."))
        .help(String(localized: "Reveal in Finder", comment: "Tooltip for active folder card."))
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsSectionHeading(
                icon: "bolt.fill",
                title: String(localized: "Quick actions", comment: "Organizer sidebar: ad-hoc sort/preview controls.")
            )

            activeFolderCard

            HStack(spacing: 10) {
                Button {
                    Task {
                        let rows = await vm.inboxPreviewEntries(prefs: prefs)
                        await MainActor.run {
                            sortPreviewRows = rows
                            showInlineSortPreview = true
                        }
                    }
                } label: {
                    Text(String(localized: "Preview…", comment: "Dry-run sort sorted folders."))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)

                Button {
                    Task {
                        if enabledRoutineCount > 1 {
                            await vm.runInteractiveSweepAllRoutines(prefs: prefs)
                        } else {
                            await vm.runInteractiveDownloadsSweep(prefs: prefs)
                        }
                    }
                } label: {
                    Text(enabledRoutineCount > 1
                         ? String(localized: "Sort All", comment: "Primary sort button: sort all enabled routines.")
                         : String(localized: "Sort Now", comment: "Primary sort button."))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if sortProgress.isActive {
                BinkySortProgressBar(
                    fraction: sortProgress.fraction,
                    caption: nil,
                    compact: true,
                    showsCaption: false
                )
                .transition(.opacity)
            }

            if showInlineSortPreview, !sortPreviewRows.isEmpty {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sortPreviewRows.prefix(5)) { row in
                        HStack(spacing: 6) {
                            Text(row.sourceLastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(inlinePreviewDestinationLabel(for: row))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                    }
                    if sortPreviewRows.count > 5 {
                        Text(String.localizedStringWithFormat(
                            String(localized: "+%lld more in full preview", comment: "Inline sort preview overflow count."),
                            Int64(sortPreviewRows.count - 5)
                        ))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    Button(String(localized: "Open full preview…", comment: "Expand sort preview sheet.")) {
                        showingSortPreview = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(binkyTintColor)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.03)))
    }

    private func inlinePreviewDestinationLabel(for row: SortPreviewEntry) -> String {
        let p = row.proposedDestinationPath
        if p == "—" { return p }
        let trash = String(localized: "Trash", comment: "Sort preview duplicate / trash label.")
        if p.caseInsensitiveCompare(trash) == .orderedSame || p == trash {
            return trash
        }
        return URL(fileURLWithPath: p).lastPathComponent
    }

    private var transientNoticeBanner: some View {
        Group {
            if let msg = vm.transientBannerMessage, !sortProgress.isActive {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "ellipsis.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.transientBannerMessage)
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

    @State private var showCalmDesktopPopover = false
    @State private var showReviewPopover = false

    private var calmDesktopToolbarButton: some View {
        Button {
            showCalmDesktopPopover.toggle()
        } label: {
            Image(systemName: "desktopcomputer")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(binkyTintColor)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Desktop also loud?", comment: "Toolbar button tooltip: Desktop onboarding."))
        .popover(isPresented: $showCalmDesktopPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(binkyTintColor)
                        .font(.system(size: 15))
                    Text(String(localized: "Desktop also loud?", comment: "Onboarding popover title."))
                        .font(.headline)
                }
                Text(String(localized: "Same pacifier, different crib.", comment: "Onboarding popover subtitle."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        showCalmDesktopPopover = false
                        PreferencesTab.stageRoutinesWithCalmDesktopTemplate()
                        PreferencesTab.openPreferencesWindow()
                    } label: {
                        Text(String(localized: "Calm my Desktop…", comment: "Opens Settings to add Desktop routine."))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(binkyTintColor)
                    .controlSize(.regular)
                    Button(String(localized: "Dismiss", comment: "Dismiss Desktop onboarding popover.")) {
                        withAnimation { calmDesktopOnboardingDismissed = true }
                        showCalmDesktopPopover = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(minWidth: 240)
        }
    }

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
                        .font(.system(size: 15))
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
                    .buttonStyle(.borderedProminent)
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
                .font(.system(size: 16))
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
            .buttonStyle(.borderedProminent)
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
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
            .buttonStyle(.borderedProminent)
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
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
                .buttonStyle(.borderedProminent)
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
