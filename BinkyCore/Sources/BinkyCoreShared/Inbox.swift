import Foundation

/// Named sorting routine: source folder, routing rules, and tag defaults. JSON persists under legacy keys (`savedPresetsData`).
public struct SortingRoutine: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    /// When true, this routine participates in folder watching when its source path resolves.
    public var isEnabled: Bool

    public var watchFolderPath: String
    public var watchFolderBookmark: Data

    public var customFinderTags: [String]
    /// Optional per-`FileSortCategory` default Finder tags (keys = category raw values). Empty map = use globals / built-ins.
    public var finderTagDefaultsByCategory: [String: [String]]
    public var sortRules: [SortRule]
    public var newTagExpiryDays: Int
    public var postSortShortcutName: String

    /// First matching entry wins when a file has multiple Finder tags for ``SortRuleMatchAction/tagFanout``.
    public var tagFanoutPriority: [String]

    /// Destination for ``installFromDMG`` (copy `.app` here). Empty = `~/Applications`.
    public var applicationsInstallPath: String
    public var applicationsInstallBookmark: Data

    public let createdAt: Date

    /// One-shot migration: legacy `watchFolderModeRaw == "global"` meant “use global watch path”.
    private var legacyUsedGlobalWatchFolder: Bool

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.isEnabled = false
        self.watchFolderPath = ""
        self.watchFolderBookmark = Data()
        self.customFinderTags = []
        self.finderTagDefaultsByCategory = [:]
        self.sortRules = []
        self.newTagExpiryDays = 0
        self.postSortShortcutName = ""
        self.tagFanoutPriority = []
        self.applicationsInstallPath = ""
        self.applicationsInstallBookmark = Data()
        self.createdAt = .now
        self.legacyUsedGlobalWatchFolder = false
    }

    public init(duplicating source: SortingRoutine, name: String) {
        self.id = UUID()
        self.name = name
        self.isEnabled = source.isEnabled
        self.watchFolderPath = source.watchFolderPath
        self.watchFolderBookmark = source.watchFolderBookmark
        self.customFinderTags = source.customFinderTags
        self.finderTagDefaultsByCategory = source.finderTagDefaultsByCategory
        self.sortRules = source.sortRules
        self.newTagExpiryDays = source.newTagExpiryDays
        self.postSortShortcutName = source.postSortShortcutName
        self.tagFanoutPriority = source.tagFanoutPriority
        self.applicationsInstallPath = source.applicationsInstallPath
        self.applicationsInstallBookmark = source.applicationsInstallBookmark
        self.createdAt = .now
        self.legacyUsedGlobalWatchFolder = false
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now

        if let ie = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) {
            isEnabled = ie
        } else {
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .watchFolderEnabled) ?? false
        }

        watchFolderPath = try c.decodeIfPresent(String.self, forKey: .watchFolderPath) ?? ""
        watchFolderBookmark = try c.decodeIfPresent(Data.self, forKey: .watchFolderBookmark) ?? Data()

        if let rawMode = try c.decodeIfPresent(String.self, forKey: .watchFolderModeRaw) {
            let normalized = (rawMode == "destination") ? "global" : rawMode
            legacyUsedGlobalWatchFolder = (normalized == "global")
        } else {
            legacyUsedGlobalWatchFolder = try c.decodeIfPresent(Bool.self, forKey: .legacyUsedGlobalWatchFolder) ?? false
        }

        customFinderTags = try c.decodeIfPresent([String].self, forKey: .customFinderTags) ?? []
        finderTagDefaultsByCategory = try c.decodeIfPresent([String: [String]].self, forKey: .finderTagDefaultsByCategory) ?? [:]
        sortRules = try c.decodeIfPresent([SortRule].self, forKey: .sortRules) ?? []
        newTagExpiryDays = try c.decodeIfPresent(Int.self, forKey: .newTagExpiryDays) ?? 0
        postSortShortcutName = try c.decodeIfPresent(String.self, forKey: .postSortShortcutName) ?? ""
        tagFanoutPriority = try c.decodeIfPresent([String].self, forKey: .tagFanoutPriority) ?? []
        applicationsInstallPath = try c.decodeIfPresent(String.self, forKey: .applicationsInstallPath) ?? ""
        applicationsInstallBookmark = try c.decodeIfPresent(Data.self, forKey: .applicationsInstallBookmark) ?? Data()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(watchFolderPath, forKey: .watchFolderPath)
        try c.encode(watchFolderBookmark, forKey: .watchFolderBookmark)
        try c.encode(customFinderTags, forKey: .customFinderTags)
        try c.encode(finderTagDefaultsByCategory, forKey: .finderTagDefaultsByCategory)
        try c.encode(sortRules, forKey: .sortRules)
        try c.encode(newTagExpiryDays, forKey: .newTagExpiryDays)
        try c.encode(postSortShortcutName, forKey: .postSortShortcutName)
        try c.encode(tagFanoutPriority, forKey: .tagFanoutPriority)
        try c.encode(applicationsInstallPath, forKey: .applicationsInstallPath)
        try c.encode(applicationsInstallBookmark, forKey: .applicationsInstallBookmark)
        try c.encode(false, forKey: .legacyUsedGlobalWatchFolder)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, createdAt
        case watchFolderPath, watchFolderBookmark
        case watchFolderEnabled, watchFolderModeRaw
        case customFinderTags, finderTagDefaultsByCategory, newTagExpiryDays, postSortShortcutName
        // Preserve the legacy on-disk key so existing user data keeps decoding after the rename.
        case sortRules = "inboxSortRules"
        case tagFanoutPriority, applicationsInstallPath, applicationsInstallBookmark
        case legacyUsedGlobalWatchFolder
    }

    public mutating func hydrateLegacyGlobalWatchIfNeeded(globalPath: String, globalBookmark: Data) {
        guard legacyUsedGlobalWatchFolder else { return }
        legacyUsedGlobalWatchFolder = false
        if watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let p = globalPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty {
                watchFolderPath = (p as NSString).standardizingPath
                watchFolderBookmark = globalBookmark
            }
        }
    }

    /// Destination for ``SortRuleMatchAction/installFromDMG``. Empty path = `~/Applications`.
    public func resolvedApplicationsInstallDirectory(fileManager: FileManager = .default) -> URL {
        let trimmed = applicationsInstallPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !applicationsInstallBookmark.isEmpty {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: applicationsInstallBookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return url.standardizedFileURL
                }
            }
        }
        if trimmed.isEmpty {
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .standardizedFileURL
        }
        if trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    /// Finder-style unique routine name among existing names.
    public static func uniqueDuplicatePresetName(baseName: String, existingNames: Set<String>) -> String {
        let copyFrag = String(localized: " copy", comment: "Filename: first duplicate after base name, as in Finder “file copy”.")
        var n = 1
        while true {
            let candidate: String
            if n == 1 {
                candidate = baseName + copyFrag
            } else {
                candidate = baseName + copyFrag + " \(n)"
            }
            if !existingNames.contains(candidate) { return candidate }
            n += 1
        }
    }

    /// Subtitle for routine lists (sidebar, Settings).
    public var organizerListSubtitle: String {
        var parts: [String] = []

        if isEnabled {
            if watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(String(localized: "Folder not set", comment: "Routine subtitle when watch path empty."))
            } else {
                parts.append(URL(fileURLWithPath: watchFolderPath).lastPathComponent)
            }
        } else {
            parts.append(String(localized: "Off", comment: "Routine subtitle when disabled."))
        }

        let tagCount = customFinderTags.count
        if tagCount == 1 {
            parts.append(String(localized: "1 tag", comment: "Routine subtitle: single custom tag."))
        } else if tagCount > 1 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lld tags", comment: "Routine subtitle: multiple custom Finder tags."),
                Int64(tagCount)
            ))
        }

        let ruleCount = sortRules.count
        if ruleCount == 1 {
            parts.append(String(localized: "1 rule", comment: "Routine subtitle: single sort rule."))
        } else if ruleCount > 1 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lld rules", comment: "Routine subtitle: multiple sort rules."),
                Int64(ruleCount)
            ))
        }

        if newTagExpiryDays > 0 {
            parts.append(String.localizedStringWithFormat(
                String(localized: "%lldd \u{201C}New\u{201D}", comment: "Routine subtitle: New-tag expiry in days."),
                Int64(newTagExpiryDays)
            ))
        }

        let trimmedShortcut = postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedShortcut.isEmpty {
            parts.append("→ \(trimmedShortcut)")
        }

        if parts.isEmpty {
            return String(localized: "Default routing", comment: "Routine subtitle when no detail.")
        }
        return parts.joined(separator: " · ")
    }
}

/// Backward-compatible alias for saved presets / profiles.
public typealias Inbox = SortingRoutine
