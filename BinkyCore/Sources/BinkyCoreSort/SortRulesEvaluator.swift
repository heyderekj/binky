import BinkyCoreShared
import Foundation
import UniformTypeIdentifiers

// MARK: - Path safety

enum SortRulesEvaluator {

    /// Drops `.` / `..` segments so destinations cannot escape the inbox root.
    static func sanitizedRelativeDestination(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return FileSortCategory.misc.downloadsSubfolder }
        let parts = trimmed.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard !parts.isEmpty else { return FileSortCategory.misc.downloadsSubfolder }
        return parts.joined(separator: "/")
    }

    // MARK: - Exclusions

    static func isExcluded(url: URL, snapshot: SortPreferencesSnapshot) -> Bool {
        let ext = url.pathExtension.lowercased()
        if !snapshot.excludeExtensions.isEmpty, snapshot.excludeExtensions.contains(ext) {
            return true
        }
        let base = url.lastPathComponent
        for fragment in snapshot.excludeNameFragments {
            guard !fragment.isEmpty else { continue }
            if base.localizedCaseInsensitiveContains(fragment) {
                return true
            }
        }
        return false
    }

    // MARK: - Signals

    struct FileSignals: Sendable {
        let ext: String
        let baseName: String
        let byteSize: Int64
        let addedToDirectoryDate: Date?
        let creationDate: Date?
        let modificationDate: Date?
        /// Hosts from `kMDItemWhereFroms` (lowercased).
        let originHosts: [String]
    }

    /// Result of content inspection for routing rules (OCR / receipt).
    struct ContentRuleMatchInput: Equatable, Sendable {
        var hasSignificantOCR: Bool
        var isReceiptLike: Bool
        /// What the picture shows; empty when nobody asked or nothing could tell.
        var visualTraits: Set<SortVisualCategory> = []

        static let unknown = ContentRuleMatchInput(hasSignificantOCR: false, isReceiptLike: false)
    }

    /// - Parameter originHostsOverride: When non-nil, skips a second `com.apple.metadata:kMDItemWhereFroms` read (caller loaded hosts once).
    static func loadSignals(url: URL, originHostsOverride: [String]? = nil) -> FileSignals? {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .addedToDirectoryDateKey,
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        let sz = Int64(v.fileSize ?? 0)
        let hosts = originHostsOverride ?? WhereFromsReader.originHosts(forFileAt: url.standardizedFileURL)
        return FileSignals(
            ext: url.pathExtension.lowercased(),
            baseName: url.lastPathComponent,
            byteSize: sz,
            addedToDirectoryDate: v.addedToDirectoryDate,
            creationDate: v.creationDate,
            modificationDate: v.contentModificationDate,
            originHosts: hosts
        )
    }

    private static func referenceDateForAge(from signals: FileSignals) -> Date? {
        signals.addedToDirectoryDate ?? signals.creationDate ?? signals.modificationDate
    }

    // MARK: - Kind filter

    static func matchesKindFilter(_ filter: SortFileKindFilter, ext: String) -> Bool {
        switch filter {
        case .any:
            return true
        case .pdf:
            return ext == "pdf"
        case .archive:
            let archives: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
            return archives.contains(ext)
        case .image:
            let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif"]
            let ut = UTType(filenameExtension: ext)
            return images.contains(ext) || ut?.conforms(to: .image) == true
        case .movie:
            let videos: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"]
            let ut = UTType(filenameExtension: ext)
            return videos.contains(ext) || ut?.conforms(to: .movie) == true || ut?.conforms(to: .video) == true
        case .audio:
            let audio: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg"]
            let ut = UTType(filenameExtension: ext)
            return audio.contains(ext) || ut?.conforms(to: .audio) == true
        case .document:
            let documents: Set<String> = ["doc", "docx", "rtf", "txt", "md", "pages", "key", "numbers", "ppt", "pptx", "xls", "xlsx", "csv", "json", "html", "xml", "swift"]
            return documents.contains(ext)
        }
    }

    // MARK: - Rule match

    static func ruleMatches(_ rule: SortRule, signals: FileSignals, content: ContentRuleMatchInput? = nil, fileTags: [String] = []) -> Bool {
        guard rule.isEnabled else { return false }
        if !rule.matchExtensions.isEmpty {
            guard rule.matchExtensions.contains(signals.ext) else { return false }
        }
        let needle = rule.nameContains.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            guard signals.baseName.localizedCaseInsensitiveContains(needle) else { return false }
        }
        guard matchesKindFilter(rule.fileKindFilter, ext: signals.ext) else { return false }
        if let minB = rule.minSizeBytes, signals.byteSize < minB { return false }
        if let maxB = rule.maxSizeBytes, signals.byteSize > maxB { return false }
        guard matchesDatePredicate(rule.dateAddedPredicate, signals: signals) else { return false }

        let originPatterns = rule.originDomains
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if !originPatterns.isEmpty {
            guard WhereFromsReader.matchesAnyOriginPattern(originPatterns, hosts: signals.originHosts) else { return false }
        }

        let requiredTags = rule.matchTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !requiredTags.isEmpty {
            let lowerFileTags = Set(fileTags.map { $0.lowercased() })
            let ok = requiredTags.contains { req in
                lowerFileTags.contains(req.lowercased())
            }
            guard ok else { return false }
        }

        guard matchesContentPredicate(rule, content: content) else { return false }
        return true
    }

    private static func matchesContentPredicate(_ rule: SortRule, content: ContentRuleMatchInput?) -> Bool {
        switch rule.contentMatch.kind {
        case .none:
            return true
        case .ocrText:
            return content?.hasSignificantOCR == true
        case .receipt:
            return content?.isReceiptLike == true || content?.visualTraits.contains(.receipt) == true
        case .screenshot:
            return content?.visualTraits.contains(.screenshot) == true
        case .photo:
            return content?.visualTraits.contains(.photo) == true
        case .documentScan:
            return content?.visualTraits.contains(.documentScan) == true
        case .ticket:
            return content?.visualTraits.contains(.ticket) == true
        }
    }

    /// True when any enabled rule needs to know what a picture shows (screenshot, photo, scan, ticket).
    static func anyRuleRequiresVisualCategory(_ rules: [SortRule]) -> Bool {
        rules.contains { $0.isEnabled && $0.contentMatch.kind.isVisual }
    }

    private static func matchesDatePredicate(_ raw: SortDateAddedPredicate?, signals: FileSignals) -> Bool {
        guard let raw else { return true }
        switch raw.kind {
        case .none:
            return true
        case .newerThanDays, .olderThanDays:
            guard let ref = referenceDateForAge(from: signals) else { return false }
            let days = max(0, raw.days)
            let boundary = TimeInterval(days) * 24 * 3600
            let age = Date().timeIntervalSince(ref)
            switch raw.kind {
            case .newerThanDays:
                return age <= boundary
            case .olderThanDays:
                return age >= boundary
            default:
                return true
            }
        }
    }

    /// True when any enabled rule needs OCR or receipt matching.
    static func anyRuleRequiresContentInspection(_ rules: [SortRule]) -> Bool {
        rules.contains { $0.isEnabled && $0.contentMatch.kind != .none }
    }
    static func firstMatchingRule(in rules: [SortRule], signals: FileSignals, content: ContentRuleMatchInput? = nil, fileTags: [String] = []) -> SortRule? {
        for r in rules where r.isEnabled {
            if ruleMatches(r, signals: signals, content: content, fileTags: fileTags) { return r }
        }
        return nil
    }

    /// Slug for `{ocr}` / template tokens (safe filename fragment).
    static func slugifyForRenameToken(from raw: String, maxLen: Int) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(raw.unicodeScalars.filter { allowed.contains($0) })
        let parts = cleaned.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        var out = parts.joined(separator: "-")
        if out.count > maxLen {
            out = String(out.prefix(maxLen)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return out
    }

    // MARK: - Rename

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    static func renamedFilename(
        originalURL: URL,
        rule: SortRule?,
        renameCounter: Int,
        originHost: String? = nil,
        ocrSlug: String? = nil,
        vendorSlug: String? = nil,
        amountSlug: String? = nil
    ) -> String {
        let stem = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        let dotExt = ext.isEmpty ? "" : ".\(ext)"
        let newExtOptional = rule?.outputExtension?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
        let newDotExt: String = {
            guard let n = newExtOptional, !n.isEmpty else { return dotExt }
            return ".\(n)"
        }()
        let dateStr = isoDateFormatter.string(from: Date())
        let originLabel = WhereFromsReader.sanitizedOriginLabel(forHost: originHost ?? originalURL.host)

        guard let rule else {
            return originalURL.lastPathComponent
        }

        func applyTemplateTokens(_ tpl: String) -> String {
            let ocr = (ocrSlug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ven = (vendorSlug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let amt = (amountSlug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return tpl
                .replacingOccurrences(of: "{date}", with: dateStr)
                .replacingOccurrences(of: "{stem}", with: stem)
                .replacingOccurrences(of: "{ext}", with: dotExt)
                .replacingOccurrences(of: "{newExt}", with: newDotExt)
                .replacingOccurrences(of: "{n}", with: "\(renameCounter)")
                .replacingOccurrences(of: "{counter}", with: "\(renameCounter)")
                .replacingOccurrences(of: "{origin}", with: originLabel.isEmpty ? "unknown-origin" : originLabel)
                .replacingOccurrences(of: "{ocr}", with: ocr.isEmpty ? stem : ocr)
                .replacingOccurrences(of: "{vendor}", with: ven.isEmpty ? "vendor" : ven)
                .replacingOccurrences(of: "{amount}", with: amt.isEmpty ? "amount" : amt)
        }

        func filenameWithOutputExtension(_ baseName: String) -> String {
            guard let n = newExtOptional, !n.isEmpty else { return baseName }
            let s = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
            return "\(s).\(n)"
        }

        switch rule.renameStyle {
        case .none:
            return filenameWithOutputExtension(originalURL.lastPathComponent)
        case .datePrefix:
            return filenameWithOutputExtension("\(dateStr) \(stem)\(dotExt)")
        case .template:
            let tpl = rule.renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tpl.isEmpty else { return filenameWithOutputExtension(originalURL.lastPathComponent) }
            return filenameWithOutputExtension(applyTemplateTokens(tpl))
        }
    }

    /// Destination directory URL under inbox root for a rule or taxonomy category.
    static func destinationDirectory(rule: SortRule?, category: FileSortCategory, inboxRoot: URL) -> URL {
        if let rule {
            let rel = sanitizedRelativeDestination(rule.destinationRelativePath)
            return inboxRoot.appendingPathComponent(rel, isDirectory: true)
        }
        return StarterDestinations.directory(for: category, root: inboxRoot)
    }

    /// Category used for Finder tags when a custom rule matched (neutral destination).
    static var customRuleTagCategory: FileSortCategory { .misc }

    // MARK: - Tag fan-out

    static func sanitizedTagFolderSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untagged" }
        return trimmed
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolvedFanoutTag(fileTags: [String], priority: [String]) -> String? {
        for p in priority {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if fileTags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                return t
            }
        }
        return fileTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.first
    }

    static func tagFanoutDestinationDirectory(rule: SortRule, inboxRoot: URL, fileTags: [String], priority: [String]) -> URL {
        let base = destinationDirectory(rule: rule, category: customRuleTagCategory, inboxRoot: inboxRoot)
        let tag = resolvedFanoutTag(fileTags: fileTags, priority: priority)
        let segment = sanitizedTagFolderSegment(tag ?? "Untagged")
        return base.appendingPathComponent(segment, isDirectory: true)
    }
}
