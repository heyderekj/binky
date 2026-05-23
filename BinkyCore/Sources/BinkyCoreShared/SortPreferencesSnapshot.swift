import Foundation

/// Frozen prefs and routing for one sort pass — safe to use from ``Task.detached``.
public struct SortPreferencesSnapshot: Sendable {
    public let excludeExtensions: Set<String>
    public let excludeNameFragments: [String]
    public let sortCustomRulesEnabled: Bool
    public let sortRoutingRules: [SortRule]
    public let sortAppendNewSemanticTagEnabled: Bool
    public let assignFinderTagsOnSortEnabled: Bool
    public let finderTagDefaultsByCategory: [String: [String]]
    public let globalInboxRoot: URL
    public let watchRegistry: WatchPipelineRegistry
    public let presetsByID: [UUID: Inbox]
    public let sortDuplicateMode: SortDuplicateHandlingMode
    public let sortSmartScreenshotNamesEnabled: Bool
    public let sortDetectReceiptsEnabled: Bool
    public let watchRecursiveOneLevel: Bool
    /// Preset / routine order (for combining rules when multiple routines share a folder).
    public let savedPresetOrder: [UUID]
    /// Lowercased Finder tags — files tagged with any of these are never sorted.
    public let globalSkipTagSet: Set<String>
    public let slowMode: Bool
    /// When true, immediate loose directories under each watch root move into the configured loose-folder destination (opaque; inner files are not harvested separately).
    public let sortMoveLooseFoldersEnabled: Bool
    /// Relative path under the sort root for loose folders; empty string means use ``FileSortCategory/folders`` default folder name.
    public let sortLooseFoldersDestinationRelative: String

    public init(
        excludeExtensions: Set<String>,
        excludeNameFragments: [String],
        sortCustomRulesEnabled: Bool,
        sortRoutingRules: [SortRule],
        sortAppendNewSemanticTagEnabled: Bool,
        assignFinderTagsOnSortEnabled: Bool,
        finderTagDefaultsByCategory: [String: [String]],
        globalInboxRoot: URL,
        watchRegistry: WatchPipelineRegistry,
        presetsByID: [UUID: Inbox],
        sortDuplicateMode: SortDuplicateHandlingMode,
        sortSmartScreenshotNamesEnabled: Bool,
        sortDetectReceiptsEnabled: Bool,
        watchRecursiveOneLevel: Bool,
        savedPresetOrder: [UUID],
        globalSkipTagSet: Set<String>,
        slowMode: Bool,
        sortMoveLooseFoldersEnabled: Bool,
        sortLooseFoldersDestinationRelative: String
    ) {
        self.excludeExtensions = excludeExtensions
        self.excludeNameFragments = excludeNameFragments
        self.sortCustomRulesEnabled = sortCustomRulesEnabled
        self.sortRoutingRules = sortRoutingRules
        self.sortAppendNewSemanticTagEnabled = sortAppendNewSemanticTagEnabled
        self.assignFinderTagsOnSortEnabled = assignFinderTagsOnSortEnabled
        self.finderTagDefaultsByCategory = finderTagDefaultsByCategory
        self.globalInboxRoot = globalInboxRoot
        self.watchRegistry = watchRegistry
        self.presetsByID = presetsByID
        self.sortDuplicateMode = sortDuplicateMode
        self.sortSmartScreenshotNamesEnabled = sortSmartScreenshotNamesEnabled
        self.sortDetectReceiptsEnabled = sortDetectReceiptsEnabled
        self.watchRecursiveOneLevel = watchRecursiveOneLevel
        self.savedPresetOrder = savedPresetOrder
        self.globalSkipTagSet = globalSkipTagSet
        self.slowMode = slowMode
        self.sortMoveLooseFoldersEnabled = sortMoveLooseFoldersEnabled
        self.sortLooseFoldersDestinationRelative = sortLooseFoldersDestinationRelative
    }
}

/// What to do when a file matches an existing hash (or near-duplicate image).
public enum SortDuplicateHandlingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case moveToDuplicates
    case moveToTrash

    public var id: String { rawValue }
}

extension SortPreferencesSnapshot {
    /// Sanitized relative path under the sort root for loose-folder moves; falls back to ``FileSortCategory/folders``.
    public func resolvedLooseFoldersRelativePath() -> String {
        let trimmed = sortLooseFoldersDestinationRelative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return FileSortCategory.folders.downloadsSubfolder }
        let parts = trimmed.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard !parts.isEmpty else { return FileSortCategory.folders.downloadsSubfolder }
        return parts.joined(separator: "/")
    }
}
