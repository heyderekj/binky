import Foundation
import OSLog
import SwiftUI

private let prefsLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Binky", category: "BinkyPreferences")

final class BinkyPreferences: ObservableObject {

    init() {
        Self.migrateSortNowShortcutKeyIfNeeded()
        Self.migratePendingRoutineTemplateUserDefaultsIfNeeded()
        seedDefaultProfileIfNeeded()
        ensureActiveProfileIsValid()
        migrateRoutineLegacyWatchFoldersIfNeeded()

        // When another process (the CLI, `defaults write`, or a synced pref store) modifies
        // UserDefaults, our in-memory caches go stale. Observing the notification lets us
        // invalidate lazily — the next getter re-decodes from the fresh backing store.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateAllCaches()
        }
    }

    /// Drops all in-memory decoded caches so the next property access re-reads from UserDefaults.
    /// Called when `UserDefaults.didChangeNotification` fires (external writes from CLI, etc).
    private func invalidateAllCaches() {
        cachedGlobalSkipTags = nil
        cachedSavedPresets = nil
        cachedSessionHistory = nil
        cachedFileAgingRules = nil
        cachedSortRoutingRules = nil
        objectWillChange.send()
    }

    /// One-time migrate from compression-era defaults key (`shortcut.compressNow` → `shortcut.sortNow`).
    private static func migrateSortNowShortcutKeyIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyKey = "shortcut.compressNow"
        let modernKey = "shortcut.sortNow"
        if defaults.object(forKey: modernKey) == nil,
           let blob = defaults.data(forKey: legacyKey), !blob.isEmpty {
            defaults.set(blob, forKey: modernKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }

    /// One-shot copy from legacy `pendingAutomationTemplate` → `pendingRoutineTemplate` staging key used by onboarding.
    private static func migratePendingRoutineTemplateUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyKey = "binky.pendingAutomationTemplate"
        let modernKey = "binky.pendingRoutineTemplate"
        if defaults.object(forKey: modernKey) == nil,
           let staged = defaults.object(forKey: legacyKey) {
            defaults.set(staged, forKey: modernKey)
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private func seedDefaultProfileIfNeeded() {
        let seedKey = "binky.profiles.didSeedDefault"
        let d = UserDefaults.standard
        guard !d.bool(forKey: seedKey) else { return }
        if savedPresets.isEmpty {
            let defaultProfile = Inbox(
                name: String(localized: "Default", comment: "Built-in default organizer profile name.")
            )
            savedPresets = [defaultProfile]
            if activePresetID.isEmpty {
                activePresetID = defaultProfile.id.uuidString
            }
        }
        d.set(true, forKey: seedKey)
    }

    private func ensureActiveProfileIsValid() {
        guard !savedPresets.isEmpty else { return }
        if activePresetID.isEmpty || !savedPresets.contains(where: { $0.id.uuidString == activePresetID }) {
            activePresetID = savedPresets.first!.id.uuidString
        }
    }

    private func migrateRoutineLegacyWatchFoldersIfNeeded() {
        let key = "binky.automation.legacyGlobalPathHydrated.v1"
        let d = UserDefaults.standard
        guard !d.bool(forKey: key) else { return }
        var list = savedPresets
        let gp = watchedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let gb = watchedFolderBookmark
        for i in list.indices {
            var a = list[i]
            a.hydrateLegacyGlobalWatchIfNeeded(globalPath: gp, globalBookmark: gb)
            list[i] = a
        }
        savedPresets = list
        d.set(true, forKey: key)
    }

    /// Finder tags that tell Binky to leave a file alone (e.g. “DoNotMove”). Case-insensitive.
    @AppStorage("sort.globalSkipTagsJSON") private var globalSkipTagsJSONStorage: Data = Data()

    private var cachedGlobalSkipTags: [String]?
    var globalSkipTags: [String] {
        get {
            if let cachedGlobalSkipTags { return cachedGlobalSkipTags }
            let v = (try? JSONDecoder().decode([String].self, from: globalSkipTagsJSONStorage)) ?? []
            cachedGlobalSkipTags = v
            return v
        }
        set {
            objectWillChange.send()
            cachedGlobalSkipTags = newValue
            globalSkipTagsJSONStorage = newValue.isEmpty ? Data() : ((try? JSONEncoder().encode(newValue)) ?? Data())
        }
    }

    // MARK: Finish

    @AppStorage("openFolderWhenDone")   var openFolderWhenDone: Bool = false
    @AppStorage("showBatchSummaryDialog") var showBatchSummaryDialog: Bool = true
    @AppStorage("notifyWhenDone")       var notifyWhenDone: Bool = false
    @AppStorage("playSoundEffects")     var playSoundEffects: Bool = true
    @AppStorage("reduceMotion")         var reduceMotion: Bool = false

    @AppStorage(EnergySettingsKey.pauseOnLowPowerMode) var energyPauseOnLowPowerMode: Bool = true
    @AppStorage(EnergySettingsKey.pauseOnThermalCritical) var energyPauseOnThermalCritical: Bool = true
    /// File count at which inter-file thermal pacing and progress coalescing apply.
    @AppStorage(EnergySettingsKey.bigBatchThreshold) private var energyBigBatchThresholdStorage: Int = 200
    @AppStorage(EnergySettingsKey.throttleProfile) private var energyThrottleProfileRaw: String = EnergyThrottleProfile.auto.rawValue

    /// Clamped 50…10,000; persisted via `energyBigBatchThresholdStorage`.
    var energyBigBatchThreshold: Int {
        get { Self.clampBigBatchThreshold(energyBigBatchThresholdStorage) }
        set { energyBigBatchThresholdStorage = Self.clampBigBatchThreshold(newValue) }
    }

    var energyThrottleProfile: EnergyThrottleProfile {
        get { EnergyThrottleProfile(rawValue: energyThrottleProfileRaw) ?? .auto }
        set { energyThrottleProfileRaw = newValue.rawValue }
    }

    private static func clampBigBatchThreshold(_ v: Int) -> Int {
        min(max(v, 50), 10_000)
    }

    /// Shows Binky in the menu bar (Sort Now, pause watching, Settings).
    @AppStorage("ui.showMenuBarIcon") var showMenuBarIcon: Bool = true
    /// Hides Dock icon and runs as accessory app; sorting still happens in the background.
    @AppStorage("ui.menuBarOnlyMode") var menuBarOnlyMode: Bool = false
    @AppStorage("binky.mainWindowModeVisibility") private var mainWindowModeVisibilityRaw: String = MainWindowModeVisibility.both.rawValue

    var mainWindowModeVisibility: MainWindowModeVisibility {
        get { MainWindowModeVisibility(rawValue: mainWindowModeVisibilityRaw) ?? .both }
        set { mainWindowModeVisibilityRaw = newValue.rawValue }
    }

    @AppStorage("folderWatchEnabled")   var folderWatchEnabled: Bool = true
    @AppStorage("watchedFolderPath")    var watchedFolderPath: String = ""
    @AppStorage("watchedFolderBookmark") var watchedFolderBookmark: Data = Data()

    // MARK: Sidebar visibility (Appearance)

    @AppStorage("sidebar.showImages") var showImagesSection: Bool = true
    @AppStorage("sidebar.showPDFs")   var showPDFsSection:   Bool = true
    @AppStorage("sidebar.showVideos") var showVideosSection:  Bool = true
    @AppStorage("sidebar.simpleMode") var sidebarSimpleMode: Bool = true

    func applySidebarSimpleMode(_ simple: Bool) {
        sidebarSimpleMode = simple
        if simple {
            showImagesSection = false
            showVideosSection = false
            showPDFsSection = false
        } else {
            showImagesSection = true
            showVideosSection = true
            showPDFsSection = true
        }
    }

    func reconcileSidebarSectionsForSimpleModeIfNeeded() {
        guard sidebarSimpleMode else { return }
        if showImagesSection || showVideosSection || showPDFsSection {
            showImagesSection = false
            showVideosSection = false
            showPDFsSection = false
        }
    }

    func adoptSimpleSidebarWhenAllSectionsHidden() {
        guard !showImagesSection, !showVideosSection, !showPDFsSection else { return }
        applySidebarSimpleMode(true)
    }

    enum SidebarScopedSection {
        case images, videos, pdfs
    }

    func setScopedSidebarSection(_ section: SidebarScopedSection, isOn: Bool) {
        if isOn && sidebarSimpleMode {
            sidebarSimpleMode = false
        }
        switch section {
        case .images: showImagesSection = isOn
        case .videos: showVideosSection = isOn
        case .pdfs: showPDFsSection = isOn
        }
        adoptSimpleSidebarWhenAllSectionsHidden()
    }

    // MARK: Presets

    @AppStorage("activePresetID") var activePresetID: String = ""
    @AppStorage("savedPresetsData") var savedPresetsData: Data = Data()

    private var cachedSavedPresets: [Inbox]?
    var savedPresets: [Inbox] {
        get {
            if let cachedSavedPresets { return cachedSavedPresets }
            let v = (try? JSONDecoder().decode([Inbox].self, from: savedPresetsData)) ?? []
            cachedSavedPresets = v
            return v
        }
        set {
            cachedSavedPresets = newValue
            savedPresetsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            NotificationCenter.default.post(name: .binkyRoutingRulesDidChange, object: nil)
        }
    }

    // MARK: Session history

    @AppStorage("sessionHistoryData") var sessionHistoryData: Data = Data()

    private var cachedSessionHistory: [SessionRecord]?
    var sessionHistory: [SessionRecord] {
        get {
            if let cachedSessionHistory { return cachedSessionHistory }
            let v = (try? JSONDecoder().decode([SessionRecord].self, from: sessionHistoryData)) ?? []
            cachedSessionHistory = v
            return v
        }
        set {
            cachedSessionHistory = newValue
            sessionHistoryData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: Updates

    @AppStorage("lastUpdateCheck")         var lastUpdateCheck: Double = 0
    @AppStorage("dismissedUpdateVersion")  var dismissedUpdateVersion: String = ""

    // MARK: Diagnostics

    @AppStorage("crashReportingEnabled") var crashReportingEnabled: Bool = false

    // MARK: Sort

    @AppStorage("sort.assignFinderTags") var assignFinderTagsOnSortEnabled: Bool = false
    @AppStorage("sort.appendNewSemanticTag") var sortAppendNewSemanticTagEnabled: Bool = true

    @AppStorage("sort.customRulesEnabled") var sortCustomRulesEnabled: Bool = false

    /// Off / move to `Duplicates` / move to Trash when a file matches a prior byte hash or near-duplicate image.
    @AppStorage("sort.duplicateMode") var sortDuplicateModeRaw: String = SortDuplicateHandlingMode.off.rawValue

    /// Vision OCR renames default screenshot filenames using the strongest text line.
    @AppStorage("sort.smartScreenshotNames") var sortSmartScreenshotNamesEnabled: Bool = false

    /// Heuristic receipt / invoice detection for PDFs and images (routes to Receipts when enabled).
    @AppStorage("sort.detectReceipts") var sortDetectReceiptsEnabled: Bool = false

    /// Most recent sort: rows that were “already had” (skipped duplicate or moved to Duplicates). For Settings summary only.
    @AppStorage("sort.lastRunAlreadyHadCount") var lastSortAlreadyHadCount: Int = 0

    /// Move / trash stagnant files in category folders (see ``CategoryAgingRule``).
    @AppStorage("fileAging.enabled") var fileAgingEnabled: Bool = false
    @AppStorage("fileAging.rulesJSON") private var fileAgingRulesJSONStorage: Data = Data()
    private var cachedFileAgingRules: [CategoryAgingRule]?
    var fileAgingRules: [CategoryAgingRule] {
        get {
            if let cachedFileAgingRules { return cachedFileAgingRules }
            let v = (try? JSONDecoder().decode([CategoryAgingRule].self, from: fileAgingRulesJSONStorage)) ?? []
            cachedFileAgingRules = v
            return v
        }
        set {
            objectWillChange.send()
            cachedFileAgingRules = newValue
            fileAgingRulesJSONStorage = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// End-of-day totals notification.
    @AppStorage("digest.enabled") var dailyDigestEnabled: Bool = false
    /// Hour 0…23 local time.
    @AppStorage("digest.hour") var dailyDigestHour: Int = 9
    /// Monday-style weekly rollup from session history.
    @AppStorage("digest.weekly.enabled") var weeklyDigestEnabled: Bool = true
    /// Calendar weekday component (Sunday = 1 … default Monday = 2).
    @AppStorage("digest.weekly.weekday") var weeklyDigestWeekday: Int = 2

    @AppStorage("sort.routingRulesJSON") private var sortRoutingRulesJSONStorage: Data = Data()

    @AppStorage("sort.finderTagDefaultsJSON") private var sortFinderTagDefaultsJSONStorage: Data = Data()

    private var cachedSortRoutingRules: [SortRule]?
    var sortRoutingRules: [SortRule] {
        get {
            if let cachedSortRoutingRules { return cachedSortRoutingRules }
            let v = (try? JSONDecoder().decode([SortRule].self, from: sortRoutingRulesJSONStorage)) ?? []
            cachedSortRoutingRules = v
            return v
        }
        set {
            objectWillChange.send()
            cachedSortRoutingRules = newValue
            sortRoutingRulesJSONStorage = (try? JSONEncoder().encode(newValue)) ?? Data()
            NotificationCenter.default.post(name: .binkyRoutingRulesDidChange, object: nil)
        }
    }

    private var cachedSortFinderTagDefaults: [String: [String]]?
    /// Default Finder tags per ``FileSortCategory`` (keys = category raw values). Empty value / missing key falls back to built-ins.
    var sortFinderTagDefaultsByCategory: [String: [String]] {
        get {
            if let cachedSortFinderTagDefaults { return cachedSortFinderTagDefaults }
            guard !sortFinderTagDefaultsJSONStorage.isEmpty else {
                cachedSortFinderTagDefaults = [:]
                return [:]
            }
            let v = (try? JSONDecoder().decode([String: [String]].self, from: sortFinderTagDefaultsJSONStorage)) ?? [:]
            cachedSortFinderTagDefaults = v
            return v
        }
        set {
            objectWillChange.send()
            cachedSortFinderTagDefaults = newValue
            sortFinderTagDefaultsJSONStorage = newValue.isEmpty ? Data() : ((try? JSONEncoder().encode(newValue)) ?? Data())
        }
    }

    @AppStorage("sort.excludeExtensionsCSV") var sortExcludeExtensionsCSV: String = ""

    @AppStorage("sort.excludeNameFragmentsJSON") private var sortExcludeNameFragmentsJSONStorage: Data = Data()

    private var cachedExcludeNameFragments: [String]?
    var sortExcludeNameFragments: [String] {
        get {
            if let cachedExcludeNameFragments { return cachedExcludeNameFragments }
            let v = (try? JSONDecoder().decode([String].self, from: sortExcludeNameFragmentsJSONStorage)) ?? []
            cachedExcludeNameFragments = v
            return v
        }
        set {
            objectWillChange.send()
            cachedExcludeNameFragments = newValue
            sortExcludeNameFragmentsJSONStorage = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    @AppStorage("folderWatch.paused") var folderWatchPaused: Bool = false

    /// Watch immediate subfolders of each watched folder root (one level) for sorting and sweep.
    @AppStorage("watch.recursiveOneLevel") var watchRecursiveOneLevel: Bool = false

    /// Move non–destination loose directories at the watch root into the Folders destination as a single unit.
    @AppStorage("sort.moveLooseFolders.enabled") var sortMoveLooseFoldersEnabled: Bool = false

    /// Relative path under the sort root for loose-folder moves; empty = default ``FileSortCategory.folders`` folder name.
    @AppStorage("sort.moveLooseFolders.relativePath") var sortLooseFoldersDestinationRelative: String = ""

    /// When on, saving routing rules triggers a sort across all watched folder roots (debounced).
    @AppStorage("sort.autoRunWhenRulesChange") var sortAutoRunWhenRulesChange: Bool = false

    /// When on, the sort engine processes files one at a time with a small delay so the user can
    /// actually watch each file get categorized. Useful for demos, screencasts, and trust-building
    /// during the first few sorts.
    @AppStorage("sort.slowModeEnabled") var sortSlowModeEnabled: Bool = false

    func sortExcludeExtensionsNormalized() -> Set<String> {
        sortExcludeExtensionsCSV
            .split(separator: ",")
            .map { chunk in
                String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: ".", with: "")
            }
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    func sortExcludeNameFragmentsNormalized() -> [String] {
        sortExcludeNameFragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: Keyboard shortcuts

    @AppStorage("shortcut.openFiles") private var shortcutOpenFilesData: Data = Data()
    @AppStorage("shortcut.sortNow") private var shortcutSortNowData: Data = Data()

    func shortcut(for action: ShortcutAction) -> CustomShortcut {
        let data: Data
        switch action {
        case .openFiles: data = shortcutOpenFilesData
        case .sortNow: data = shortcutSortNowData
        }
        if data.isEmpty { return action.defaultShortcut }
        return (try? JSONDecoder().decode(CustomShortcut.self, from: data)) ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: CustomShortcut, for action: ShortcutAction) {
        objectWillChange.send()
        let encoded = (try? JSONEncoder().encode(shortcut)) ?? Data()
        switch action {
        case .openFiles: shortcutOpenFilesData = encoded
        case .sortNow: shortcutSortNowData = encoded
        }
    }

    func resetShortcut(_ action: ShortcutAction) {
        objectWillChange.send()
        switch action {
        case .openFiles: shortcutOpenFilesData = Data()
        case .sortNow: shortcutSortNowData = Data()
        }
    }

    func resetAllShortcuts() {
        objectWillChange.send()
        shortcutOpenFilesData = Data()
        shortcutSortNowData = Data()
    }

    func isDefaultShortcut(_ action: ShortcutAction) -> Bool {
        shortcut(for: action) == action.defaultShortcut
    }

    var shortcutHelpFingerprint: String {
        [
            shortcutOpenFilesData,
            shortcutSortNowData,
        ]
        .map { $0.base64EncodedString() }
        .joined(separator: "|")
    }

    // MARK: Bookmarks

    func reconcileFolderBookmarksIfNeeded() {
        if folderWatchEnabled, let r = Self.reanchorDirectory(bookmark: watchedFolderBookmark) {
            if r.path != watchedFolderPath { watchedFolderPath = r.path }
            if r.bookmark != watchedFolderBookmark { watchedFolderBookmark = r.bookmark }
        }
        var presets = savedPresets
        var touched = false
        for i in presets.indices {
            if presets[i].isEnabled,
               let r = Self.reanchorDirectory(bookmark: presets[i].watchFolderBookmark) {
                if r.path != presets[i].watchFolderPath {
                    presets[i].watchFolderPath = r.path
                    touched = true
                }
                if r.bookmark != presets[i].watchFolderBookmark {
                    presets[i].watchFolderBookmark = r.bookmark
                    touched = true
                }
            }
        }
        if touched { savedPresets = presets }
    }

    private struct ReanchoredFolder {
        let path: String
        let bookmark: Data
    }

    private static func reanchorDirectory(bookmark: Data) -> ReanchoredFolder? {
        guard !bookmark.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        let std = (url.path as NSString).standardizingPath
        let bm = (stale ? (try? url.bookmarkData(options: .withSecurityScope)) : nil) ?? bookmark
        return ReanchoredFolder(path: std, bookmark: bm)
    }
}

extension BinkyPreferences {

    @MainActor
    func makeSortPreferencesSnapshot() -> SortPreferencesSnapshot {
        var byPresetID: [UUID: Inbox] = [:]
        for p in savedPresets {
            byPresetID[p.id] = p
        }
        return SortPreferencesSnapshot(
            excludeExtensions: sortExcludeExtensionsNormalized(),
            excludeNameFragments: sortExcludeNameFragmentsNormalized(),
            sortCustomRulesEnabled: sortCustomRulesEnabled,
            sortRoutingRules: sortRoutingRules,
            sortAppendNewSemanticTagEnabled: sortAppendNewSemanticTagEnabled,
            assignFinderTagsOnSortEnabled: assignFinderTagsOnSortEnabled,
            finderTagDefaultsByCategory: sortFinderTagDefaultsByCategory,
            globalInboxRoot: downloadsSortRootDirectory(),
            watchRegistry: WatchPipelineRegistry(prefs: self),
            presetsByID: byPresetID,
            sortDuplicateMode: SortDuplicateHandlingMode(rawValue: sortDuplicateModeRaw) ?? .off,
            sortSmartScreenshotNamesEnabled: sortSmartScreenshotNamesEnabled,
            sortDetectReceiptsEnabled: sortDetectReceiptsEnabled,
            watchRecursiveOneLevel: watchRecursiveOneLevel,
            savedPresetOrder: savedPresets.map(\.id),
            globalSkipTagSet: Set(
                globalSkipTags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            ),
            slowMode: sortSlowModeEnabled,
            sortMoveLooseFoldersEnabled: sortMoveLooseFoldersEnabled,
            sortLooseFoldersDestinationRelative: sortLooseFoldersDestinationRelative
        )
    }

    func downloadsSortRootDirectory() -> URL {
        reconcileFolderBookmarksIfNeeded()
        if folderWatchEnabled, !watchedFolderPath.isEmpty {
            let normalized = watchedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
            return URL(fileURLWithPath: normalized).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
    }

    /// Resolved active organizer profile (`activePresetID`), if any.
    var activePreset: Inbox? {
        guard let uuid = UUID(uuidString: activePresetID) else { return nil }
        return savedPresets.first { $0.id == uuid }
    }

    /// Default watched folder used for interactive **Sort Now**, drop routing, preview, Review counts, etc. Uses the active automation’s folder when set.
    func activeSortSweepRootDirectory() -> URL {
        reconcileFolderBookmarksIfNeeded()
        guard let preset = activePreset else { return downloadsSortRootDirectory() }
        if let path = WatchFolderPathResolver.resolvedWatchDirectoryPath(
            bookmark: preset.watchFolderBookmark,
            storedPath: preset.watchFolderPath
        ), !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return downloadsSortRootDirectory()
    }

    func sortTagComposition(forCategory category: FileSortCategory) -> [String] {
        FinderTagComposer.compose(
            naturalCategory: category,
            globalDefaults: sortFinderTagDefaultsByCategory,
            preset: activePreset,
            matchedRule: nil,
            appendNewSemanticTag: sortAppendNewSemanticTagEnabled
        )
    }

    func appendSortOutcomeRecord(_ outcome: SortBatchOutcome) {
        guard let data = try? JSONEncoder().encode(outcome) else {
            prefsLog.error("Failed to encode SortBatchOutcome id=\(outcome.id.uuidString, privacy: .public)")
            return
        }

        let bytesMoved: Int64 = outcome.entries.reduce(into: 0) { sum, e in
            guard e.disposition == .moved, let d = e.destinationPath else { return }
            let attrs = try? FileManager.default.attributesOfItem(atPath: d)
            sum += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }

        let record = SessionRecord(
            id: outcome.id,
            timestamp: outcome.started,
            fileCount: outcome.entries.count,
            totalBytesMoved: max(0, bytesMoved),
            formats: outcome.entries.isEmpty
                ? ["Downloads sort"]
                : Array(Set(outcome.entries.map(\.category.rawValue))).sorted(),
            batchSummaryData: data
        )

        var hist = sessionHistory
        hist.insert(record, at: 0)
        sessionHistory = Array(hist.prefix(50))
    }
}
