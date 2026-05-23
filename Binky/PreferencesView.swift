import SwiftUI
import AppKit
import UserNotifications

// MARK: - In-window navigation (contextual links between preference tabs)

private enum OpenPreferencesRelatedTabKey: EnvironmentKey {
    static let defaultValue: (PreferencesTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switch the Settings window to another tab (used for small “see also” links).
    fileprivate var openPreferencesRelatedTab: (PreferencesTab) -> Void {
        get { self[OpenPreferencesRelatedTabKey.self] }
        set { self[OpenPreferencesRelatedTabKey.self] = newValue }
    }
}

/// Small accent link, same spirit as ``SidebarView``’s “Change folder or naming…” / preset rows.
private struct PreferencesRelatedTabLink: View {
    @Environment(\.openPreferencesRelatedTab) private var openTab
    let title: String
    let tab: PreferencesTab

    var body: some View {
        Button(title) { openTab(tab) }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(binkyTintColor)
    }
}

private extension View {
    /// Matches Dinky’s preferences chrome: inline navigation title with Back/Forward in the unified title bar.
    @ViewBuilder
    func preferencesWindowToolbarChrome() -> some View {
        self
            .toolbarBackground(.clear, for: .windowToolbar)
            .modifier(PreferencesWindowToolbarVisibilityModifier())
    }
}

private struct PreferencesWindowToolbarVisibilityModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// Tabs in the Settings window — use ``PreferencesTab/openPreferencesWindow(selecting:)`` before presenting.
enum PreferencesTab: Int, Hashable, Identifiable {
    /// Legacy raw `0` — core behavior & Finder tags while sorting.
    case generalBehavior = 0
    /// Legacy raw `1` — was combined “Sorting”;/watch folder & inbox defaults.
    case sortWatchFolder = 1
    case routines = 2
    case shortcuts = 3
    case appearance = 4
    case sortSmartAndPace = 5
    case sortRouting = 6
    case sortStaleFiles = 7
    case sortExclusions = 8
    case sortPreview = 9
    case generalNotifications = 11
    case generalEnergy = 12
    case generalPrivacy = 13
    case generalProTools = 14
    case generalSupport = 15

    var id: Int { rawValue }

    static let pendingTabUserDefaultsKey = "prefs.pendingTab"

    static var generalGroup: [PreferencesTab] {
        [
            .generalBehavior,
            .generalNotifications,
            .generalEnergy,
            .generalPrivacy,
            .generalProTools,
            .generalSupport,
        ]
    }

    static var sortingGroup: [PreferencesTab] {
        [
            .sortWatchFolder,
            .sortSmartAndPace,
            .sortRouting,
            .sortStaleFiles,
            .sortExclusions,
            .sortPreview,
            .routines,
        ]
    }

    static var interfaceGroup: [PreferencesTab] {
        [.shortcuts, .appearance]
    }

    var sidebarLabel: String {
        switch self {
        case .generalBehavior:
            return String(localized: "Behavior", comment: "Settings sidebar: behavior & Finder tags.")
        case .generalNotifications:
            return String(localized: "Notifications", comment: "Settings sidebar.")
        case .generalEnergy:
            return String(localized: "Energy", comment: "Settings sidebar: thermal & pacing.")
        case .generalPrivacy:
            return String(localized: "Privacy", comment: "Settings sidebar.")
        case .generalProTools:
            return String(localized: "Pro tools", comment: "Settings sidebar: CLI.")
        case .generalSupport:
            return String(localized: "Support", comment: "Settings sidebar.")
        case .sortWatchFolder:
            return String(localized: "Watch folder", comment: "Settings sidebar: default inbox & watch.")
        case .sortSmartAndPace:
            return String(localized: "Smart & pace", comment: "Settings sidebar: smart sorting & slow mode.")
        case .sortRouting:
            return String(localized: "Routing", comment: "Settings sidebar: custom routing rules.")
        case .sortStaleFiles:
            return String(localized: "Stale files", comment: "Settings sidebar: file aging.")
        case .sortExclusions:
            return String(localized: "Never sort", comment: "Settings sidebar: skip lists.")
        case .sortPreview:
            return String(localized: "Preview", comment: "Settings sidebar: dry-run preview.")
        case .routines:
            return String(localized: "Routines", comment: "Settings UI: routines tab.")
        case .shortcuts:
            return String(localized: "Shortcuts", comment: "Settings UI.")
        case .appearance:
            return String(localized: "Appearance", comment: "Settings UI.")
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .generalBehavior: return "slider.horizontal.3"
        case .generalNotifications: return "bell"
        case .generalEnergy: return "leaf.fill"
        case .generalPrivacy: return "hand.raised"
        case .generalProTools: return "terminal"
        case .generalSupport: return "questionmark.circle"
        case .sortWatchFolder: return "folder"
        case .sortSmartAndPace: return "wand.and.stars"
        case .sortRouting: return "arrow.triangle.branch"
        case .sortStaleFiles: return "calendar.badge.clock"
        case .sortExclusions: return "slash.circle"
        case .sortPreview: return "eye"
        case .routines: return "repeat.circle"
        case .shortcuts: return "keyboard"
        case .appearance: return "sidebar.left"
        }
    }

    /// Stores the tab for the next preferences presentation and updates an already-open window.
    static func stagePendingTab(_ tab: PreferencesTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: pendingTabUserDefaultsKey)
        NotificationCenter.default.post(name: .binkySelectPreferencesTab, object: tab.rawValue)
    }

    /// Brings the preferences window forward (creating it if needed). Optionally selects a sidebar pane first.
    static func openPreferencesWindow(selecting tab: PreferencesTab? = nil) {
        if let tab {
            stagePendingTab(tab)
        }
        NotificationCenter.default.post(name: .binkyOpenMacPreferences, object: nil)
    }

    /// Maps legacy pending-tab indices and notification payloads to the current sidebar panes.
    static func migrateStoredTabIndex(_ raw: Int) -> PreferencesTab {
        switch raw {
        case 10:
            // Former standalone Housekeeping pane — merged into Behavior.
            return .generalBehavior
        case 2, 3:
            // Legacy: "Watch" (2) and "Profiles" (3) both land on Routines.
            return .routines
        case 4:
            return .shortcuts
        case 5:
            return .appearance
        default:
            return PreferencesTab(rawValue: raw) ?? .generalBehavior
        }
    }

    fileprivate static func consumePendingSelection() -> PreferencesTab? {
        guard UserDefaults.standard.object(forKey: pendingTabUserDefaultsKey) != nil else { return nil }
        let raw = UserDefaults.standard.integer(forKey: pendingTabUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: pendingTabUserDefaultsKey)
        return migrateStoredTabIndex(raw)
    }

    /// Onboarding: open Routines and auto-create the Calm Desktop template once the tab appears.
    static func stageRoutinesWithCalmDesktopTemplate() {
        UserDefaults.standard.set(RoutineTemplate.calmDesktop.rawValue, forKey: RoutineTemplate.pendingUserDefaultsKey)
        stagePendingTab(.routines)
    }
}

struct PreferencesView: View {
    @State private var history: [PreferencesTab] = [.generalBehavior]
    @State private var historyIndex: Int = 0

    private var selectedTab: PreferencesTab { history[historyIndex] }

    private var selectedTabBinding: Binding<PreferencesTab> {
        Binding(get: { history[historyIndex] }, set: { selectPane($0) })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTabBinding) {
                Section(String(localized: "General", comment: "Settings sidebar section header.")) {
                    ForEach(PreferencesTab.generalGroup, id: \.self) { tab in
                        Label(tab.sidebarLabel, systemImage: tab.sidebarSystemImage).tag(tab)
                    }
                }
                Section(String(localized: "Sorting", comment: "Settings sidebar section header.")) {
                    ForEach(PreferencesTab.sortingGroup, id: \.self) { tab in
                        Label(tab.sidebarLabel, systemImage: tab.sidebarSystemImage).tag(tab)
                    }
                }
                Section(String(localized: "Interface", comment: "Settings sidebar section header.")) {
                    ForEach(PreferencesTab.interfaceGroup, id: \.self) { tab in
                        Label(tab.sidebarLabel, systemImage: tab.sidebarSystemImage).tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            // Pull sidebar labels closer to the window edge; system default leaves a wide gutter beside the traffic lights.
            .contentMargins(.leading, 6, for: .automatic)
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
            .toolbarBackground(.clear, for: .automatic)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            NavigationStack {
                preferencesDetail(for: selectedTab)
                    .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedTab.sidebarLabel)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                goBack()
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Back", comment: "Preferences toolbar."))
                            .disabled(historyIndex == 0)
                        }
                        ToolbarItem(placement: .navigation) {
                            Button {
                                goForward()
                            } label: {
                                Image(systemName: "chevron.forward")
                            }
                            .buttonStyle(.bordered)
                            .help(String(localized: "Forward", comment: "Preferences toolbar."))
                            .disabled(historyIndex >= history.count - 1)
                        }
                        if #available(macOS 26.0, *) {
                            ToolbarSpacer(.flexible)
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .preferencesWindowToolbarChrome()
        .tint(binkyTintColor)
        .environment(\.openPreferencesRelatedTab) { selectPane($0) }
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .onAppear {
            if let tab = PreferencesTab.consumePendingSelection() {
                selectPane(tab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .binkySelectPreferencesTab)) { note in
            guard let raw = note.object as? Int else { return }
            let tab = PreferencesTab.migrateStoredTabIndex(raw)
            selectPane(tab)
            UserDefaults.standard.removeObject(forKey: PreferencesTab.pendingTabUserDefaultsKey)
        }
    }

    private func selectPane(_ tab: PreferencesTab) {
        guard tab != selectedTab else { return }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(tab)
        historyIndex = history.count - 1
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
    }

    private func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
    }

    @ViewBuilder
    private func preferencesDetail(for tab: PreferencesTab) -> some View {
        switch tab {
        case .generalBehavior:
            GeneralBehaviorTab()
        case .generalNotifications:
            GeneralNotificationsTab()
        case .generalEnergy:
            GeneralEnergyTab()
        case .generalPrivacy:
            GeneralPrivacyTab()
        case .generalProTools:
            GeneralProToolsTab()
        case .generalSupport:
            GeneralSupportTab()
        case .sortWatchFolder:
            SortWatchFolderTab()
        case .sortSmartAndPace:
            SortSmartAndPaceTab()
        case .sortRouting:
            SortRoutingTab()
        case .sortStaleFiles:
            SortStaleFilesTab()
        case .sortExclusions:
            SortExclusionsTab()
        case .sortPreview:
            SortPreviewTab()
        case .routines:
            RoutinesOrganizerTab()
        case .shortcuts:
            ShortcutsTab()
        case .appearance:
            AppearanceTab()
        }
    }
}

// MARK: - General (split sidebar panes)

private struct GeneralBehaviorTab: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled
    @State private var confirmForgetDuplicateMemory = false

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Open Binky at login", comment: "Settings UI."), isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
                    }
                ))
                if LaunchAtLoginManager.requiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(String(localized: "Approve Binky in System Settings → General → Login Items.", comment: "Settings UI."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Open…", comment: "Settings UI.")) { LaunchAtLoginManager.openLoginItemsSettings() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(binkyTintColor)
                    }
                }

                Toggle(String(localized: "Assign Finder tags when sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.assignFinderTagsOnSortEnabled },
                    set: { prefs.assignFinderTagsOnSortEnabled = $0 }
                ))
                Text(String(localized: "Adds simple Finder tags (“New”, category hints) so files remain searchable.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PreferencesRelatedTabLink(
                    title: String(localized: "Routing & sorted folders…", comment: "Settings UI: link from General to Sorting tab for tag-related sorted folders."),
                    tab: .sortWatchFolder
                )

                Toggle(String(localized: "Add the “New” Finder tag when sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.sortAppendNewSemanticTagEnabled },
                    set: { prefs.sortAppendNewSemanticTagEnabled = $0 }
                ))
                .disabled(!prefs.assignFinderTagsOnSortEnabled)
                if !prefs.assignFinderTagsOnSortEnabled {
                    Text(String(localized: "Requires “Assign Finder tags when sorting”.", comment: "Settings UI."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if prefs.assignFinderTagsOnSortEnabled {
                    DisclosureGroup {
                        FinderTagDefaultsByCategoryMapEditor(
                            map: Binding(
                                get: { prefs.sortFinderTagDefaultsByCategory },
                                set: { prefs.sortFinderTagDefaultsByCategory = $0 }
                            )
                        )
                    } label: {
                        Text(String(localized: "Default tags by type", comment: "Settings: Finder tag defaults per sort category."))
                    }
                    Text(String(localized: "Leave blank to use Binky’s built-in hint for each type. Routine settings can override these per workflow.", comment: "Settings: Finder tag defaults footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(String(localized: "Show summaries after sorting", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showBatchSummaryDialog },
                    set: { prefs.showBatchSummaryDialog = $0 }
                ))
                Text(String(localized: "Opens the move/review summary when autonomous sorting batches finish.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Behavior", comment: "Settings UI."))
            }

            Section {
                Picker(String(localized: "When Binky sees a duplicate file", comment: "Settings: duplicate handling."), selection: $prefs.sortDuplicateModeRaw) {
                    Text(String(localized: "Do nothing special", comment: "Duplicate mode off.")).tag(SortDuplicateHandlingMode.off.rawValue)
                    Text(String(localized: "Move to Duplicates folder", comment: "Duplicate mode.")).tag(SortDuplicateHandlingMode.moveToDuplicates.rawValue)
                    Text(String(localized: "Move to Trash", comment: "Duplicate mode.")).tag(SortDuplicateHandlingMode.moveToTrash.rawValue)
                }
                Text(String(localized: "Matches an identical file or a very similar image Binky already sorted.", comment: "Duplicate footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String.localizedStringWithFormat(
                    String(localized: "Binky remembers %lld files.", comment: "Duplicate fingerprint database count."),
                    Int64(FileHashStore.shared.storedRecordCount())
                ))
                .font(.callout)
                if prefs.lastSortAlreadyHadCount > 0 {
                    Text(String.localizedStringWithFormat(
                        String(localized: "%lld already had in the last sort.", comment: "Last sort duplicate-style count."),
                        Int64(prefs.lastSortAlreadyHadCount)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button(String(localized: "Forget everything…", comment: "Clear duplicate memory database.")) {
                    confirmForgetDuplicateMemory = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .confirmationDialog(
                    String(localized: "Forget remembered files?", comment: "Clear hash store title."),
                    isPresented: $confirmForgetDuplicateMemory,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Forget everything", comment: "Confirm clear duplicate memory."), role: .destructive) {
                        FileHashStore.shared.clearAllRecords()
                    }
                    Button(String(localized: "Keep it", comment: "Cancel clear duplicate memory."), role: .cancel) {}
                } message: {
                    Text(String(localized: "This clears Binky’s memory of files it’s seen. Duplicates won’t be recognized until they’re sorted again.", comment: "Clear hash store explanation."))
                }

                Toggle(String(localized: "Daily digest notification", comment: "Settings."), isOn: $prefs.dailyDigestEnabled)
                Stepper(value: $prefs.dailyDigestHour, in: 0...23) {
                    Text(String.localizedStringWithFormat(
                        String(localized: "Digest hour: %lld", comment: "Settings digest hour."),
                        Int64(prefs.dailyDigestHour)
                    ))
                }
                Text(String(localized: "One quiet summary of what Binky handled. Requires notification permission.", comment: "Digest footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(String(localized: "Weekly digest reminder", comment: "Settings: weekly rollup notification."), isOn: Binding(
                    get: { prefs.weeklyDigestEnabled },
                    set: { prefs.weeklyDigestEnabled = $0 }
                ))
                Text(String(localized: "Roughly Mondays at 9:00 AM (local): a rollup you can screenshot as the digest card.", comment: "Weekly digest footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            } header: {
                Text(String(localized: "Housekeeping", comment: "Settings section."))
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLoginEnabled = LaunchAtLoginManager.isEnabled }
    }
}

private struct GeneralNotificationsTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Play sound when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.playSoundEffects },
                    set: { prefs.playSoundEffects = $0 }
                ))
                Toggle(String(localized: "Notify when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.notifyWhenDone },
                    set: { newValue in
                        prefs.notifyWhenDone = newValue
                        if newValue { requestNotificationAuth() }
                    }
                ))
                Text(String(localized: "To receive notifications during Focus or Do Not Disturb, allow Binky in System Settings → Focus.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(String(localized: "Open watch folder in Finder when done", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.openFolderWhenDone },
                    set: { prefs.openFolderWhenDone = $0 }
                ))
                Text(String(localized: "Opens your watch folder in Finder after each sort batch completes.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Notifications", comment: "Settings UI."))
            } footer: {
                Button(String(localized: "Notification settings…", comment: "Settings UI.")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(binkyTintColor)
            }
        }
        .formStyle(.grouped)
    }

    private func requestNotificationAuth() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            case .denied:
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            default:
                break
            }
        }
    }
}

private struct GeneralEnergyTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Pause sorting on Low Power Mode", comment: "Settings: Energy section."), isOn: Binding(
                    get: { prefs.energyPauseOnLowPowerMode },
                    set: { prefs.energyPauseOnLowPowerMode = $0 }
                ))
                Toggle(String(localized: "Pause sorting when thermal state is critical", comment: "Settings: Energy section."), isOn: Binding(
                    get: { prefs.energyPauseOnThermalCritical },
                    set: { prefs.energyPauseOnThermalCritical = $0 }
                ))
                Stepper(value: Binding(
                    get: { prefs.energyBigBatchThreshold },
                    set: { prefs.energyBigBatchThreshold = $0 }
                ), in: 50...10_000, step: 50) {
                    Text(String.localizedStringWithFormat(
                        String(localized: "Big-batch threshold: %lld files", comment: "Settings: Energy section; file count before thermal pacing and progress coalescing."),
                        Int64(prefs.energyBigBatchThreshold)
                    ))
                }
                Picker(selection: Binding(
                    get: { prefs.energyThrottleProfile },
                    set: { prefs.energyThrottleProfile = $0 }
                )) {
                    Text(String(localized: "Auto", comment: "Settings: Energy throttle profile.")).tag(EnergyThrottleProfile.auto)
                    Text(String(localized: "Gentle", comment: "Settings: Energy throttle profile.")).tag(EnergyThrottleProfile.gentle)
                    Text(String(localized: "Aggressive", comment: "Settings: Energy throttle profile.")).tag(EnergyThrottleProfile.aggressive)
                } label: {
                    Text(String(localized: "Large-batch pacing", comment: "Settings: Energy throttle picker label."))
                }
                .pickerStyle(.segmented)
                Text(String(localized: "Applies to large sorts and watch-folder batches. Lower threshold means pacing starts sooner. Aggressive finishes faster when the Mac is warm; Gentle eases CPU and disk.", comment: "Settings: Energy section footnote."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "Energy", comment: "Settings: General tab section title."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralPrivacyTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Share crash diagnostics with Binky", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.crashReportingEnabled },
                    set: { newValue in
                        prefs.crashReportingEnabled = newValue
                        DiagnosticsReporter.shared.applyCrashReportingPreference()
                    }
                ))
                Text(String(localized: "When on, Apple's MetricKit can deliver anonymous crash and hang diagnostics to Binky on your Mac. Nothing leaves your device until you choose to send a report. Requires \u{201C}Share with App Developers\u{201D} in System Settings → Privacy & Security → Analytics & Improvements.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Privacy", comment: "Settings UI."))
            } footer: {
                Button(String(localized: "Open Analytics & Improvements settings…", comment: "Settings UI.")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Analytics")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(binkyTintColor)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralProToolsTab: View {
    var body: some View {
        Form {
            Section {
                Text(
                    String(
                        localized: "Build `binky` from the `BinkyCore` folder for scripts & Shortcuts. Same rules & prefs — shared lock prevents racing the GUI.",
                        comment: "CLI pro tools blurble in Settings."
                    )
                )
                .fixedSize(horizontal: false, vertical: true)

                Button(
                    String(
                        localized: "Open CLI setup on GitHub",
                        comment: "Settings button opening docs/local-cli.md in browser."
                    )
                ) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/heyderekj/binky/blob/main/docs/local-cli.md")!)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(binkyTintColor)

                Button(
                    String(
                        localized: "Copy Terminal build snippet",
                        comment: "Places swift build snippet on pasteboard."
                    )
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "cd ~/path/to/binky/BinkyCore && swift build -c release  # releases .build/release/binky",
                        forType: .string
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(binkyTintColor)
            } header: {
                Text(String(localized: "Pro tools (CLI)", comment: "Settings: CLI section heading."))
            } footer: {
                Text(
                    String(
                        localized: "Paths you pass aren’t sandboxed; bookmarks from the Finder sheet don’t propagate to Terminal.",
                        comment: "CLI security footnote in Settings."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSupportTab: View {
    var body: some View {
        Form {
            Section {
                PreferencesRelatedTabLink(title: String(localized: "Keyboard shortcuts…", comment: "Settings UI."), tab: .shortcuts)
                Link(S.supportEmail, destination: URL(string: "mailto:\(S.supportEmail)")!)
            } header: {
                Text(String(localized: "Support", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sorting (split sidebar panes)

private struct SortWatchFolderTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    private func pickGlobalDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose folder", comment: "Open panel: choose global default folder.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.watchedFolderPath = url.path
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            prefs.watchedFolderBookmark = bookmark
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Watch for new files", comment: "Global folder watch."), isOn: Binding(
                    get: { prefs.folderWatchEnabled },
                    set: { prefs.folderWatchEnabled = $0 }
                ))
                if prefs.folderWatchEnabled {
                    HStack {
                        Text(prefs.watchedFolderPath.isEmpty
                             ? String(localized: "Downloads (default)", comment: "Settings UI: default folder label.")
                             : URL(fileURLWithPath: prefs.watchedFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Settings UI.")) { pickGlobalDefaultFolder() }
                            .buttonStyle(.bordered)
                    }
                }
                Toggle(String(localized: "Also watch inside immediate subfolders (one level)", comment: "Settings: shallow recursive watch."), isOn: $prefs.watchRecursiveOneLevel)
                Toggle(String(localized: "Move loose folders into the Folders destination", comment: "Settings: relocate top-level directories as a unit."), isOn: $prefs.sortMoveLooseFoldersEnabled)
                if prefs.sortMoveLooseFoldersEnabled {
                    TextField(String(localized: "Relative path under sort root (empty = “Folders”)", comment: "Loose folder destination path."), text: $prefs.sortLooseFoldersDestinationRelative)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text(String(localized: "Default folder", comment: "Sorting tab: default folder section header."))
            } footer: {
                Text(String(localized: "The fallback folder when no routine's path matches. Add routines for Desktop, Dropbox, or anything else fussy. Loose folders are ordinary directories at the top of the watch folder — Binky can move them as one piece without sorting inside. That skips built-in destinations (Images, Documents, etc.) and sends app bundles to Apps.", comment: "Default folder section footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SortSmartAndPaceTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Smart screenshot names (OCR)", comment: "Settings."), isOn: $prefs.sortSmartScreenshotNamesEnabled)
                Toggle(String(localized: "Detect receipts and invoices", comment: "Settings."), isOn: $prefs.sortDetectReceiptsEnabled)
                Text(String(localized: "Receipts use on-device text heuristics. Pauses when Low Power Mode pauses sorting.", comment: "Settings smart sort footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "Smart sorting", comment: "Settings section."))
            }

            Section {
                Toggle(String(localized: "Slow mode", comment: "Sorting tab: deliberate per-file pacing."), isOn: $prefs.sortSlowModeEnabled)
                Text(String(localized: "Sort one file at a time, with a small pause between each, so you can actually watch where things land. Calmer than fast.", comment: "Slow mode footer; brand voice."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "Pace", comment: "Settings section: sort speed."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct SortStaleFilesTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Archive stale files", comment: "Settings aging."), isOn: $prefs.fileAgingEnabled)
                if prefs.fileAgingEnabled {
                    FileAgingRulesList(rules: Binding(
                        get: { prefs.fileAgingRules },
                        set: { prefs.fileAgingRules = $0 }
                    ))
                }
            } header: {
                Text(String(localized: "Stale files", comment: "Settings section: file aging."))
            } footer: {
                Text(String(localized: "Checks last opened, last used, and date added. Runs about once a day while Binky is open.", comment: "Aging footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SortRoutingTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Custom routing rules", comment: "Output settings."), isOn: $prefs.sortCustomRulesEnabled)
                if prefs.sortCustomRulesEnabled {
                    SortRulesListEditor(
                        rules: Binding(
                            get: { prefs.sortRoutingRules },
                            set: { prefs.sortRoutingRules = $0 }
                        ),
                        enableGlobalCustomRulesOnAdd: true
                    )
                        .frame(minHeight: 200)
                }
            } header: {
                Text(String(localized: "Routing", comment: "Output settings."))
            } footer: {
                Text(String(localized: "First enabled rule wins. Rules run before automatic sorted folders (Images, Documents, Review folder, etc.).", comment: "Sorted folders tab routing section footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Re-sort watched folders when rules change", comment: "Settings: auto sweep after saving routing rules."), isOn: $prefs.sortAutoRunWhenRulesChange)
                Text(String(localized: "Quiet pass across every watch root — useful when you tighten a rule and want what’s already there to move.", comment: "Auto re-sort footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "After you edit rules", comment: "Settings section."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct SortExclusionsTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    private var excludeFragmentsBinding: Binding<String> {
        Binding(
            get: { prefs.sortExcludeNameFragments.joined(separator: "\n") },
            set: { newVal in
                prefs.sortExcludeNameFragments = newVal
                    .split(whereSeparator: \.isNewline)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var globalSkipTagsCSVBinding: Binding<String> {
        Binding(
            get: { prefs.globalSkipTags.joined(separator: ", ") },
            set: { raw in
                let parts = raw
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                prefs.globalSkipTags = parts
            }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Ignored extensions (comma-separated)", comment: "Output settings."), text: $prefs.sortExcludeExtensionsCSV)
                    .textFieldStyle(.roundedBorder)
                Text(String(localized: "Example: iso, sparsebundle", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Ignored filename fragments — one per line", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: excludeFragmentsBinding)
                    .frame(minHeight: 72)
                    .font(.system(.body, design: .monospaced))
                Divider()
                LabeledContent(String(localized: "Leave files tagged:", comment: "Skip tags row label in Never sort section.")) {
                    TextField(
                        String(localized: "DoNotMove, Keep…", comment: "Skip tags placeholder."),
                        text: globalSkipTagsCSVBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                }
                Text(String(localized: "Binky won't touch any file carrying one of these Finder tags — handy for shortcuts or files you've parked on purpose.", comment: "Skip tags footer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(String(localized: "Never sort", comment: "Output settings."))
            }
        }
        .formStyle(.grouped)
    }
}

private struct SortPreviewTab: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @State private var showingPreview = false
    @State private var previewRows: [SortPreviewEntry] = []

    var body: some View {
        Form {
            Section {
                Button(String(localized: "Preview sort…", comment: "Output settings.")) {
                    Task {
                        let rows = await DownloadsSortOrchestrator.shared.previewInbox(prefs: prefs)
                        await MainActor.run {
                            previewRows = rows
                            showingPreview = true
                        }
                    }
                }
                Text(String(localized: "Shows where files in your watch folder would land. Nothing moves until you sort.", comment: "Output settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Dry run", comment: "Output settings."))
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingPreview) {
            SortPreviewSheet(rows: previewRows)
        }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @EnvironmentObject var prefs: BinkyPreferences

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Choose how much detail the organizer sidebar shows.", comment: "Appearance: organizer sidebar detail level intro."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let hasRoutines = prefs.savedPresets.contains(where: { $0.isEnabled })

                Picker(String(localized: "Sidebar style", comment: "Settings UI."), selection: Binding(
                    get: { prefs.sidebarSimpleMode },
                    set: { prefs.applySidebarSimpleMode($0) }
                )) {
                    Text(String(localized: "Simple", comment: "Settings UI: organizer sidebar style (minimal).")).tag(true)
                    Text(String(localized: "Expanded", comment: "Settings UI: organizer sidebar style (detailed).")).tag(false)
                }
                .pickerStyle(.radioGroup)
                .disabled(hasRoutines)

                if hasRoutines {
                    Text(String(localized: "Simple is unavailable while routines are configured. Expanded keeps them visible.", comment: "Settings UI: simple sidebar unavailable when routines exist."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !prefs.sidebarSimpleMode {
                    Text(String(localized: "Expanded shows both Quick Sort and Routines sections in the sidebar.", comment: "Settings UI: organizer expanded sidebar summary."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "Simple shows only the Quick Sort section.", comment: "Settings UI: organizer simple sidebar summary."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            } header: {
                Text(String(localized: "Layout", comment: "Settings UI."))
            } footer: {
                PreferencesRelatedTabLink(title: String(localized: "Open Routines…", comment: "Settings UI."), tab: .routines)
            }

            Section {
                Toggle(String(localized: "Show menu bar icon", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.showMenuBarIcon },
                    set: { newVal in
                        if !newVal, prefs.menuBarOnlyMode {
                            return
                        }
                        prefs.showMenuBarIcon = newVal
                        BinkyMenuBarController.shared.refresh()
                    }
                ))
                .disabled(prefs.menuBarOnlyMode)
                Toggle(String(localized: "Menu bar only (hide Dock icon)", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.menuBarOnlyMode },
                    set: { newVal in
                        prefs.menuBarOnlyMode = newVal
                        if newVal {
                            prefs.showMenuBarIcon = true
                        }
                        BinkyActivationPolicy.apply(menuBarOnly: newVal)
                        BinkyMenuBarController.shared.refresh()
                    }
                ))
                Text(String(localized: "Keeps watch-folder sorting awake even when the window is closed. Use the menu bar for Sort Now and History.", comment: "Settings UI: menu bar mode hint."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if prefs.menuBarOnlyMode {
                    Text(String(localized: "Menu bar icon stays on — it’s how you reach Binky without the Dock.", comment: "Settings UI: menu bar only constraint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(localized: "Menu bar", comment: "Settings UI."))
            }

            Section {
                Toggle(String(localized: "Reduce motion", comment: "Settings UI."), isOn: Binding(
                    get: { prefs.reduceMotion },
                    set: { prefs.reduceMotion = $0 }
                ))
                Text(String(localized: "Reduces expressive animation in the main window.", comment: "Settings UI."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Accessibility", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            BinkyActivationPolicy.apply(menuBarOnly: prefs.menuBarOnlyMode)
            BinkyMenuBarController.shared.refresh()
        }
    }
}

// MARK: - Folder aging rules

private struct FileAgingPreviewSheet: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    let rule: CategoryAgingRule
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [FileAgingPreviewRow] = []

    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "What would go", comment: "Aging preview sheet title."))
                .font(.title2.weight(.semibold))
            Text(String(localized: "Nothing is moved — this is a dry run.", comment: "Aging preview disclaimer."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rows.isEmpty {
                Text(String(localized: "Nothing old enough to touch yet.", comment: "Aging preview empty."))
                    .frame(minHeight: 160)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.tertiary)
            } else {
                List(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(String.localizedStringWithFormat(
                            String(localized: "Untouched about %lld days · last activity %@", comment: "Aging preview row."),
                            Int64(row.idleDays),
                            Self.rowDateFormatter.string(from: row.lastActivity)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(row.actionSummary)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button(String(localized: "Close", comment: "Dismiss aging preview.")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(minWidth: 440, minHeight: 320)
        .onAppear {
            let root = prefs.activeSortSweepRootDirectory()
            rows = FileAgingService.shared.previewCandidates(rule: rule, root: root)
        }
    }
}

private struct FileAgingRulesList: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Binding var rules: [CategoryAgingRule]
    @State private var previewingRule: CategoryAgingRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rules.isEmpty {
                Text(String(localized: "No aging rules yet. Add one per category you want swept.", comment: "Aging rules empty state."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach($rules) { $rule in
                agingRuleRow($rule)
            }
            Button(String(localized: "Add aging rule", comment: "Aging rules add button.")) {
                rules.append(CategoryAgingRule.fresh())
            }
            .buttonStyle(.bordered)
        }
        .sheet(item: $previewingRule) { rule in
            FileAgingPreviewSheet(rule: rule)
                .environmentObject(prefs)
        }
    }

    @ViewBuilder
    private func agingRuleRow(_ rule: Binding<CategoryAgingRule>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(String(localized: "Category", comment: "Aging rule category."), selection: rule.categoryRaw) {
                ForEach(FileSortCategory.allCases, id: \.rawValue) { cat in
                    Text(Self.categoryLabel(cat)).tag(cat.rawValue)
                }
            }
            Stepper(value: rule.untouchedDays, in: 1...3650) {
                Text(String.localizedStringWithFormat(
                    String(localized: "Untouched %lld days", comment: "Aging rule days."),
                    Int64(rule.wrappedValue.untouchedDays)
                ))
            }
            Picker(String(localized: "Then", comment: "Aging rule action."), selection: rule.action) {
                Text(String(localized: "Archive", comment: "Aging action.")).tag(FileAgingAction.archive)
                Text(String(localized: "Trash", comment: "Aging action.")).tag(FileAgingAction.trash)
            }
            .pickerStyle(.segmented)
            if rule.wrappedValue.action == .archive {
                TextField(
                    String(localized: "Archive subfolder", comment: "Aging archive path."),
                    text: rule.archiveFolderRelative
                )
                .textFieldStyle(.roundedBorder)
            }
            Button(String(localized: "See what would go", comment: "Aging rule dry-run preview.")) {
                previewingRule = rule.wrappedValue
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            HStack {
                Spacer()
                Button(String(localized: "Remove", comment: "Remove aging rule.")) {
                    rules.removeAll { $0.id == rule.wrappedValue.id }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private static func categoryLabel(_ category: FileSortCategory) -> String {
        switch category {
        case .images: return String(localized: "Images", comment: "Sort category.")
        case .pdf: return String(localized: "PDF", comment: "Sort category.")
        case .video: return String(localized: "Video", comment: "Sort category.")
        case .audio: return String(localized: "Audio", comment: "Sort category.")
        case .documents: return String(localized: "Documents", comment: "Sort category.")
        case .archives: return String(localized: "Archives", comment: "Sort category.")
        case .apps: return String(localized: "Apps / installers", comment: "Sort category.")
        case .screenshots: return String(localized: "Screenshots", comment: "Sort category.")
        case .misc: return String(localized: "Misc", comment: "Sort category.")
        case .review: return String(localized: "Review", comment: "Sort category.")
        case .duplicates: return String(localized: "Duplicates", comment: "Sort category.")
        case .receipts: return String(localized: "Receipts", comment: "Sort category.")
        case .folders: return String(localized: "Folders", comment: "Sort category.")
        }
    }
}

// MARK: - Routing rules (list + sheet editor)

struct RuleEditorSheetState: Identifiable {
    var draft: SortRule
    let isNew: Bool
    var id: UUID { draft.id }
}

// MARK: - Routing templates (new-rule presets)

private enum SortRoutingRuleTemplate: String, CaseIterable, Identifiable {
    case fromWebsite
    case byFileKind
    case byName
    case byFinderTag
    case installDiskImage
    case extractArchive
    case blank

    var id: String { rawValue }

    fileprivate var title: String {
        switch self {
        case .fromWebsite:
            return String(localized: "From a website", comment: "Routing rule template title.")
        case .byFileKind:
            return String(localized: "By file kind", comment: "Routing rule template title.")
        case .byName:
            return String(localized: "By name", comment: "Routing rule template title.")
        case .byFinderTag:
            return String(localized: "By Finder tag", comment: "Routing rule template title.")
        case .installDiskImage:
            return String(localized: "Install disk images", comment: "Routing rule template title.")
        case .extractArchive:
            return String(localized: "Extract archives", comment: "Routing rule template title.")
        case .blank:
            return String(localized: "Blank", comment: "Routing rule template title.")
        }
    }

    fileprivate var subtitle: String {
        switch self {
        case .fromWebsite:
            return String(localized: "Match downloads from specific sites, route into a folder.", comment: "Routing rule template subtitle.")
        case .byFileKind:
            return String(localized: "Images, PDFs, video, archives, and more.", comment: "Routing rule template subtitle.")
        case .byName:
            return String(localized: "When the filename contains certain text.", comment: "Routing rule template subtitle.")
        case .byFinderTag:
            return String(localized: "When the file already has a Finder tag.", comment: "Routing rule template subtitle.")
        case .installDiskImage:
            return String(localized: "Open .dmg installers and copy the app, then trash the image.", comment: "Routing rule template subtitle.")
        case .extractArchive:
            return String(localized: "Expand zip and similar archives into a folder.", comment: "Routing rule template subtitle.")
        case .blank:
            return String(localized: "No preset; set every field yourself.", comment: "Routing rule template subtitle.")
        }
    }

    fileprivate var symbolName: String {
        switch self {
        case .fromWebsite: return "globe"
        case .byFileKind: return "square.grid.2x2"
        case .byName: return "character.cursor.ibeam"
        case .byFinderTag: return "tag"
        case .installDiskImage: return "opticaldisc"
        case .extractArchive: return "doc.zipper"
        case .blank: return "doc"
        }
    }

    fileprivate func seededRule(order: Int) -> SortRule {
        switch self {
        case .fromWebsite:
            var r = SortRule.fresh(order: order)
            r.name = self.title
            r.originDomains = []
            r.destinationRelativePath = ""
            r.matchExtensions = []
            r.matchTags = []
            r.nameContains = ""
            r.fileKindFilter = .any
            return r
        case .byFileKind:
            var r = SortRule.fresh(order: order)
            r.name = self.title
            r.fileKindFilter = .image
            r.originDomains = []
            r.matchTags = []
            r.nameContains = ""
            r.matchExtensions = []
            r.destinationRelativePath = "Images"
            return r
        case .byName:
            var r = SortRule.fresh(order: order)
            r.name = self.title
            r.nameContains = ""
            r.destinationRelativePath = ""
            return r
        case .byFinderTag:
            var r = SortRule.fresh(order: order)
            r.name = self.title
            r.matchTags = []
            r.destinationRelativePath = ""
            return r
        case .installDiskImage:
            var r = SortRule.fresh(order: order)
            r.name = self.title
            r.matchExtensions = ["dmg"]
            r.matchAction = .installFromDMG
            r.destinationRelativePath = ""
            return r
        case .extractArchive:
            var r = SortRule.fresh(order: order)
            r.name = self.title
            r.matchExtensions = ["zip", "tar", "gz", "tgz"]
            r.matchAction = .extractAndTrash
            r.destinationRelativePath = "Archives"
            return r
        case .blank:
            return SortRule.fresh(order: order)
        }
    }
}

private struct RoutingRuleTemplatePickerSheet: View {
    let onPick: (SortRoutingRuleTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SortRoutingRuleTemplate.allCases) { tpl in
                    Button {
                        onPick(tpl)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tpl.symbolName)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .center)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tpl.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(tpl.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "New routing", comment: "Routing rules template picker title."))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Dismiss template picker.")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, minHeight: 380)
    }
}

private func ruleWhenFragment(_ rule: SortRule) -> String {
    var clauses: [String] = []
    if !rule.originDomains.isEmpty {
        let shown = rule.originDomains.prefix(2).joined(separator: ", ")
        let more = rule.originDomains.count > 2 ? String(localized: "…", comment: "Ellipsis for truncated list.") : ""
        clauses.append(String.localizedStringWithFormat(
            String(localized: "it’s from %1$@%2$@", comment: "Rule card when-fragment: download origin."),
            shown,
            more
        ))
    }
    if !rule.matchTags.isEmpty {
        clauses.append(String.localizedStringWithFormat(
            String(localized: "it has Finder tag “%@”", comment: "Rule card when-fragment."),
            rule.matchTags.joined(separator: ", ")
        ))
    }
    if !rule.nameContains.isEmpty {
        clauses.append(String.localizedStringWithFormat(
            String(localized: "the name contains “%@”", comment: "Rule card when-fragment."),
            rule.nameContains
        ))
    }
    if !rule.matchExtensions.isEmpty {
        let joined = rule.matchExtensions.map { ".\($0)" }.joined(separator: ", ")
        clauses.append(String.localizedStringWithFormat(
            String(localized: "the extension is %@",
                  comment: "Rule card when-fragment; list like .zip, .dmg."),
            joined
        ))
    }
    if rule.fileKindFilter != .any {
        let kind = rule.fileKindFilter.localizedTitle.lowercased(with: Locale.current)
        clauses.append(String.localizedStringWithFormat(
            String(localized: "it’s a %@ file", comment: "Rule card when-fragment; kind filter."),
            kind
        ))
    }
    if rule.contentMatch.kind != .none {
        clauses.append(String.localizedStringWithFormat(
            String(localized: "content matches “%@”", comment: "Rule card when-fragment."),
            rule.contentMatch.kind.localizedTitle
        ))
    }
    if let minB = rule.minSizeBytes {
        clauses.append(String.localizedStringWithFormat(
            String(localized: "size is at least %lld bytes", comment: "Rule card when-fragment."),
            minB
        ))
    }
    if let maxB = rule.maxSizeBytes {
        clauses.append(String.localizedStringWithFormat(
            String(localized: "size is at most %lld bytes", comment: "Rule card when-fragment."),
            maxB
        ))
    }
    if let pred = rule.dateAddedPredicate, pred.kind != .none {
        switch pred.kind {
        case .none:
            break
        case .newerThanDays:
            clauses.append(String.localizedStringWithFormat(
                String(localized: "Date Added is within the last %lld days", comment: "Rule card when-fragment."),
                Int64(pred.days)
            ))
        case .olderThanDays:
            clauses.append(String.localizedStringWithFormat(
                String(localized: "Date Added is more than %lld days ago", comment: "Rule card when-fragment."),
                Int64(pred.days)
            ))
        }
    }
    if clauses.isEmpty {
        return String(localized: "anything matches", comment: "Rule card when no conditions set.")
    }
    return clauses.joined(separator: String(localized: ", and ", comment: "Join rule when-clauses."))
}

private func ruleThenFragment(_ rule: SortRule) -> String {
    let dest = rule.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    let destPhrase = dest.isEmpty
        ? String(localized: "the inbox root", comment: "Rule card then-fragment: empty relative destination.")
        : dest
    switch rule.matchAction {
    case .moveToDestination:
        return String.localizedStringWithFormat(
            String(localized: "move to “%@”", comment: "Rule card then-fragment."),
            destPhrase
        )
    case .moveToTrash:
        return String(localized: "move to Trash", comment: "Rule card then-fragment.")
    case .renameInPlace:
        return String(localized: "rename in place", comment: "Rule card then-fragment.")
    case .zipToDestination:
        return String.localizedStringWithFormat(
            String(localized: "zip into “%@”", comment: "Rule card then-fragment."),
            destPhrase
        )
    case .extractAndTrash:
        return String.localizedStringWithFormat(
            String(localized: "extract into “%@”, then trash the archive", comment: "Rule card then-fragment."),
            destPhrase
        )
    case .installFromDMG:
        return String(localized: "install from the disk image", comment: "Rule card then-fragment.")
    case .tagFanout:
        return String.localizedStringWithFormat(
            String(localized: "sort by Finder tag under “%@”", comment: "Rule card then-fragment."),
            destPhrase
        )
    }
}

private func ruleCardSubtitle(_ rule: SortRule) -> String {
    String.localizedStringWithFormat(
        String(localized: "When %1$@, %2$@.", comment: "Routing rule row Zapier-style subtitle."),
        ruleWhenFragment(rule),
        ruleThenFragment(rule)
    )
}

private struct SortRulesListEditor: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @Binding var rules: [SortRule]
    var enableGlobalCustomRulesOnAdd: Bool = false
    @State private var editorSheet: RuleEditorSheetState?
    @State private var templatePickerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if rules.isEmpty {
                Text(String(localized: "No rules yet. Tap New routing to start from a template.", comment: "Routing rules empty hint."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            List {
                ForEach(Array(rules.enumerated()), id: \.element.id) { _, rule in
                    ruleRow(rule: rule)
                }
                .onMove { source, destination in
                    rules.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(minHeight: 160)
            HStack(spacing: 12) {
                Button(String(localized: "New routing", comment: "Routing rules: open template picker.")) {
                    templatePickerOpen = true
                }
                .buttonStyle(.borderedProminent)
                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $templatePickerOpen) {
            RoutingRuleTemplatePickerSheet { tpl in
                templatePickerOpen = false
                let next = rules.count + 1
                DispatchQueue.main.async {
                    editorSheet = RuleEditorSheetState(
                        draft: tpl.seededRule(order: next),
                        isNew: true
                    )
                }
            }
        }
        .sheet(item: $editorSheet) { state in
            RuleEditorSheet(
                state: state,
                onCancel: { editorSheet = nil },
                onSave: { saved in
                    if state.isNew {
                        rules.append(saved)
                        if enableGlobalCustomRulesOnAdd {
                            prefs.sortCustomRulesEnabled = true
                        }
                    } else if let idx = rules.firstIndex(where: { $0.id == saved.id }) {
                        rules[idx] = saved
                    }
                    editorSheet = nil
                }
            )
            .environmentObject(prefs)
        }
    }

    private func isEnabledBinding(for ruleID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                rules.first(where: { $0.id == ruleID })?.isEnabled ?? false
            },
            set: { newVal in
                guard let idx = rules.firstIndex(where: { $0.id == ruleID }) else { return }
                var c = rules
                c[idx].isEnabled = newVal
                rules = c
            }
        )
    }

    @ViewBuilder
    private func ruleRow(rule: SortRule) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(
                String(),
                isOn: isEnabledBinding(for: rule.id)
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(String(localized: "Enabled", comment: "Routing rule list toggle."))

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(ruleCardSubtitle(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                editorSheet = RuleEditorSheetState(draft: rule, isNew: false)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(String(localized: "Edit…", comment: "Routing rule context menu.")) {
                editorSheet = RuleEditorSheetState(draft: rule, isNew: false)
            }
            Button(String(localized: "Delete", comment: "Routing rule context menu."), role: .destructive) {
                rules.removeAll { $0.id == rule.id }
            }
        }
    }
}

struct RuleEditorSheet: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @State private var draft: SortRule
    private let isNew: Bool
    private let onCancel: () -> Void
    private let onSave: (SortRule) -> Void

    @State private var showWhenAdvanced = false
    @State private var nlPhrase: String = ""
    @State private var nlWorking: Bool = false
    @State private var nlParsedDraft: SortRule?

    @State private var scannedFolderDestinations: [String] = []
    @State private var isScanningFolderDestinations = false

    init(state: RuleEditorSheetState, onCancel: @escaping () -> Void, onSave: @escaping (SortRule) -> Void) {
        _draft = State(initialValue: state.draft)
        isNew = state.isNew
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { draft.matchExtensions.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        .replacingOccurrences(of: ".", with: "")
                }.filter { !$0.isEmpty }
                c.matchExtensions = parts
                draft = c
            }
        )
    }

    private var matchTagsBinding: Binding<String> {
        Binding(
            get: { draft.matchTags.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                c.matchTags = parts
                draft = c
            }
        )
    }

    private var outputExtensionBinding: Binding<String> {
        Binding(
            get: {
                draft.outputExtension?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ".", with: "") ?? ""
            },
            set: { raw in
                var c = draft
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
                c.outputExtension = trimmed.isEmpty ? nil : trimmed
                draft = c
            }
        )
    }

    private var addedTagsBinding: Binding<String> {
        Binding(
            get: { draft.addedTags.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                c.addedTags = parts
                draft = c
            }
        )
    }

    private var categoryDefaultReplacementTagsBinding: Binding<String> {
        Binding(
            get: { draft.categoryDefaultReplacementTags.joined(separator: ", ") },
            set: { newVal in
                var c = draft
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                c.categoryDefaultReplacementTags = parts
                draft = c
            }
        )
    }

    private var originDomainsBinding: Binding<String> {
        Binding(
            get: { draft.originDomains.joined(separator: "\n") },
            set: { newVal in
                var c = draft
                let lines = newVal.split(whereSeparator: \.isNewline).map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }.filter { !$0.isEmpty }
                c.originDomains = lines
                draft = c
            }
        )
    }

    private var contentMatchKindBinding: Binding<SortContentMatchKind> {
        Binding(
            get: { draft.contentMatch.kind },
            set: { newKind in
                var c = draft
                c.contentMatch = SortContentMatch(kind: newKind)
                draft = c
            }
        )
    }

    private func binding<T>(_ keyPath: WritableKeyPath<SortRule, T>) -> Binding<T> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newVal in
                var c = draft
                c[keyPath: keyPath] = newVal
                draft = c
            }
        )
    }

    private var minSizeBinding: Binding<String> {
        Binding(
            get: {
                if let b = draft.minSizeBytes { return "\(b)" }
                return ""
            },
            set: { raw in
                var c = draft
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                c.minSizeBytes = trimmed.isEmpty ? nil : Int64(trimmed)
                draft = c
            }
        )
    }

    private var maxSizeBinding: Binding<String> {
        Binding(
            get: {
                if let b = draft.maxSizeBytes { return "\(b)" }
                return ""
            },
            set: { raw in
                var c = draft
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                c.maxSizeBytes = trimmed.isEmpty ? nil : Int64(trimmed)
                draft = c
            }
        )
    }

    private var dateKindBinding: Binding<SortDateAddedPredicateKind> {
        Binding(
            get: { draft.dateAddedPredicate?.kind ?? .none },
            set: { newKind in
                var c = draft
                if newKind == .none {
                    c.dateAddedPredicate = nil
                } else {
                    let days = c.dateAddedPredicate?.days ?? 7
                    c.dateAddedPredicate = SortDateAddedPredicate(kind: newKind, days: max(0, days))
                }
                draft = c
            }
        )
    }

    private var dateDaysBinding: Binding<Int> {
        Binding(
            get: { draft.dateAddedPredicate?.days ?? 7 },
            set: { newDays in
                var c = draft
                let kind = c.dateAddedPredicate?.kind ?? SortDateAddedPredicateKind.olderThanDays
                guard kind != .none else { return }
                c.dateAddedPredicate = SortDateAddedPredicate(kind: kind, days: max(0, newDays))
                draft = c
            }
        )
    }

    private var topicDestinationHints: [String] {
        let others = prefs.sortRoutingRules.filter { $0.id != draft.id }
        return Self.uniqueSortedCap(Self.collectTopicHintPaths(draft: draft, otherRules: others), max: 24)
    }

    private var folderDestinationSuggestions: [String] {
        Self.uniqueSortedCap(scannedFolderDestinations, max: 40)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(String(localized: "Enabled", comment: "Rule editor."), isOn: binding(\.isEnabled))
                    TextField(String(localized: "Rule name", comment: "Rule editor."), text: binding(\.name))
                } header: {
                    Text(String(localized: "Rule", comment: "Rule editor sheet section."))
                }

                Section {
                    Picker(String(localized: "File kind", comment: "Rule editor."), selection: binding(\.fileKindFilter)) {
                        ForEach(SortFileKindFilter.allCases) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                    TextField(String(localized: "Filename contains", comment: "Rule editor."), text: binding(\.nameContains))
                        .textFieldStyle(.roundedBorder)
                    TextField(String(localized: "Has Finder tag (comma-separated, any match)", comment: "Rule editor: tag predicate."), text: matchTagsBinding)
                        .textFieldStyle(.roundedBorder)
                    DisclosureGroup(isExpanded: $showWhenAdvanced) {
                        TextField(String(localized: "Extensions (comma-separated, empty = any)", comment: "Rule editor."), text: extensionsBinding)
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Downloaded from — one host per line (*.stripe.com, figma.com)", comment: "Rule editor where-froms."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextEditor(text: originDomainsBinding)
                            .frame(minHeight: 52)
                            .font(.system(.body, design: .monospaced))
                        Picker(String(localized: "Content match", comment: "Rule editor."), selection: contentMatchKindBinding) {
                            ForEach(SortContentMatchKind.allCases) { kind in
                                Text(kind.localizedTitle).tag(kind)
                            }
                        }
                        HStack {
                            TextField(String(localized: "Min size (bytes)", comment: "Rule editor."), text: minSizeBinding)
                                .textFieldStyle(.roundedBorder)
                            TextField(String(localized: "Max size (bytes)", comment: "Rule editor."), text: maxSizeBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                        Picker(String(localized: "Date added", comment: "Rule editor."), selection: dateKindBinding) {
                            Text(String(localized: "Ignore", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.none)
                            Text(String(localized: "Added within last … days", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.newerThanDays)
                            Text(String(localized: "Added more than … days ago", comment: "Rule editor.")).tag(SortDateAddedPredicateKind.olderThanDays)
                        }
                        if let predicate = draft.dateAddedPredicate, predicate.kind != .none {
                            Stepper(value: dateDaysBinding, in: 0...3650) {
                                Text(String.localizedStringWithFormat(String(localized: "Days: %lld", comment: "Rule editor."), Int64(dateDaysBinding.wrappedValue)))
                            }
                        }
                    } label: {
                        Text(String(localized: "More conditions", comment: "Rule editor: disclose extensions origins etc."))
                    }
                } header: {
                    Text(String(localized: "When", comment: "Rule editor: conditions section."))
                } footer: {
                    Text(String(localized: "Runs before automatic destinations. Add extensions, sites, or size rules only if you need them.", comment: "Rule editor When footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker(String(localized: "Action", comment: "Rule editor: what happens when rule matches."), selection: binding(\.matchAction)) {
                        ForEach(SortRuleMatchAction.allCases) { action in
                            Text(action.localizedTitle).tag(action)
                        }
                    }
                    .accessibilityHint(String(localized: "Move, extract, install a disk image, fan out by tag, zip, trash, or rename in place.", comment: "VoiceOver: rule action picker."))
                    // Warn when the user picks extractAndTrash but the matched extensions include
                    // formats Binky can't extract (no bundled unrar/7z — only zip/tar/gz/bz2/xz).
                    if draft.matchAction == .extractAndTrash {
                        let unsupported = Set(draft.matchExtensions.map { $0.lowercased() }).intersection(["rar", "7z", "7zip", "lzh", "cab"])
                        if !unsupported.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text(String.localizedStringWithFormat(
                                    String(localized: "Binky can't extract %@ files. These will be skipped at sort time.", comment: "Rule editor warning: unsupported archive format list."),
                                    unsupported.sorted().joined(separator: ", ")
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            TextField(String(localized: "Destination (relative to watch folder)", comment: "Rule editor."), text: binding(\.destinationRelativePath))
                                .textFieldStyle(.roundedBorder)
                            destinationSuggestPathMenu
                            Button(String(localized: "Choose…", comment: "Rule editor: pick destination folder.")) {
                                pickDestinationFolder()
                            }
                        }
                        if isScanningFolderDestinations {
                            Text(String(localized: "Scanning folders…", comment: "Rule editor: scanning watch tree for paths."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if DinkyBridge.isInstalled {
                        Button(String(localized: "Watch in Dinky →", comment: "Routing rule: open destination in Dinky.")) {
                            let trimmed = draft.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
                            let root = prefs.activeSortSweepRootDirectory()
                            let folder = trimmed.isEmpty ? root : root.appendingPathComponent(trimmed, isDirectory: true)
                            _ = DinkyBridge.openFolder(folder)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(binkyTintColor)
                        .accessibilityLabel(String(localized: "Open sorted folder in Dinky", comment: "VoiceOver routing rule helper."))
                    }
                } header: {
                    Text(String(localized: "Then", comment: "Rule editor: action and destination."))
                } footer: {
                    Text(String(localized: "Trash and some actions ignore the destination path. Suggest path combines topic-style segments (sites, tags, other rules) with folders already under your watch folder—one folder can hold any file types.", comment: "Rule Then footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Picker(String(localized: "Rename", comment: "Rule editor."), selection: binding(\.renameStyle)) {
                        ForEach(SortRenameStyle.allCases) { style in
                            Text(style.localizedTitle).tag(style)
                        }
                    }
                    if draft.renameStyle == .template {
                        TextField("{date} {stem}{ext}", text: binding(\.renameTemplate))
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Tokens: {date}, {stem}, {ext}, {newExt}, {n}, {origin}, {ocr}, {vendor}, {amount}", comment: "Rule editor rename hint."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    TextField(String(localized: "Force extension (e.g. md, leave empty to keep)", comment: "Rule editor: output file extension."), text: outputExtensionBinding)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text(String(localized: "Rename", comment: "Rule editor sheet section."))
                }

                Section {
                    TextField(String(localized: "Tags on match (comma-separated)", comment: "Rule editor."), text: addedTagsBinding)
                        .textFieldStyle(.roundedBorder)
                    Picker(String(localized: "Category tags when this rule matches", comment: "Rule editor: Finder tag policy."), selection: binding(\.finderTagPolicy)) {
                        Text(String(localized: "Use defaults for file type", comment: "Rule editor: additive Finder tag policy.")).tag(SortRuleFinderTagPolicy.additive)
                        Text(String(localized: "Replace type defaults", comment: "Rule editor: replace category Finder tags.")).tag(SortRuleFinderTagPolicy.replaceCategoryDefault)
                    }
                    if draft.finderTagPolicy == .replaceCategoryDefault {
                        TextField(String(localized: "Replacement tags (comma-separated)", comment: "Rule editor: tags that replace category defaults."), text: categoryDefaultReplacementTagsBinding)
                            .textFieldStyle(.roundedBorder)
                        Text(String(localized: "Replaces only the type-based tags. Routine tags and “Tags on match” still apply after.", comment: "Rule editor: replace tags hint."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text(String(localized: "Tags", comment: "Rule editor sheet section."))
                }

                Section {
                    DisclosureGroup {
                        TextField(
                            String(localized: "Describe in plain language (e.g. from figma.com to Design/Figma)", comment: "NL rule placeholder."),
                            text: $nlPhrase
                        )
                        .textFieldStyle(.roundedBorder)
                        HStack(spacing: 12) {
                            Button(String(localized: "Generate", comment: "Apply natural language to rule fields.")) {
                                generateFromPhrase()
                            }
                            .disabled(nlPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nlWorking)
                            if nlWorking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Spacer(minLength: 0)
                        }
                        if #unavailable(macOS 26.0) {
                            Text(String(localized: "On macOS 26, Generate can use on-device models when available. Earlier macOS still fills the form with phrase heuristics.", comment: "NL availability hint in rule sheet."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let pending = nlParsedDraft {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(String(localized: "Here’s what Binky heard.", comment: "NL rule parse preview header."))
                                    .font(.subheadline.weight(.semibold))
                                Text(RuleEditorSheet.nlPreviewDetailLines(pending))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 12) {
                                    Button(String(localized: "Looks right. Apply it.", comment: "Apply NL parse to editor form.")) {
                                        applyNLProposed(pending)
                                    }
                                    .keyboardShortcut(.defaultAction)
                                    Button(String(localized: "Dismiss", comment: "Dismiss NL parse preview.")) {
                                        nlParsedDraft = nil
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        Text(String(localized: "Quick phrase (experimental)", comment: "Collapsed NL rule section title."))
                    }
                } footer: {
                    Text(String(localized: "Optional shortcut. You can still edit every field afterward.", comment: "NL section footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                isNew
                    ? String(localized: "New rule", comment: "Rule editor sheet title.")
                    : String(localized: "Edit rule", comment: "Rule editor sheet title.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Rule editor sheet.")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", comment: "Rule editor sheet.")) { onSave(draft) }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .task {
            await scanFolderDestinationsUnderWatchRoot()
        }
    }

    @ViewBuilder
    private var destinationSuggestPathMenu: some View {
        Menu {
            if !topicDestinationHints.isEmpty {
                Section(String(localized: "Topic-style", comment: "Destination suggestions section: inferred topic paths.")) {
                    ForEach(topicDestinationHints, id: \.self) { path in
                        Button(path) { applySuggestedDestination(path) }
                    }
                }
            }
            if !folderDestinationSuggestions.isEmpty {
                Section(String(localized: "Existing folders", comment: "Destination suggestions section: watch subtree.")) {
                    ForEach(folderDestinationSuggestions, id: \.self) { path in
                        Button(path) { applySuggestedDestination(path) }
                    }
                }
            }
            if topicDestinationHints.isEmpty && folderDestinationSuggestions.isEmpty && !isScanningFolderDestinations {
                Text(String(localized: "No suggestions yet. Add a site under More conditions, or rescan.", comment: "Empty destination suggestions."))
                    .foregroundStyle(.secondary)
            }
            Button(String(localized: "Rescan folders", comment: "Refresh folder list for destination suggestions.")) {
                Task { await scanFolderDestinationsUnderWatchRoot() }
            }
        } label: {
            Label(String(localized: "Suggest", comment: "Rule editor: open destination path suggestions."), systemImage: "sparkles")
        }
        .controlSize(.regular)
        .menuIndicator(.visible)
        .accessibilityHint(String(localized: "Shows topic paths and folders under the watch folder.", comment: "VoiceOver: destination suggest menu."))
    }

    private func applySuggestedDestination(_ path: String) {
        draft.destinationRelativePath = path
    }

    private func scanFolderDestinationsUnderWatchRoot() async {
        isScanningFolderDestinations = true
        let root = prefs.activeSortSweepRootDirectory().standardizedFileURL
        let paths = await Task.detached {
            Self.enumerateRelativeDirectoryPaths(under: root, maxDepth: 4, maxItems: 220)
        }.value
        scannedFolderDestinations = paths
        isScanningFolderDestinations = false
    }

    private func pickDestinationFolder() {
        let root = prefs.activeSortSweepRootDirectory().standardizedFileURL
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        let rel = draft.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if rel.isEmpty {
            panel.directoryURL = root
        } else {
            let hinted = root.appendingPathComponent(rel, isDirectory: true)
            panel.directoryURL = FileManager.default.fileExists(atPath: hinted.path) ? hinted : root
        }
        panel.prompt = String(localized: "Choose folder", comment: "NSOpenPanel prompt for rule destination.")
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                guard let relPath = Self.relativePath(under: root, for: url) else {
                    NSSound.beep()
                    return
                }
                draft.destinationRelativePath = relPath
            }
        }
    }

    private nonisolated static func relativePath(under root: URL, for chosen: URL) -> String? {
        let r = root.standardizedFileURL.path
        let f = chosen.standardizedFileURL.path
        guard f.hasPrefix(r) else { return nil }
        if f == r { return "" }
        let prefix = r.hasSuffix("/") ? r : r + "/"
        guard f.hasPrefix(prefix) else { return nil }
        return String(f.dropFirst(prefix.count))
    }

    private nonisolated static func enumerateRelativeDirectoryPaths(under root: URL, maxDepth: Int, maxItems: Int) -> [String] {
        let fm = FileManager.default
        var collected: [String] = []
        func visit(_ url: URL, depth: Int) {
            guard collected.count < maxItems else { return }
            if depth > 0 {
                if let rel = relativePath(under: root, for: url), !rel.isEmpty {
                    collected.append(rel)
                }
            }
            guard depth < maxDepth else { return }
            guard collected.count < maxItems else { return }
            guard let kids = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            let dirs = kids.filter { u in
                (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
            for u in dirs {
                visit(u, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return collected.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func collectTopicHintPaths(draft: SortRule, otherRules: [SortRule]) -> [String] {
        var out: [String] = []
        for line in draft.originDomains {
            if let s = topicFolderSlug(fromOriginLine: line) { out.append(s) }
        }
        for rawTag in draft.matchTags {
            let t = sanitizePathSegment(rawTag)
            if !t.isEmpty { out.append(t) }
        }
        if draft.name.contains("/") {
            if let p = sanitizeRelativePathFromName(draft.name) { out.append(p) }
        }
        for r in otherRules {
            let d = r.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !d.isEmpty { out.append(d) }
            for line in r.originDomains {
                if let s = topicFolderSlug(fromOriginLine: line) { out.append(s) }
            }
            for rawTag in r.matchTags {
                let t = sanitizePathSegment(rawTag)
                if !t.isEmpty { out.append(t) }
            }
        }
        return out
    }

    private static func topicFolderSlug(fromOriginLine line: String) -> String? {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("*.") { s.removeFirst(2) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        let parts = s.split { $0 == "." || $0 == ":" }.map(String.init).filter { !$0.isEmpty }
        guard let head = parts.first else { return nil }
        if Int(head) != nil { return nil }
        guard head != "com", head != "org", head != "net", head != "io", head != "app", head != "co", head != "edu", head != "gov" else { return nil }
        let cap = sanitizePathSegment(head.capitalized)
        return cap.isEmpty ? nil : cap
    }

    private static func sanitizePathSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeRelativePathFromName(_ raw: String) -> String? {
        let parts = raw.split(separator: "/").map { sanitizePathSegment(String($0)) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "/")
    }

    private static func uniqueSortedCap(_ paths: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for p in paths {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = t.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(t)
        }
        let sorted = unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if sorted.count <= max { return sorted }
        return Array(sorted.prefix(max))
    }

    private func generateFromPhrase() {
        Task {
            nlWorking = true
            defer { nlWorking = false }
            let built = await RuleSynthesizer.synthesize(from: nlPhrase, order: 1)
            await MainActor.run {
                nlParsedDraft = built
            }
        }
    }

    private func applyNLProposed(_ proposed: SortRule) {
        var merged = proposed
        merged.id = draft.id
        draft = merged
        nlParsedDraft = nil
        nlPhrase = ""
    }

    private static func nlPreviewDetailLines(_ rule: SortRule) -> String {
        var lines: [String] = []
        lines.append(String.localizedStringWithFormat(String(localized: "Name: %@", comment: "NL preview field."), rule.name))
        if rule.originDomains.isEmpty {
            lines.append(String(localized: "From: any", comment: "NL preview field."))
        } else {
            lines.append(String.localizedStringWithFormat(
                String(localized: "From: %@", comment: "NL preview field."),
                rule.originDomains.joined(separator: ", ")
            ))
        }
        lines.append(String.localizedStringWithFormat(
            String(localized: "Then: %@", comment: "NL preview: rule match action."),
            rule.matchAction.localizedTitle
        ))
        let dest = rule.destinationRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(String.localizedStringWithFormat(
            String(localized: "Goes to: %@", comment: "NL preview field."),
            dest.isEmpty ? String(localized: "(not set)", comment: "NL preview empty destination.") : dest
        ))
        lines.append(String.localizedStringWithFormat(
            String(localized: "File kind: %@", comment: "NL preview field."),
            rule.fileKindFilter.localizedTitle
        ))
        lines.append(String.localizedStringWithFormat(
            String(localized: "Content: %@", comment: "NL preview field."),
            rule.contentMatch.kind.localizedTitle
        ))
        if !rule.matchTags.isEmpty {
            lines.append(String.localizedStringWithFormat(
                String(localized: "Finder tags: %@", comment: "NL preview field."),
                rule.matchTags.joined(separator: ", ")
            ))
        }
        if let ext = rule.outputExtension?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ext.replacingOccurrences(of: ".", with: "").isEmpty {
            lines.append(String.localizedStringWithFormat(
                String(localized: "Output extension: .%@", comment: "NL preview field."),
                ext.replacingOccurrences(of: ".", with: "")
            ))
        }
        return lines.joined(separator: "\n")
    }
}
// MARK: - Routines (organizer)

private enum RoutineTemplate: String, CaseIterable, Hashable {
    case blank
    case sortDownloads
    case calmDesktop
    case autoInstallDMG
    case autoExtractArchives
    case sortByFinderTag
    case archiveScreenshots
    case emailToObsidian

    fileprivate static let pendingUserDefaultsKey = "binky.pendingRoutineTemplate"

    /// Staged before opening the Routines pane so ``RoutinesOrganizerTab`` can create on appear.
    fileprivate static func stagePending(_ template: RoutineTemplate) {
        UserDefaults.standard.set(template.rawValue, forKey: pendingUserDefaultsKey)
    }

    fileprivate static func consumePending() -> RoutineTemplate? {
        guard let raw = UserDefaults.standard.string(forKey: pendingUserDefaultsKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingUserDefaultsKey)
        return RoutineTemplate(rawValue: raw)
    }

    fileprivate var suggestedRoutineName: String {
        switch self {
        case .blank:
            return String(localized: "New routine", comment: "Default name for blank routine.")
        case .sortDownloads:
            return String(localized: "Sort my Downloads", comment: "Routine template name.")
        case .calmDesktop:
            return String(localized: "Calm my Desktop", comment: "Routine template name.")
        case .autoInstallDMG:
            return String(localized: "Auto-install DMGs", comment: "Routine template name.")
        case .autoExtractArchives:
            return String(localized: "Auto-extract archives", comment: "Routine template name.")
        case .sortByFinderTag:
            return String(localized: "Sort by Finder tag", comment: "Routine template name.")
        case .archiveScreenshots:
            return String(localized: "Archive old screenshots", comment: "Routine template name.")
        case .emailToObsidian:
            return String(localized: "Notes to Obsidian", comment: "Routine template name.")
        }
    }
}

private struct RoutinesOrganizerTab: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @State private var selectedPresetID: UUID?
    @State private var newCustomTagDraft: String = ""
    @State private var confirmDeleteProfile = false

    private static let newTagExpiryChoices = [0, 1, 3, 7, 14, 30]

    private var selectedPresetIndex: Int? {
        guard let id = selectedPresetID else { return nil }
        return prefs.savedPresets.firstIndex { $0.id == id }
    }

    private var canDeleteSelected: Bool {
        prefs.savedPresets.count > 1 && selectedPresetIndex != nil
    }

    var body: some View {
        Form {
            Section(String(localized: "Routines", comment: "Routines list header.")) {
                ForEach(Array(prefs.savedPresets.enumerated()), id: \.element.id) { _, preset in
                    profileListRow(preset)
                }

                Button {
                    createNewRoutine(.blank)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .frame(width: 16, alignment: .center)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Add routine", comment: "Routines list: add row."))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                HStack(spacing: 18) {
                    profileToolbarButton(
                        systemImage: "plus",
                        title: String(localized: "Add", comment: "Added automation toolbar: create.")
                    ) {
                        createNewRoutine(.blank)
                    }

                    Menu {
                        Button(String(localized: "Blank routine", comment: "Routine template.")) {
                            createNewRoutine(.blank)
                        }
                        Button(String(localized: "Sort my Downloads", comment: "Routine template.")) {
                            createNewRoutine(.sortDownloads)
                        }
                        Button(String(localized: "Calm my Desktop", comment: "Routine template.")) {
                            createNewRoutine(.calmDesktop)
                        }
                        Button(String(localized: "Auto-install DMGs", comment: "Routine template.")) {
                            createNewRoutine(.autoInstallDMG)
                        }
                        Button(String(localized: "Auto-extract archives", comment: "Routine template.")) {
                            createNewRoutine(.autoExtractArchives)
                        }
                        Button(String(localized: "Sort by Finder tag", comment: "Routine template.")) {
                            createNewRoutine(.sortByFinderTag)
                        }
                        Button(String(localized: "Archive old screenshots", comment: "Routine template.")) {
                            createNewRoutine(.archiveScreenshots)
                        }
                        Button(String(localized: "Notes to Obsidian", comment: "Routine template; txt → md style routing.")) {
                            createNewRoutine(.emailToObsidian)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                            Text(String(localized: "Templates", comment: "Routine templates menu."))
                        }
                    }
                    .menuStyle(.borderlessButton)

                    profileToolbarButton(
                        systemImage: "doc.on.doc",
                        title: String(localized: "Duplicate", comment: "Routines toolbar: duplicate.")
                    ) {
                        duplicateSelectedProfile()
                    }
                    .disabled(selectedPresetIndex == nil)

                    profileToolbarButton(
                        systemImage: "trash",
                        title: String(localized: "Delete", comment: "Routines toolbar: delete.")
                    ) {
                        confirmDeleteProfile = true
                    }
                    .disabled(!canDeleteSelected)

                    Spacer(minLength: 0)
                }
            }

            if let idx = selectedPresetIndex {
                Section(String(localized: "Name", comment: "Routine editor section.")) {
                    TextField(
                        String(localized: "Routine name", comment: "Routine editor: name field."),
                        text: profileNameBinding(presetIndex: idx)
                    )
                    .textFieldStyle(.roundedBorder)
                }

                Section(String(localized: "When", comment: "Routine source folder section.")) {
                    Toggle(String(localized: "Enable this routine", comment: "Routine on."), isOn: isEnabledBinding(presetIndex: idx))
                    HStack {
                        Text(prefs.savedPresets[idx].watchFolderPath.isEmpty
                             ? String(localized: "No folder selected", comment: "Routine: watch path empty.")
                             : URL(fileURLWithPath: prefs.savedPresets[idx].watchFolderPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Pick routine source folder.")) {
                            pickWatchFolder(presetIndex: idx)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(String(localized: "Binky watches here and runs the rules below. Different folder than the default? That’s the point.", comment: "Routine watch hint; brand voice."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(String(localized: "Install from disk images", comment: "DMG install target section.")) {
                    HStack {
                        Text(applicationsInstallSummary(presetIndex: idx))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…", comment: "Pick Applications folder for DMG installs.")) {
                            pickApplicationsInstallFolder(presetIndex: idx)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(String(localized: "Rules that “Install app from disk image” copy .app bundles here. Leave default for ~/Applications.", comment: "DMG install hint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(String(localized: "Tag fan-out priority", comment: "Tag priority for fan-out rules.")) {
                    TextField(
                        String(localized: "Comma-separated tag names (first match wins)", comment: "Tag priority placeholder."),
                        text: tagFanoutPriorityCSVBinding(presetIndex: idx)
                    )
                    .textFieldStyle(.roundedBorder)
                    Text(String(localized: "Used when a rule sends files into subfolders by Finder tag.", comment: "Tag priority footer."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(String(localized: "Default tags by type", comment: "Routine editor: per-category Finder tag overrides.")) {
                    Text(String(localized: "Overrides global defaults for files sorted under this automation. Leave blank to inherit.", comment: "Per-type tag hint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FinderTagDefaultsByCategoryMapEditor(map: finderTagDefaultsBinding(presetIndex: idx))
                }

                Section(String(localized: "Custom tags", comment: "Routine editor section: custom Finder tags.")) {
                    if prefs.savedPresets[idx].customFinderTags.isEmpty {
                        Text(String(localized: "No custom tags. Sorted files only get Binky's category tags.", comment: "Routine editor: no custom tags."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(prefs.savedPresets[idx].customFinderTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button(String(localized: "Remove", comment: "Routine editor: remove custom Finder tag.")) {
                                removeCustomTag(tag, presetIndex: idx)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        TextField(
                            String(localized: "Tag name", comment: "Routine editor: add custom Finder tag placeholder."),
                            text: $newCustomTagDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        Button(String(localized: "Add", comment: "Routine editor: add custom Finder tag.")) {
                            addCustomTag(presetIndex: idx)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section(String(localized: "\u{201C}New\u{201D} tag expiry", comment: "Routine editor section: New tag expiry.")) {
                    Picker(
                        String(localized: "Expires after", comment: "Routine editor: New tag expiry picker."),
                        selection: newTagExpiryBinding(presetIndex: idx)
                    ) {
                        ForEach(Self.newTagExpiryChoices, id: \.self) { days in
                            Text(newTagExpiryChoiceLabel(days)).tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(String(localized: "Sort rules", comment: "Routine editor section: sort rules.")) {
                    if prefs.savedPresets[idx].sortRules.isEmpty {
                        Text(String(localized: "No rules. Binky uses default sorted folders.", comment: "Routine editor: empty rules."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(String(localized: "When this routine has rules, they apply to files from its source folder (combined with other routines on the same path in list order).", comment: "Routine editor: rules hint."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SortRulesListEditor(rules: sortRulesBinding(presetIndex: idx))
                        .frame(minHeight: 200)
                }

                Section(String(localized: "After sorting", comment: "Routine editor section: post-sort shortcut.")) {
                    TextField(
                        String(localized: "Shortcut name (e.g. \u{201C}Notify Slack\u{201D})", comment: "Routine editor: post-sort shortcut."),
                        text: postSortShortcutBinding(presetIndex: idx)
                    )
                    .textFieldStyle(.roundedBorder)
                    Text(String(localized: "Runs this Shortcut with the moved file as input.", comment: "Routine editor: shortcut hint."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncSelectedPresetSelection()
            if let pending = RoutineTemplate.consumePending() {
                createNewRoutine(pending)
            }
        }
        .onChange(of: prefs.savedPresets.map(\.id)) { _, _ in
            syncSelectedPresetSelection()
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $confirmDeleteProfile,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete", comment: "Routine editor: confirm delete."), role: .destructive) {
                deleteSelectedProfile()
            }
            Button(String(localized: "Cancel", comment: "Routine editor: cancel delete."), role: .cancel) {}
        }
    }

    private var deleteConfirmationTitle: String {
        guard let idx = selectedPresetIndex else {
            return String(localized: "Delete routine?", comment: "Routine editor: generic delete title.")
        }
        return String.localizedStringWithFormat(
            String(localized: "Delete \u{201C}%@\u{201D}?", comment: "Routine editor: delete title."),
            prefs.savedPresets[idx].name
        )
    }

    @ViewBuilder
    private func profileListRow(_ preset: Inbox) -> some View {
        let isSelected = preset.id == selectedPresetID
        Button {
            selectedPresetID = preset.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(preset.organizerListSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(binkyTintColor)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preset.name). \(preset.organizerListSubtitle)\(isSelected ? ", selected" : "")")
    }

    private func profileToolbarButton(
        systemImage: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(binkyTintColor)
    }

    private func syncSelectedPresetSelection() {
        guard !prefs.savedPresets.isEmpty else {
            selectedPresetID = nil
            return
        }
        if selectedPresetID == nil || !prefs.savedPresets.contains(where: { $0.id == selectedPresetID }) {
            if let activeID = UUID(uuidString: prefs.activePresetID),
               prefs.savedPresets.contains(where: { $0.id == activeID }) {
                selectedPresetID = activeID
            } else {
                selectedPresetID = prefs.savedPresets.first?.id
            }
        }
    }

    private func createNewRoutine(_ template: RoutineTemplate) {
        var copy = prefs.savedPresets
        let baseName = template.suggestedRoutineName
        let name = uniqueRoutineName(
            baseName: baseName,
            existingNames: Set(copy.map(\.name))
        )
        var preset = Inbox(name: name)
        apply(template, to: &preset)
        copy.append(preset)
        prefs.savedPresets = copy
        selectedPresetID = preset.id
    }

    /// Applies template defaults (paths, starter rules). Caller sets name and appends to `savedPresets`.
    private func apply(_ template: RoutineTemplate, to preset: inout Inbox) {
        func bookmarkDirectory(_ url: URL) {
            let normalized = url.standardizedFileURL
            preset.watchFolderPath = normalized.path
            preset.watchFolderBookmark = (try? normalized.bookmarkData(options: .withSecurityScope)) ?? Data()
        }

        switch template {
        case .blank:
            break

        case .sortDownloads:
            preset.isEnabled = true
            let dl = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            bookmarkDirectory(dl)

        case .calmDesktop:
            preset.isEnabled = true
            let desk = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop", isDirectory: true)
            bookmarkDirectory(desk)
            mergeGlobalSkipTag("DoNotMove")

        case .autoInstallDMG:
            preset.isEnabled = true
            let dl = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            bookmarkDirectory(dl)
            var rule = SortRule.fresh(order: 1)
            rule.name = String(localized: "Install disk images", comment: "Starter rule for DMG template.")
            rule.matchExtensions = ["dmg"]
            rule.matchAction = .installFromDMG
            rule.destinationRelativePath = FileSortCategory.apps.downloadsSubfolder
            preset.sortRules = [rule]

        case .autoExtractArchives:
            preset.isEnabled = true
            let dl = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            bookmarkDirectory(dl)
            var rule = SortRule.fresh(order: 1)
            rule.name = String(localized: "Unpack archives", comment: "Starter rule for extract template.")
            rule.fileKindFilter = .archive
            rule.matchAction = .extractAndTrash
            rule.destinationRelativePath = FileSortCategory.archives.downloadsSubfolder
            preset.sortRules = [rule]

        case .sortByFinderTag:
            preset.isEnabled = true
            let dl = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            bookmarkDirectory(dl)
            var rule = SortRule.fresh(order: 1)
            rule.name = String(localized: "Fan out by tag", comment: "Starter rule for tag fan-out template.")
            rule.matchAction = .tagFanout
            rule.destinationRelativePath = "By tag"
            preset.sortRules = [rule]

        case .archiveScreenshots:
            preset.isEnabled = true
            let dl = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            bookmarkDirectory(dl)
            var r1 = SortRule.fresh(order: 1)
            r1.name = String(localized: "Old Screen Shot images", comment: "Screenshot archive rule name.")
            r1.fileKindFilter = .image
            r1.nameContains = "Screen Shot"
            r1.dateAddedPredicate = SortDateAddedPredicate(kind: .olderThanDays, days: 30)
            r1.destinationRelativePath = "Archive/Screenshots"
            var r2 = SortRule.fresh(order: 2)
            r2.name = String(localized: "Old Screenshot images", comment: "Screenshot archive rule name (alternate spelling).")
            r2.fileKindFilter = .image
            r2.nameContains = "Screenshot"
            r2.dateAddedPredicate = SortDateAddedPredicate(kind: .olderThanDays, days: 30)
            r2.destinationRelativePath = "Archive/Screenshots"
            preset.sortRules = [r1, r2]

        case .emailToObsidian:
            preset.isEnabled = true
            let dl = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            bookmarkDirectory(dl)
            var rule = SortRule.fresh(order: 1)
            rule.name = String(localized: "Plain text to Markdown", comment: "Starter rule for notes template.")
            rule.matchExtensions = ["txt"]
            rule.outputExtension = "md"
            rule.renameStyle = .template
            rule.renameTemplate = "{stem}{ext}"
            rule.destinationRelativePath = "Obsidian Inbox"
            rule.matchAction = .moveToDestination
            preset.sortRules = [rule]
        }
    }

    private func mergeGlobalSkipTag(_ tag: String) {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var tags = prefs.globalSkipTags
        guard !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        tags.append(t)
        prefs.globalSkipTags = tags
    }

    private func duplicateSelectedProfile() {
        guard let idx = selectedPresetIndex else { return }
        var copy = prefs.savedPresets
        let source = copy[idx]
        let name = Inbox.uniqueDuplicatePresetName(
            baseName: source.name,
            existingNames: Set(copy.map(\.name))
        )
        let duplicated = Inbox(duplicating: source, name: name)
        copy.append(duplicated)
        prefs.savedPresets = copy
        selectedPresetID = duplicated.id
    }

    private func deleteSelectedProfile() {
        guard prefs.savedPresets.count > 1, let id = selectedPresetID else { return }
        var copy = prefs.savedPresets
        copy.removeAll { $0.id == id }
        prefs.savedPresets = copy
        selectedPresetID = copy.first?.id
        // If the deleted profile was active, fall back to the first remaining profile.
        if prefs.activePresetID == id.uuidString {
            prefs.activePresetID = copy.first?.id.uuidString ?? ""
        }
    }

    private func uniqueRoutineName(baseName: String, existingNames: Set<String>) -> String {
        if !existingNames.contains(baseName) {
            return baseName
        }
        var index: Int64 = 2
        while true {
            let candidate = String.localizedStringWithFormat(
                String(localized: "%1$@ %2$lld", comment: "Auto-generated automation name with numeric suffix."),
                baseName,
                index
            )
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func sortRulesBinding(presetIndex: Int) -> Binding<[SortRule]> {
        Binding(
            get: { prefs.savedPresets[presetIndex].sortRules },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].sortRules = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func finderTagDefaultsBinding(presetIndex: Int) -> Binding<[String: [String]]> {
        Binding(
            get: { prefs.savedPresets[presetIndex].finderTagDefaultsByCategory },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].finderTagDefaultsByCategory = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func profileNameBinding(presetIndex: Int) -> Binding<String> {
        Binding(
            get: { prefs.savedPresets[presetIndex].name },
            set: { newVal in
                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                var copy = prefs.savedPresets
                copy[presetIndex].name = trimmed
                prefs.savedPresets = copy
            }
        )
    }

    private func newTagExpiryBinding(presetIndex: Int) -> Binding<Int> {
        Binding(
            get: {
                let v = prefs.savedPresets[presetIndex].newTagExpiryDays
                return Self.newTagExpiryChoices.contains(v) ? v : 0
            },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].newTagExpiryDays = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func postSortShortcutBinding(presetIndex: Int) -> Binding<String> {
        Binding(
            get: { prefs.savedPresets[presetIndex].postSortShortcutName },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].postSortShortcutName = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private var globalSkipTagsCSVBinding: Binding<String> {
        Binding(
            get: { prefs.globalSkipTags.joined(separator: ", ") },
            set: { raw in
                let parts = raw
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                prefs.globalSkipTags = parts
            }
        )
    }

    private func isEnabledBinding(presetIndex: Int) -> Binding<Bool> {
        Binding(
            get: { prefs.savedPresets[presetIndex].isEnabled },
            set: { newVal in
                var copy = prefs.savedPresets
                copy[presetIndex].isEnabled = newVal
                prefs.savedPresets = copy
            }
        )
    }

    private func tagFanoutPriorityCSVBinding(presetIndex: Int) -> Binding<String> {
        Binding(
            get: { prefs.savedPresets[presetIndex].tagFanoutPriority.joined(separator: ", ") },
            set: { raw in
                let parts = raw
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                var copy = prefs.savedPresets
                copy[presetIndex].tagFanoutPriority = parts
                prefs.savedPresets = copy
            }
        )
    }

    private func applicationsInstallSummary(presetIndex: Int) -> String {
        let url = prefs.savedPresets[presetIndex].resolvedApplicationsInstallDirectory()
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homeApps = (home as NSString).appendingPathComponent("Applications")
        if path == homeApps {
            return String(localized: "~/Applications (default)", comment: "DMG install target summary.")
        }
        if path == "/Applications" {
            return "/Applications"
        }
        return url.path
    }

    private func pickGlobalDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose folder", comment: "Open panel: choose global default folder.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.watchedFolderPath = url.path
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            prefs.watchedFolderBookmark = bookmark
        }
    }

    private func pickApplicationsInstallFolder(presetIndex: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose Applications folder", comment: "Open panel for DMG install target.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var copy = prefs.savedPresets
        copy[presetIndex].applicationsInstallPath = url.path
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            copy[presetIndex].applicationsInstallBookmark = bookmark
        }
        prefs.savedPresets = copy
    }

    private func pickWatchFolder(presetIndex: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose source folder", comment: "Open panel: automation source folder.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var copy = prefs.savedPresets
        copy[presetIndex].watchFolderPath = url.path
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            copy[presetIndex].watchFolderBookmark = bookmark
        }
        prefs.savedPresets = copy
    }

    private func addCustomTag(presetIndex: Int) {
        let trimmed = newCustomTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = prefs.savedPresets
        if copy[presetIndex].customFinderTags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            newCustomTagDraft = ""
            return
        }
        copy[presetIndex].customFinderTags.append(trimmed)
        prefs.savedPresets = copy
        newCustomTagDraft = ""
    }

    private func removeCustomTag(_ tag: String, presetIndex: Int) {
        var copy = prefs.savedPresets
        copy[presetIndex].customFinderTags.removeAll { $0 == tag }
        prefs.savedPresets = copy
    }

    private func newTagExpiryChoiceLabel(_ days: Int) -> String {
        switch days {
        case 0:
            return String(localized: "Off", comment: "New tag expiry choice.")
        case 1:
            return String(localized: "1 day", comment: "New tag expiry choice.")
        default:
            return String.localizedStringWithFormat(String(localized: "%lld days", comment: "New tag expiry choice."), Int64(days))
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsTab: View {
    @EnvironmentObject private var prefs: BinkyPreferences
    @State private var shortcutErrors: [ShortcutAction: String] = [:]
    @State private var recordingAction: ShortcutAction?

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.settingsListedActions) { action in
                    shortcutRow(for: action)
                }
                HStack {
                    Spacer()
                    Button(S.shortcutsResetAll) {
                        prefs.resetAllShortcuts()
                        shortcutErrors = [:]
                        recordingAction = nil
                    }
                    .disabled(ShortcutAction.settingsListedActions.allSatisfy { prefs.isDefaultShortcut($0) })
                }
            } header: {
                Text(S.shortcutsCustomizableHeader)
            } footer: {
                Text(S.shortcutsTabServicesFooter)
                    .font(.caption)
            }

            Section {
                ForEach(S.fixedMenuShortcutReference) { row in
                    HStack(spacing: 12) {
                        Text(row.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        KeyComboView(combo: row.keys)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title), \(row.keys)")
                }
            } header: {
                Text(S.shortcutsFixedHeader)
            }

            Section {
                Text(S.shortcutsAppDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "Shortcuts app", comment: "Settings UI."))
            }

            Section {
                Text(S.shortcutsTabHelpFooter(helpMenuShortcut: BinkyFixedShortcut.binkyHelp.shortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "More help", comment: "Settings UI."))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func shortcutRow(for action: ShortcutAction) -> some View {
        let s = prefs.shortcut(for: action)
        let sysWarn = ShortcutValidator.systemWarning(for: s)
        let isRecording = recordingAction == action
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(action.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    ShortcutRecorderField(
                        prefs: prefs,
                        action: action,
                        isRecording: recordingBinding(for: action),
                        inlineError: errorBinding(for: action)
                    )
                    .frame(minWidth: 128, maxWidth: 160)
                    if let w = sysWarn, !isRecording {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help("\(S.shortcutsSystemWarningPrefix) \(w)")
                            .accessibilityLabel("\(S.shortcutsSystemWarningPrefix) \(w)")
                    }
                    if isRecording {
                        Button(S.shortcutsCancelEdit) {
                            recordingAction = nil
                            shortcutErrors.removeValue(forKey: action)
                        }
                        .fixedSize()
                    } else {
                        Button(S.shortcutsEdit) {
                            shortcutErrors.removeValue(forKey: action)
                            recordingAction = action
                        }
                        .fixedSize()
                        if !prefs.isDefaultShortcut(action) {
                            Button(S.shortcutsResetRow) {
                                prefs.resetShortcut(action)
                                shortcutErrors.removeValue(forKey: action)
                            }
                            .fixedSize()
                        }
                    }
                }
            }
            if isRecording {
                Text(S.shortcutsRecorderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = shortcutErrors[action] {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: action, shortcut: s, systemWarn: sysWarn, isRecording: isRecording))
    }

    private func accessibilityLabel(for action: ShortcutAction, shortcut: CustomShortcut, systemWarn: String?, isRecording: Bool) -> String {
        var parts = "\(action.title), \(shortcut.displayString)"
        if isRecording { parts += ", recording — \(S.shortcutsRecorderHint)" }
        if let w = systemWarn, !isRecording { parts += ", \(S.shortcutsSystemWarningPrefix) \(w)" }
        if let e = shortcutErrors[action] { parts += ", \(e)" }
        return parts
    }

    private func recordingBinding(for action: ShortcutAction) -> Binding<Bool> {
        Binding(
            get: { recordingAction == action },
            set: { newValue in
                if newValue {
                    if recordingAction != action {
                        if let prev = recordingAction {
                            shortcutErrors.removeValue(forKey: prev)
                        }
                        recordingAction = action
                    }
                } else if recordingAction == action {
                    recordingAction = nil
                }
            }
        )
    }

    private func errorBinding(for action: ShortcutAction) -> Binding<String?> {
        Binding(
            get: { shortcutErrors[action] },
            set: { newVal in
                if let newVal {
                    shortcutErrors[action] = newVal
                } else {
                    shortcutErrors.removeValue(forKey: action)
                }
            }
        )
    }
}

/// Comma-separated tags per ``FileSortCategory`` (persisted as `[rawValue: [tags]]`).
private struct FinderTagDefaultsByCategoryMapEditor: View {
    @Binding var map: [String: [String]]

    private var tagsColumnTitle: String {
        String(localized: "Tags", comment: "Column header: custom Finder tags per category.")
    }

    private var builtInColumnTitle: String {
        String(localized: "Built-in", comment: "Column header: built-in Finder tag fallback when maps are blank.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(localized: "Category", comment: "Column header: sort category for Finder tag defaults."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: typeColumnMinWidth, alignment: .leading)
                Text(tagsColumnTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(builtInColumnTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: builtInColumnWidth, alignment: .leading)
            }
            .accessibilityHidden(true)

            ForEach(FileSortCategory.allCases, id: \.rawValue) { category in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.rowTitle(for: category))
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: typeColumnMinWidth, alignment: .leading)

                    TextField("", text: binding(for: category), prompt: tagsFieldPrompt)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text(Self.accessibilityFieldLabel(for: category)))
                        .accessibilityHint(String(localized: "Separate tags with commas. Leave empty for the built-in tag.", comment: "VoiceOver hint for per-category Finder tag field."))

                    Text(Self.builtInHint(for: category))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: builtInColumnWidth, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    /// Matches widest localized category label so the tag fields align.
    private var typeColumnMinWidth: CGFloat { 130 }

    private var builtInColumnWidth: CGFloat { 110 }

    private var tagsFieldPrompt: Text {
        Text(String(localized: "Optional — comma-separated", comment: "Placeholder for per-type Finder tag list (single prompt for all rows)."))
    }

    private func binding(for category: FileSortCategory) -> Binding<String> {
        Binding(
            get: { map[category.rawValue]?.joined(separator: ", ") ?? "" },
            set: { newVal in
                var copy = map
                let parts = newVal.split(separator: ",").map { chunk in
                    String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                if parts.isEmpty {
                    copy.removeValue(forKey: category.rawValue)
                } else {
                    copy[category.rawValue] = parts
                }
                map = copy
            }
        )
    }

    private static func builtInHint(for category: FileSortCategory) -> String {
        category.semanticTagHint
    }

    private static func accessibilityFieldLabel(for category: FileSortCategory) -> String {
        String.localizedStringWithFormat(
            String(localized: "Finder tags for %@", comment: "VoiceOver label for per-category tag field."),
            rowTitle(for: category)
        )
    }

    private static func rowTitle(for category: FileSortCategory) -> String {
        switch category {
        case .images:
            return String(localized: "Images", comment: "Sort category label for Finder tag defaults.")
        case .pdf:
            return String(localized: "PDF", comment: "Sort category label for Finder tag defaults.")
        case .video:
            return String(localized: "Video", comment: "Sort category label for Finder tag defaults.")
        case .audio:
            return String(localized: "Audio", comment: "Sort category label for Finder tag defaults.")
        case .documents:
            return String(localized: "Documents", comment: "Sort category label for Finder tag defaults.")
        case .archives:
            return String(localized: "Archives", comment: "Sort category label for Finder tag defaults.")
        case .apps:
            return String(localized: "Apps / installers", comment: "Sort category label for Finder tag defaults.")
        case .screenshots:
            return String(localized: "Screenshots", comment: "Sort category label for Finder tag defaults.")
        case .misc:
            return String(localized: "Misc", comment: "Sort category label for Finder tag defaults.")
        case .review:
            return String(localized: "Review", comment: "Sort category label for Finder tag defaults.")
        case .duplicates:
            return String(localized: "Duplicates", comment: "Sort category label for Finder tag defaults.")
        case .receipts:
            return String(localized: "Receipts", comment: "Sort category label for Finder tag defaults.")
        case .folders:
            return String(localized: "Folders", comment: "Sort category label for Finder tag defaults.")
        }
    }
}

/// Renders a compact key combo like `⌘⇧V` as individual keycaps.
private struct KeyComboView: View {
    let combo: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(combo.enumerated()), id: \.offset) { _, ch in
                KeyCapView(label: String(ch))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single keycap, sized to its content but with a uniform minimum so modifier glyphs and letters line up.
private struct KeyCapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
    }
}
