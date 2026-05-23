import SwiftUI
import UniformTypeIdentifiers
import AppKit
import UserNotifications

/// Hosts the organizer UI and bridges menu / external events.
struct ContentView: View {
    @EnvironmentObject var prefs: BinkyPreferences
    @EnvironmentObject var updater: UpdateChecker
    @ObservedObject var vm: OrganizerViewModel
    @AppStorage("binky.mainWindowMode") private var mainWindowStored = MainWindowMode.quickSort.rawValue

    /// One-time heuristic: upgrading users land on **Routines** when they’ve already enabled watches.
    private static let mainWindowModeMigrationKey = "binky.mainWindowMode.didMigrate.v1"

    @State private var showingHistorySheet = false
    @ObservedObject private var diagnostics = DiagnosticsReporter.shared
    @AppStorage("binky.onboarding.v2.completed") private var onboardingCompleted = false

    init(vm: OrganizerViewModel) {
        self.vm = vm
    }

    var body: some View {
        coreBody
            .environmentObject(prefs)
            .environmentObject(updater)
            .onAppear {
                migrateMainWindowModeIfNeeded()
                BinkyMenuBarController.shared.refresh()
                SortDigestScheduler.reschedule(prefs: prefs)
                FileAgingService.shared.restartTimer(prefs: prefs)
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
            .modifier(PreferenceObservers(prefs: prefs))
            .modifier(MenuBridgeObservers(
                vm: vm,
                prefs: prefs,
                updater: updater,
                openFilesPanel: { openSortableFilesPanel() }
            ))
            .onReceive(NotificationCenter.default.publisher(for: .binkyShowHistory)) { _ in
                showingHistorySheet = true
            }
            .sheet(isPresented: $showingHistorySheet) {
                HistorySheet(
                    onOpenSessionSummary: { record in
                        guard let data = record.batchSummaryData else { return }
                        if let sortOutcome = try? JSONDecoder().decode(SortBatchOutcome.self, from: data) {
                            showingHistorySheet = false
                            vm.presentHistoricalSortOutcome(sortOutcome)
                        }
                    }
                )
                .environmentObject(prefs)
            }
            .sheet(item: $vm.pendingSortOutcome) { outcome in
                SortOutcomeSheet(
                    outcome: outcome,
                    onUndo: { vm.applySortOutcomeDismissalDefaults() },
                    onDismiss: { vm.applySortOutcomeDismissalDefaults() },
                    onTransientStatus: { vm.flashTransientStatus($0) }
                )
                .environmentObject(prefs)
                .id(outcome.id.uuidString)
            }
            .sheet(item: $diagnostics.pendingCrashReport) { report in
                PostCrashReportSheet(report: report, diagnostics: diagnostics)
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyPrepareQuit)) { _ in
                vm.pendingSortOutcome = nil
                diagnostics.pendingCrashReport = nil
                showingHistorySheet = false
            }
            .sheet(isPresented: Binding(
                get: { !onboardingCompleted },
                set: { if !$0 { onboardingCompleted = true } }
            )) {
                OnboardingSheet()
            }
    }

    /// v2: Daily Calm is the main window. The old OrganizerMainView is retired.
    private var coreBody: some View {
        DailyCalmPreviewSheet()
    }

    /// First launch after upgrading: preserve muscle memory when someone already wired Routines up.
    private func migrateMainWindowModeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.mainWindowModeMigrationKey) else { return }
        let routineCount = prefs.savedPresets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        mainWindowStored = routineCount > 0 ? MainWindowMode.routines.rawValue : MainWindowMode.quickSort.rawValue
        UserDefaults.standard.set(true, forKey: Self.mainWindowModeMigrationKey)
    }

    private func openSortableFilesPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = prefs.activeSortSweepRootDirectory()
        panel.prompt = String(localized: "Sort", comment: "Open panel button.")
        if panel.runModal() == .OK {
            Task {
                await vm.sortIncomingFiles(panel.urls, prefs: prefs)
            }
        }
    }
}

// MARK: - Manual update check alerts

@MainActor
private func presentManualUpdateResult(_ result: UpdateChecker.CheckResult,
                                       updater: UpdateChecker) {
    let alert = NSAlert()
    alert.alertStyle = .informational

    switch result {
    case .updateAvailable(let version):
        alert.messageText = String(localized: "A newer Binky is available.", comment: "Manual update alert title.")
        alert.informativeText = String(localized: "Version \(version) is out. You’re on \(currentAppVersion()). Want it?", comment: "Manual update alert; arguments are new and current version.")
        alert.addButton(withTitle: String(localized: "Install Update", comment: "Manual update alert."))
        alert.addButton(withTitle: String(localized: "What’s new", comment: "Manual update alert."))
        alert.addButton(withTitle: String(localized: "Maybe later", comment: "Manual update alert."))

        switch updater.installState {
        case .idle, .failed:
            break
        case .downloading, .installing:
            return
        }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Task { await updater.downloadAndInstall() }
        } else if response == .alertSecondButtonReturn, let url = updater.releaseURL {
            NSWorkspace.shared.open(url)
        }

    case .upToDate:
        alert.messageText = String(localized: "All caught up.", comment: "Manual update: no update available.")
        alert.informativeText = String(localized: "You’re on Binky \(currentAppVersion()) — the latest.", comment: "Manual update: up to date; argument is version.")
        alert.addButton(withTitle: String(localized: "Nice", comment: "Dismiss up-to-date alert."))
        alert.runModal()

    case .failed:
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t phone home.", comment: "Manual update: network error title.")
        alert.informativeText = String(localized: "Binky couldn’t reach GitHub. Probably the internet. Try again in a sec?", comment: "Manual update: network error detail.")
        alert.addButton(withTitle: String(localized: "OK", comment: "Alert dismiss."))
        alert.runModal()
    }
}

private func currentAppVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
}

// MARK: - View modifier helpers

/// Splits ContentView's preference observers off the main body so the SwiftUI type checker
/// doesn't time out on a single deep modifier chain.
private struct PreferenceObservers: ViewModifier {
    @ObservedObject var prefs: BinkyPreferences

    func body(content: Content) -> some View {
        content
            .onChange(of: prefs.dailyDigestEnabled) { _, _ in
                SortDigestScheduler.reschedule(prefs: prefs)
            }
            .onChange(of: prefs.dailyDigestHour) { _, _ in
                SortDigestScheduler.reschedule(prefs: prefs)
            }
            .onChange(of: prefs.weeklyDigestEnabled) { _, _ in
                SortDigestScheduler.reschedule(prefs: prefs)
            }
            .onChange(of: prefs.weeklyDigestWeekday) { _, _ in
                SortDigestScheduler.reschedule(prefs: prefs)
            }
            .onChange(of: prefs.fileAgingEnabled) { _, _ in
                FileAgingService.shared.restartTimer(prefs: prefs)
            }
            .onChange(of: prefs.showMenuBarIcon) { _, _ in
                BinkyMenuBarController.shared.refresh()
            }
            .onChange(of: prefs.menuBarOnlyMode) { _, newVal in
                BinkyActivationPolicy.apply(menuBarOnly: newVal)
                BinkyMenuBarController.shared.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyFolderWatchPauseChanged)) { _ in
                let v = UserDefaults.standard.bool(forKey: "folderWatch.paused")
                if prefs.folderWatchPaused != v {
                    prefs.folderWatchPaused = v
                }
            }
    }
}

/// Bridges menu bar / shortcut notifications into ContentView actions. Kept in its own
/// modifier so the SwiftUI type checker handles each `.onReceive` chain separately.
private struct MenuBridgeObservers: ViewModifier {
    @ObservedObject var vm: OrganizerViewModel
    @ObservedObject var prefs: BinkyPreferences
    @ObservedObject var updater: UpdateChecker
    let openFilesPanel: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .binkyOpenPanel)) { _ in
                openFilesPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyOpenFiles)) { note in
                guard let urls = note.object as? [URL] else { return }
                Task { await vm.sortIncomingFiles(urls, prefs: prefs) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyStartSort)) { _ in
                Task { await runSweep(routineID: nil) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyStartSortForRoutine)) { note in
                let id = note.userInfo?[BinkyNotificationUserInfoKey.sortRoutinePresetID] as? UUID
                Task { await runSweep(routineID: id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyShowLastBatchSummary)) { _ in
                vm.showLastSortSummary()
            }
            .onReceive(NotificationCenter.default.publisher(for: .binkyCheckUpdates)) { _ in
                Task {
                    let result = await updater.check(manual: true)
                    presentManualUpdateResult(result, updater: updater)
                }
            }
    }

    /// One sweep helper that handles all three menu paths:
    /// global Sort Now, Sort All Folders, and per-routine sweep. `routineID` `nil`
    /// uses the count-based fallback (single routine → default sweep, multiple → all).
    private func runSweep(routineID: UUID?) async {
        let enabled = prefs.savedPresets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let id = routineID, let preset = prefs.savedPresets.first(where: { $0.id == id }) {
            await vm.runInteractiveSweep(preset: preset, prefs: prefs)
            return
        }
        if enabled.count > 1 {
            await vm.runInteractiveSweepAllRoutines(prefs: prefs)
        } else {
            await vm.runInteractiveDownloadsSweep(prefs: prefs)
        }
    }
}
