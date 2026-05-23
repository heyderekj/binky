import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

/// Main-window state for Downloads folder sorting (replaces the compression queue).
@MainActor
final class OrganizerViewModel: ObservableObject {
    /// Latest automated / manual sort audit sheet.
    @Published var pendingSortOutcome: SortBatchOutcome?
    /// For **Last Sort Summary…** menu / shortcut.
    @Published var lastSortOutcome: SortBatchOutcome?

    /// One-shot status line shown in the organizer (empty folder, duplicate sort, filtering, etc.).
    @Published var transientBannerMessage: String?

    private var transientResetTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .binkySortRejectedBecauseBusy)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.flashTransientStatus(
                    String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
                )
            }
            .store(in: &cancellables)
    }

    func flashTransientStatus(_ message: String, durationSeconds: UInt64 = 3) {
        transientResetTask?.cancel()
        transientBannerMessage = message
        transientResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(durationSeconds))
            guard !Task.isCancelled else { return }
            transientBannerMessage = nil
        }
    }

    func presentSortOutcome(_ outcome: SortBatchOutcome?) {
        pendingSortOutcome = outcome
    }

    func applySortOutcomeDismissalDefaults() {
        pendingSortOutcome = nil
    }

    func presentHistoricalSortOutcome(_ outcome: SortBatchOutcome) {
        pendingSortOutcome = outcome
    }

    func showLastSortSummary() {
        guard let base = lastSortOutcome else { return }
        pendingSortOutcome = base
    }

    /// Run after any successful sort with user-facing side effects.
    func deliverCompletedSort(_ outcome: SortBatchOutcome, prefs: BinkyPreferences) {
        lastSortOutcome = outcome
        let revealRoot = prefs.activeSortSweepRootDirectory()
        if prefs.openFolderWhenDone {
            NSWorkspace.shared.open(revealRoot)
        }
        if prefs.playSoundEffects {
            NSSound(named: "Pop")?.play()
        }
        if prefs.notifyWhenDone {
            postSortSortOnlyNotification(outcome: outcome)
        }
        prefs.lastSortAlreadyHadCount = outcome.alreadyHadCount
        SortDailyDigestAccumulator.shared.record(outcome: outcome)
        pendingSortOutcome = prefs.showBatchSummaryDialog ? outcome : nil
    }

    private func postSortSortOnlyNotification(outcome: SortBatchOutcome) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Binky", comment: "Notification title.")
        content.body = String.localizedStringWithFormat(
            String(localized: "Moved %1$lld · Kept %2$lld · Skipped %3$lld", comment: "Sort notification; three counts."),
            Int64(outcome.movedCount),
            Int64(outcome.keptCount),
            Int64(outcome.skippedCount)
        )
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    func runInteractiveDownloadsSweep(prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }
        let root = prefs.activeSortSweepRootDirectory()
        let recursive = prefs.watchRecursiveOneLevel
        let w = await Task.detached(priority: .utility) {
            DownloadsSortOrchestrator.collectSweepWorkItems(
                in: root,
                recursiveOneLevel: recursive,
                moveLooseFolders: prefs.sortMoveLooseFoldersEnabled
            )
        }.value
        guard w.hasAnyWork else {
            flashTransientStatus(
                String(localized: "Binky'd. Already handled.", comment: "Organizer transient banner when Sweep finds no files in the watched folder.")
            )
            return
        }
        let outcome = await DownloadsSortOrchestrator.shared.sort(
            work: w,
            prefs: prefs,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// One-off sort for an arbitrary inbox folder (Quick Sort pane). Same routing model as preset sweeps.
    func runInteractiveSweep(in rootURL: URL, prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }
        let root = rootURL.standardizedFileURL
        let recursive = prefs.watchRecursiveOneLevel
        let (work, rootOverride) = await Task.detached(priority: .utility) {
            let collected = DownloadsSortOrchestrator.collectSweepWorkItems(
                in: root,
                recursiveOneLevel: recursive,
                moveLooseFolders: prefs.sortMoveLooseFoldersEnabled
            )
            var override: [URL: URL] = [:]
            for url in collected.fileURLs {
                override[url] = root
            }
            for url in collected.looseFolderURLs {
                override[url] = root
            }
            return (collected, override)
        }.value
        guard work.hasAnyWork else {
            flashTransientStatus(
                String(localized: "Binky'd. Already handled.", comment: "Organizer transient banner when Sweep finds no files in the watched folder.")
            )
            return
        }
        let outcome = await DownloadsSortOrchestrator.shared.sort(
            work: work,
            prefs: prefs,
            rootOverride: rootOverride,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Sweep a single routine's folder. Uses `rootOverride` so per-routine rules route
    /// the same way as multi-folder batches.
    func runInteractiveSweep(preset: Inbox, prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }
        let root = URL(fileURLWithPath: preset.watchFolderPath).standardizedFileURL
        let recursive = prefs.watchRecursiveOneLevel
        let (work, rootOverride) = await Task.detached(priority: .utility) {
            let collected = DownloadsSortOrchestrator.collectSweepWorkItems(
                in: root,
                recursiveOneLevel: recursive,
                moveLooseFolders: prefs.sortMoveLooseFoldersEnabled
            )
            var override: [URL: URL] = [:]
            for url in collected.fileURLs {
                override[url] = root
            }
            for url in collected.looseFolderURLs {
                override[url] = root
            }
            return (collected, override)
        }.value
        guard work.hasAnyWork else {
            flashTransientStatus(
                String(localized: "Binky'd. Already handled.", comment: "Organizer transient banner when Sweep finds no files in the watched folder.")
            )
            return
        }
        let outcome = await DownloadsSortOrchestrator.shared.sort(
            work: work,
            prefs: prefs,
            rootOverride: rootOverride,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Sweep every enabled routine in one pass. Each file gets a `rootOverride` to its
    /// own routine source, so the orchestrator routes per-routine rules correctly even
    /// though we only run the sort engine once.
    func runInteractiveSweepAllRoutines(prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }

        let enabled = prefs.savedPresets.filter {
            $0.isEnabled && !$0.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard enabled.count > 1 else {
            await runInteractiveDownloadsSweep(prefs: prefs)
            return
        }

        let roots = enabled.map { URL(fileURLWithPath: $0.watchFolderPath).standardizedFileURL }
        let recursive = prefs.watchRecursiveOneLevel
        let moveLoose = prefs.sortMoveLooseFoldersEnabled
        let (work, rootOverride) = await Task.detached(priority: .utility) {
            var filePaths: [URL] = []
            var folderPaths: [URL] = []
            var override: [URL: URL] = [:]
            var seenFiles: Set<String> = []
            var seenFolders: Set<String> = []
            for root in roots {
                let w = DownloadsSortOrchestrator.collectSweepWorkItems(
                    in: root,
                    recursiveOneLevel: recursive,
                    moveLooseFolders: moveLoose
                )
                for url in w.fileURLs {
                    guard seenFiles.insert(url.standardizedFileURL.path).inserted else { continue }
                    filePaths.append(url)
                    override[url] = root
                }
                for url in w.looseFolderURLs {
                    guard seenFolders.insert(url.standardizedFileURL.path).inserted else { continue }
                    folderPaths.append(url)
                    override[url] = root
                }
            }
            return (SortSweepWorkItems(fileURLs: filePaths, looseFolderURLs: folderPaths), override)
        }.value

        guard work.hasAnyWork else {
            flashTransientStatus(
                String(localized: "All quiet. Every folder is Binky'd.", comment: "Organizer transient banner when Sweep All finds no files across all routines.")
            )
            return
        }

        let outcome = await DownloadsSortOrchestrator.shared.sort(
            work: work,
            prefs: prefs,
            rootOverride: rootOverride,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Sort explicit files (drop, Open panel, Finder Services / right-click).
    ///
    /// - Files: must live under the active watch folder root (kept from earlier behavior).
    /// - Folders: expand to their top-level files; the folder itself becomes the ad-hoc watch
    ///   root for those files, even when it sits outside the watched folder. Subfolders are not
    ///   descended — matches the Sweep model.
    func sortIncomingFiles(_ urls: [URL], prefs: BinkyPreferences) async {
        transientBannerMessage = nil
        let inboxRoot = prefs.activeSortSweepRootDirectory().standardizedFileURL
        let inboxPath = inboxRoot.path
        let capturedUrls = urls

        let (files, rootOverride) = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var files: [URL] = []
            var rootOverride: [URL: URL] = [:]
            var seen: Set<URL> = []

            for raw in capturedUrls {
                let std = raw.standardizedFileURL
                guard std.isFileURL else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: std.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    guard let entries = try? fm.contentsOfDirectory(
                        at: std,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for entry in entries {
                        let entryStd = entry.standardizedFileURL
                        var entryIsDir: ObjCBool = false
                        guard fm.fileExists(atPath: entryStd.path, isDirectory: &entryIsDir),
                              !entryIsDir.boolValue else { continue }
                        guard seen.insert(entryStd).inserted else { continue }
                        files.append(entryStd)
                        rootOverride[entryStd] = std
                    }
                } else {
                    let p = std.path
                    guard p == inboxPath || p.hasPrefix(inboxPath + "/") else { continue }
                    guard seen.insert(std).inserted else { continue }
                    files.append(std)
                }
            }
            return (files, rootOverride)
        }.value

        guard !files.isEmpty else {
            flashTransientStatus(
                String(localized: "Those aren’t in the watched folder. Drop them there first.", comment: "Organizer transient when dropped paths are outside the active watched folder root.")
            )
            return
        }
        guard !DownloadsSortOrchestrator.shared.isSorting else {
            flashTransientStatus(
                String(localized: "Sh. Binky's already on it.", comment: "Organizer transient banner when a sort is requested while one runs.")
            )
            return
        }
        let outcome = await DownloadsSortOrchestrator.shared.sort(
            files: files,
            prefs: prefs,
            rootOverride: rootOverride,
            progress: SortProgressTracker.orchestratorClosure()
        )
        guard outcome.hasWork else { return }
        deliverCompletedSort(outcome, prefs: prefs)
    }

    /// Dry-run rows for active sweep root (sidebar Preview).
    func inboxPreviewEntries(prefs: BinkyPreferences) async -> [SortPreviewEntry] {
        let work = DownloadsSortOrchestrator.collectSweepWorkItems(
            in: prefs.activeSortSweepRootDirectory(),
            recursiveOneLevel: prefs.watchRecursiveOneLevel,
            moveLooseFolders: prefs.sortMoveLooseFoldersEnabled
        )
        return await DownloadsSortOrchestrator.shared.previewSort(work: work, prefs: prefs)
    }
}
