import Foundation

// MARK: - Rename

public enum SortRenameStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none
    case datePrefix
    case template

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .none:
            return String(localized: "Keep original name", comment: "Sort rule rename style.")
        case .datePrefix:
            return String(localized: "Prefix with date (yyyy-MM-dd)", comment: "Sort rule rename style.")
        case .template:
            return String(localized: "Custom pattern", comment: "Sort rule rename style.")
        }
    }
}

// MARK: - Date predicate (Date Added / fallback)

public enum SortDateAddedPredicateKind: String, Codable, Hashable, Sendable {
    case none
    case newerThanDays
    case olderThanDays
}

public struct SortDateAddedPredicate: Codable, Equatable, Sendable {
    public var kind: SortDateAddedPredicateKind
    /// Ignored when kind is `.none`.
    public var days: Int

    public init(kind: SortDateAddedPredicateKind, days: Int) {
        self.kind = kind
        self.days = days
    }

    public static let disabled = SortDateAddedPredicate(kind: .none, days: 0)
}

// MARK: - Kind filter (UTType-aligned)

public enum SortFileKindFilter: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case any
    case image
    case movie
    case audio
    case archive
    case pdf
    case document

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .any:
            return String(localized: "Any kind", comment: "Sort rule kind filter.")
        case .image:
            return String(localized: "Images", comment: "Sort rule kind filter.")
        case .movie:
            return String(localized: "Video", comment: "Sort rule kind filter.")
        case .audio:
            return String(localized: "Audio", comment: "Sort rule kind filter.")
        case .archive:
            return String(localized: "Archives", comment: "Sort rule kind filter.")
        case .pdf:
            return String(localized: "PDF", comment: "Sort rule kind filter.")
        case .document:
            return String(localized: "Documents", comment: "Sort rule kind filter.")
        }
    }
}

// MARK: - Inbox aging

public enum FileAgingAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case archive
    case trash

    public var id: String { rawValue }
}

public struct CategoryAgingRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var categoryRaw: String
    public var untouchedDays: Int
    public var action: FileAgingAction
    public var archiveFolderRelative: String

    public static func fresh() -> CategoryAgingRule {
        CategoryAgingRule(
            id: UUID(),
            categoryRaw: "misc",
            untouchedDays: 30,
            action: .archive,
            archiveFolderRelative: "Archive"
        )
    }
}

// MARK: - Rule Finder tag policy

/// How a matched rule interacts with category-derived Finder tags (`FileSortCategory` defaults).
public enum SortRuleFinderTagPolicy: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Keep category defaults (global / profile / built-in), then apply ``SortRule/addedTags``.
    case additive
    /// Replace the category-default layer with ``SortRule/categoryDefaultReplacementTags``; profile custom tags and `addedTags` still apply after.
    case replaceCategoryDefault

    public var id: String { rawValue }
}

// MARK: - Content match (OCR / receipt rules)

public enum SortContentMatchKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none
    case ocrText
    case receipt
    case screenshot
    case photo
    case documentScan
    case ticket

    public var id: String { rawValue }

    /// Unknown raw values (a kind from a newer Binky) decode as `.none` instead of failing the whole rule list.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SortContentMatchKind(rawValue: raw) ?? .none
    }

    public var localizedTitle: String {
        switch self {
        case .none:
            return String(localized: "Any content", comment: "Sort rule: no content predicate.")
        case .ocrText:
            return String(localized: "Has readable text (OCR)", comment: "Sort rule content kind.")
        case .receipt:
            return String(localized: "Looks like receipt / invoice", comment: "Sort rule content kind.")
        case .screenshot:
            return String(localized: "Looks like a screenshot", comment: "Sort rule content kind.")
        case .photo:
            return String(localized: "Looks like a photo", comment: "Sort rule content kind: camera photo.")
        case .documentScan:
            return String(localized: "Looks like a scanned page", comment: "Sort rule content kind.")
        case .ticket:
            return String(localized: "Looks like a ticket or pass", comment: "Sort rule content kind: boarding pass, event ticket.")
        }
    }

    /// Kinds answered by looking at the picture rather than reading its text.
    public var isVisual: Bool {
        switch self {
        case .screenshot, .photo, .documentScan, .ticket: return true
        case .none, .ocrText, .receipt: return false
        }
    }

    /// Kinds that only match when the on-device model can see images (macOS 27+).
    /// Screenshots and photos fall back to file metadata on older releases.
    public var requiresVisionModel: Bool {
        self == .documentScan || self == .ticket
    }
}

public struct SortContentMatch: Codable, Equatable, Hashable, Sendable {
    public var kind: SortContentMatchKind

    public init(kind: SortContentMatchKind) {
        self.kind = kind
    }

    public static let disabled = SortContentMatch(kind: .none)
}

// MARK: - Rule match action

/// What happens when an inbox rule matches (before automatic taxonomy sort).
public enum SortRuleMatchAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case moveToDestination
    case moveToTrash
    case renameInPlace
    case zipToDestination
    case extractAndTrash
    case installFromDMG
    case tagFanout

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .moveToDestination:
            return String(localized: "Move to folder", comment: "Rule action: move to destination path.")
        case .moveToTrash:
            return String(localized: "Move to Trash", comment: "Rule action.")
        case .renameInPlace:
            return String(localized: "Rename here only", comment: "Rule action: stay in current folder, rename.")
        case .zipToDestination:
            return String(localized: "Zip into folder", comment: "Rule action: zip file into destination.")
        case .extractAndTrash:
            return String(localized: "Extract archive then trash", comment: "Rule action: expand zip/tar into destination.")
        case .installFromDMG:
            return String(localized: "Install app from disk image", comment: "Rule action: mount DMG, copy .app, trash DMG.")
        case .tagFanout:
            return String(localized: "Sort into subfolder by Finder tag", comment: "Rule action: tag-based fan-out.")
        }
    }
}

// MARK: - User-defined inbox rule

public struct SortRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var name: String
    /// Lowercased extensions without leading dot; empty = match any extension.
    public var matchExtensions: [String]
    /// Case-insensitive substring on full filename; empty = ignore.
    public var nameContains: String
    public var fileKindFilter: SortFileKindFilter
    public var minSizeBytes: Int64?
    public var maxSizeBytes: Int64?
    /// Compared against Date Added to folder when available, else creation date.
    public var dateAddedPredicate: SortDateAddedPredicate?
    /// Download origin: host glob per line, e.g. `*.stripe.com`, `figma.com`. Empty = any origin.
    public var originDomains: [String]
    /// Content-based predicate (OCR / receipt). Evaluated after basic signals when not `.none`.
    public var contentMatch: SortContentMatch
    /// File must carry at least one of these Finder tags (case-insensitive). Empty = ignore.
    public var matchTags: [String]
    /// When set, the final filename uses this extension instead of the original (no leading dot).
    public var outputExtension: String?
    /// Relative path under the inbox root (slashes for nested folders). Sanitized on use.
    public var destinationRelativePath: String
    public var renameStyle: SortRenameStyle
    /// Tokens: {date}, {stem}, {ext}, {n}, {origin}, {ocr}, {vendor}, {amount}
    public var renameTemplate: String
    /// Effect when this rule matches (default: move into ``destinationRelativePath``).
    public var matchAction: SortRuleMatchAction
    /// Finder tags merged when this rule matches (after category defaults and profile custom tags).
    public var addedTags: [String]
    /// When ``finderTagPolicy`` is ``SortRuleFinderTagPolicy/replaceCategoryDefault``, replaces the category-default tag layer (comma list → array in UI).
    public var finderTagPolicy: SortRuleFinderTagPolicy
    public var categoryDefaultReplacementTags: [String]

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, name, matchExtensions, nameContains, fileKindFilter
        case minSizeBytes, maxSizeBytes, dateAddedPredicate, destinationRelativePath, renameStyle, renameTemplate
        case matchAction
        case addedTags
        case finderTagPolicy
        case categoryDefaultReplacementTags
        case originDomains, contentMatch
        case matchTags, outputExtension
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        name = try c.decode(String.self, forKey: .name)
        matchExtensions = try c.decode([String].self, forKey: .matchExtensions)
        nameContains = try c.decode(String.self, forKey: .nameContains)
        fileKindFilter = try c.decode(SortFileKindFilter.self, forKey: .fileKindFilter)
        minSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .minSizeBytes)
        maxSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .maxSizeBytes)
        dateAddedPredicate = try c.decodeIfPresent(SortDateAddedPredicate.self, forKey: .dateAddedPredicate)
        destinationRelativePath = try c.decode(String.self, forKey: .destinationRelativePath)
        renameStyle = try c.decode(SortRenameStyle.self, forKey: .renameStyle)
        renameTemplate = try c.decode(String.self, forKey: .renameTemplate)
        matchAction = try c.decodeIfPresent(SortRuleMatchAction.self, forKey: .matchAction) ?? .moveToDestination
        addedTags = try c.decodeIfPresent([String].self, forKey: .addedTags) ?? []
        finderTagPolicy = try c.decodeIfPresent(SortRuleFinderTagPolicy.self, forKey: .finderTagPolicy) ?? .additive
        categoryDefaultReplacementTags = try c.decodeIfPresent([String].self, forKey: .categoryDefaultReplacementTags) ?? []
        originDomains = try c.decodeIfPresent([String].self, forKey: .originDomains) ?? []
        contentMatch = try c.decodeIfPresent(SortContentMatch.self, forKey: .contentMatch) ?? .disabled
        matchTags = try c.decodeIfPresent([String].self, forKey: .matchTags) ?? []
        let rawOut = try c.decodeIfPresent(String.self, forKey: .outputExtension)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
        outputExtension = (rawOut?.isEmpty == false) ? rawOut : nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(name, forKey: .name)
        try c.encode(matchExtensions, forKey: .matchExtensions)
        try c.encode(nameContains, forKey: .nameContains)
        try c.encode(fileKindFilter, forKey: .fileKindFilter)
        try c.encodeIfPresent(minSizeBytes, forKey: .minSizeBytes)
        try c.encodeIfPresent(maxSizeBytes, forKey: .maxSizeBytes)
        try c.encodeIfPresent(dateAddedPredicate, forKey: .dateAddedPredicate)
        try c.encode(destinationRelativePath, forKey: .destinationRelativePath)
        try c.encode(renameStyle, forKey: .renameStyle)
        try c.encode(renameTemplate, forKey: .renameTemplate)
        try c.encode(matchAction, forKey: .matchAction)
        try c.encode(addedTags, forKey: .addedTags)
        try c.encode(finderTagPolicy, forKey: .finderTagPolicy)
        try c.encode(categoryDefaultReplacementTags, forKey: .categoryDefaultReplacementTags)
        try c.encode(originDomains, forKey: .originDomains)
        try c.encode(contentMatch, forKey: .contentMatch)
        try c.encode(matchTags, forKey: .matchTags)
        try c.encodeIfPresent(outputExtension, forKey: .outputExtension)
    }

    public static func fresh(order: Int) -> SortRule {
        SortRule(
            id: UUID(),
            isEnabled: true,
            name: String(localized: "Rule \(order)", comment: "Default name for new sort rule; argument is order index."),
            matchExtensions: [],
            nameContains: "",
            fileKindFilter: .any,
            minSizeBytes: nil,
            maxSizeBytes: nil,
            dateAddedPredicate: nil,
            originDomains: [],
            contentMatch: .disabled,
            matchTags: [],
            outputExtension: nil,
            destinationRelativePath: "Misc",
            renameStyle: .none,
            renameTemplate: "{date} {stem}{ext}",
            matchAction: .moveToDestination,
            addedTags: [],
            finderTagPolicy: .additive,
            categoryDefaultReplacementTags: []
        )
    }

    public init(
        id: UUID,
        isEnabled: Bool,
        name: String,
        matchExtensions: [String],
        nameContains: String,
        fileKindFilter: SortFileKindFilter,
        minSizeBytes: Int64?,
        maxSizeBytes: Int64?,
        dateAddedPredicate: SortDateAddedPredicate?,
        originDomains: [String] = [],
        contentMatch: SortContentMatch = .disabled,
        matchTags: [String] = [],
        outputExtension: String? = nil,
        destinationRelativePath: String,
        renameStyle: SortRenameStyle,
        renameTemplate: String,
        matchAction: SortRuleMatchAction = .moveToDestination,
        addedTags: [String] = [],
        finderTagPolicy: SortRuleFinderTagPolicy = .additive,
        categoryDefaultReplacementTags: [String] = []
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.matchExtensions = matchExtensions
        self.nameContains = nameContains
        self.fileKindFilter = fileKindFilter
        self.minSizeBytes = minSizeBytes
        self.maxSizeBytes = maxSizeBytes
        self.dateAddedPredicate = dateAddedPredicate
        self.originDomains = originDomains
        self.contentMatch = contentMatch
        self.matchTags = matchTags
        self.outputExtension = outputExtension
        self.destinationRelativePath = destinationRelativePath
        self.renameStyle = renameStyle
        self.renameTemplate = renameTemplate
        self.matchAction = matchAction
        self.addedTags = addedTags
        self.finderTagPolicy = finderTagPolicy
        self.categoryDefaultReplacementTags = categoryDefaultReplacementTags
    }

}
