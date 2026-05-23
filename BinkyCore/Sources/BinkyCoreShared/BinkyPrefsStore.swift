import Foundation

/// Reads Binky’s Organizer prefs directly from ``UserDefaults`` (same suites and keys as the app).
/// Used by CLI and tools without SwiftUI.
public struct BinkyPrefsStore: Sendable {
    public var defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Raw reads (mirror `BinkyPreferences` @AppStorage defaults)

    public func decodingSavedPresets() -> [SortingRoutine] {
        let data = defaults.data(forKey: "savedPresetsData") ?? Data()
        return (try? JSONDecoder().decode([SortingRoutine].self, from: data)) ?? []
    }

    public func decodingSortRoutingRules() -> [SortRule] {
        let data = defaults.data(forKey: "sort.routingRulesJSON") ?? Data()
        return (try? JSONDecoder().decode([SortRule].self, from: data)) ?? []
    }

    public func decodingFinderTagDefaultsByCategory() -> [String: [String]] {
        let data = defaults.data(forKey: "sort.finderTagDefaultsJSON") ?? Data()
        guard !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    private func decodingGlobalSkipTags() -> [String] {
        let data = defaults.data(forKey: "sort.globalSkipTagsJSON") ?? Data()
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func decodingExcludeNameFragments() -> [String] {
        let data = defaults.data(forKey: "sort.excludeNameFragmentsJSON") ?? Data()
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Lowercased extension set mirroring ``BinkyPreferences/sortExcludeExtensionsNormalized``.
    private func excludeExtensionsNormalized() -> Set<String> {
        guard let csv = defaults.string(forKey: "sort.excludeExtensionsCSV"), !csv.isEmpty else {
            return []
        }
        return csv.split(separator: ",")
            .map { chunk in
                String(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: ".", with: "")
            }
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    private func downloadsSortRootDecoded() -> URL {
        let folderWatchEnabled = defaults.object(forKey: "folderWatchEnabled") as? Bool ?? true
        let watchedFolderPath = (defaults.string(forKey: "watchedFolderPath") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if folderWatchEnabled, !watchedFolderPath.isEmpty {
            let normalized = watchedFolderPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
            return URL(fileURLWithPath: normalized).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
    }

    /// ``WatchPipelineRegistry`` using bookmark resolution identical to ``WatchPipelineRegistry(prefs:)`` in-app.
    public func watchPipelineRegistry() -> WatchPipelineRegistry {
        let folderWatchEnabled = defaults.object(forKey: "folderWatchEnabled") as? Bool ?? true
        let gpResolved: String? = {
            guard folderWatchEnabled else { return nil }
            let bookmark = defaults.data(forKey: "watchedFolderBookmark") ?? Data()
            let storedPath = defaults.string(forKey: "watchedFolderPath") ?? ""
            if let resolved = WatchFolderPathResolver.resolvedWatchDirectoryPath(bookmark: bookmark, storedPath: storedPath) {
                return resolved
            }
            let downloads = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            return WatchFolderPathResolver.normalizedPath(downloads.path)
        }()

        var pairings: [(UUID, String)] = []
        let presets = decodingSavedPresets()
        for preset in presets where preset.isEnabled {
            guard let raw = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: preset.watchFolderBookmark,
                storedPath: preset.watchFolderPath
            ) else { continue }
            pairings.append((preset.id, raw))
        }
        return WatchPipelineRegistry(globalPath: gpResolved, routinePaths: pairings)
    }

    public func makeSortPreferencesSnapshot() -> SortPreferencesSnapshot {
        let presets = decodingSavedPresets()
        var byPresetID: [UUID: Inbox] = [:]
        for p in presets {
            byPresetID[p.id] = p
        }
        return SortPreferencesSnapshot(
            excludeExtensions: excludeExtensionsNormalized(),
            excludeNameFragments: decodingExcludeNameFragments()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            sortCustomRulesEnabled: defaults.object(forKey: "sort.customRulesEnabled") as? Bool ?? false,
            sortRoutingRules: decodingSortRoutingRules(),
            sortAppendNewSemanticTagEnabled: defaults.object(forKey: "sort.appendNewSemanticTag") as? Bool ?? true,
            assignFinderTagsOnSortEnabled: defaults.object(forKey: "sort.assignFinderTags") as? Bool ?? false,
            finderTagDefaultsByCategory: decodingFinderTagDefaultsByCategory(),
            globalInboxRoot: downloadsSortRootDecoded(),
            watchRegistry: watchPipelineRegistry(),
            presetsByID: byPresetID,
            sortDuplicateMode: SortDuplicateHandlingMode(rawValue: defaults.string(forKey: "sort.duplicateMode") ?? "") ?? .off,
            sortSmartScreenshotNamesEnabled: defaults.object(forKey: "sort.smartScreenshotNames") as? Bool ?? false,
            sortDetectReceiptsEnabled: defaults.object(forKey: "sort.detectReceipts") as? Bool ?? false,
            watchRecursiveOneLevel: defaults.bool(forKey: "watch.recursiveOneLevel"),
            savedPresetOrder: presets.map(\.id),
            globalSkipTagSet: Set(
                decodingGlobalSkipTags()
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            ),
            slowMode: defaults.object(forKey: "sort.slowModeEnabled") as? Bool ?? false,
            sortMoveLooseFoldersEnabled: defaults.object(forKey: "sort.moveLooseFolders.enabled") as? Bool ?? false,
            sortLooseFoldersDestinationRelative: defaults.string(forKey: "sort.moveLooseFolders.relativePath") ?? ""
        )
    }

    public func loadSessionHistory() -> [SortSessionHistoryRecord] {
        let data = defaults.data(forKey: "sessionHistoryData") ?? Data()
        return (try? JSONDecoder().decode([SortSessionHistoryRecord].self, from: data)) ?? []
    }

    /// Mirrors ``BinkyPreferences/appendSortOutcomeRecord`` so the CLI can persist undo-capable summaries.
    public func appendSortOutcomeRecord(_ outcome: SortBatchOutcome, fileManager: FileManager = .default) {
        guard let encodedOutcome = try? JSONEncoder().encode(outcome) else {
            return
        }

        let bytesMoved: Int64 = outcome.entries.reduce(into: 0) { sum, entry in
            guard entry.disposition == .moved, let dst = entry.destinationPath else { return }
            let attrs = try? fileManager.attributesOfItem(atPath: dst)
            sum += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }

        let record = SortSessionHistoryRecord(
            id: outcome.id,
            timestamp: outcome.started,
            fileCount: outcome.entries.count,
            totalBytesMoved: max(0, bytesMoved),
            formats: outcome.entries.isEmpty
                ? ["Downloads sort"]
                : Array(Set(outcome.entries.map(\.category.rawValue))).sorted(),
            batchSummaryData: encodedOutcome
        )

        var history = loadSessionHistory()
        history.insert(record, at: 0)
        history = Array(history.prefix(50))
        guard let blob = try? JSONEncoder().encode(history) else { return }
        defaults.set(blob, forKey: "sessionHistoryData")
        defaults.synchronize()
    }
}
