import Foundation

extension WatchPipelineRegistry {
    init(prefs: BinkyPreferences) {
        let gpResolved: String? = {
            guard prefs.folderWatchEnabled else { return nil }
            if let resolved = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: prefs.watchedFolderBookmark,
                storedPath: prefs.watchedFolderPath
            ) {
                return resolved
            }
            let downloads = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
            return WatchFolderPathResolver.normalizedPath(downloads.path)
        }()

        var auto: [(UUID, String)] = []
        for a in prefs.savedPresets where a.isEnabled {
            guard let raw = WatchFolderPathResolver.resolvedWatchDirectoryPath(
                bookmark: a.watchFolderBookmark,
                storedPath: a.watchFolderPath
            ) else { continue }
            auto.append((a.id, raw))
        }

        self.init(globalPath: gpResolved, routinePaths: auto)
    }
}

extension BinkyPreferences {
    /// Inbox layout root and routines contributing rules for files routed through folder watch.
    func sortContext(for fileURL: URL) -> (inboxRoot: URL, presets: [Inbox]) {
        let reg = WatchPipelineRegistry(prefs: self)
        switch reg.routing(for: fileURL) {
        case .global:
            return (downloadsSortRootDirectory(), [])
        case .routine(let root, let ids):
            let idSet = Set(ids)
            let presets = savedPresets.filter { idSet.contains($0.id) }
            return (root, presets)
        }
    }
}
