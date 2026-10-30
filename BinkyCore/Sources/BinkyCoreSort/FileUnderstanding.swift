import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import BinkyCoreShared

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Where a Review file probably belongs, and why, in a few words.
public struct ReviewSuggestion: Sendable, Equatable {
    /// Relative to the sort root, `/`-separated, already sanitized.
    public let destinationRelativePath: String
    /// "Looks like a tax form" — short enough for one line.
    public let reason: String
}

/// Apple Intelligence (on-device Foundation Models, macOS 26+) reading a single file:
/// where it should go, and what to call it. Everything returns `nil` when the model isn't
/// available, so callers keep today's behavior.
public enum FileUnderstanding {

    public static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    // MARK: - Review suggestions

    public static func suggestDestination(
        for url: URL,
        originHost: String?,
        existingFolders: [String]
    ) async -> ReviewSuggestion? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isModelAvailable else { return nil }
        let sample = await ContentInspector.textSample(for: url, maxChars: 1200)
        let folders = existingFolders
            .filter { !$0.hasPrefix(FileSortCategory.review.downloadsSubfolder) }
            .prefix(80)
            .map { "- \($0)" }
            .joined(separator: "\n")

        let instructions = """
        You help tidy a Downloads folder. Pick the folder a file belongs in.
        Prefer one of the existing folders. Suggest a new folder only when none fit,
        using a short, plain name (like Finance/Taxes). Never suggest Review.
        """
        let prompt = """
        File name: \(url.lastPathComponent)
        Downloaded from: \(originHost ?? "unknown")
        Text in the file:
        \(sample.isEmpty ? "(none)" : sample)

        Existing folders:
        \(folders.isEmpty ? "(none)" : folders)
        """
        guard let placement = await ask(Placement.self, instructions: instructions, prompt: prompt, imageOf: url) else {
            return nil
        }
        guard let path = sanitizedRelativePath(placement.destination) else { return nil }
        let reason = placement.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewSuggestion(destinationRelativePath: path, reason: String(reason.prefix(60)))
        #else
        return nil
        #endif
    }

    // MARK: - Smart names

    /// A short, specific title for a PDF or image ("Stripe invoice October"), without date or extension.
    /// `nil` when the model is unavailable or the file gives it nothing to go on.
    public static func suggestedTitle(for url: URL, originHost: String?) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isModelAvailable else { return nil }
        let sample = await ContentInspector.textSample(for: url, maxChars: 1200)
        let canSee = visionAvailable
        guard !sample.isEmpty || canSee else { return nil }

        let instructions = """
        Name a downloaded file so a person can find it later.
        Two to six words, specific: who it's from and what it is (like "Stripe invoice October"
        or "Lease agreement 14 Elm St"). No dates, no file extension, no quotes.
        """
        let prompt = """
        Current name: \(url.lastPathComponent)
        Downloaded from: \(originHost ?? "unknown")
        Text in the file:
        \(sample.isEmpty ? "(none)" : sample)
        """
        guard let out = await ask(FileTitle.self, instructions: instructions, prompt: prompt, imageOf: url) else {
            return nil
        }
        let title = sanitizedFilenameComponent(out.title)
        return title.split(separator: " ").count >= 2 ? title : nil
        #else
        return nil
        #endif
    }

    /// New filename for a PDF or image that arrived with a generic name, keeping its extension.
    /// Screenshots are left to the OCR namer. Cached per file so preview and sort agree without asking twice.
    static func preferredSmartDocumentName(fileURL: URL, category: FileSortCategory, originHost: String?) async -> String? {
        guard category != .screenshots, looksLikeGenericName(fileURL.lastPathComponent) else { return nil }
        guard !EnergyConditions.shared.shouldPauseFully else { return nil }

        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(fileURL.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)" as NSString
        if let hit = titleCache.object(forKey: key) {
            return hit.length == 0 ? nil : hit as String
        }

        let ext = fileURL.pathExtension
        let name = await suggestedTitle(for: fileURL, originHost: originHost).map { ext.isEmpty ? $0 : "\($0).\(ext)" }
        titleCache.setObject((name ?? "") as NSString, forKey: key)
        return name
    }

    private static let titleCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 200
        return cache
    }()

    /// True for camera, scanner and browser default names ("IMG_2041", "document (3)", "Scan 2026-10-02",
    /// a UUID) — names worth replacing. Anything a person typed is left alone.
    public static func looksLikeGenericName(_ baseName: String) -> Bool {
        let stem = (baseName as NSString).deletingPathExtension.lowercased()
        if UUID(uuidString: stem) != nil { return true }
        let filler: Set<String> = [
            "img", "image", "dsc", "dscn", "pxl", "photo", "scan", "scanned", "document", "doc", "file",
            "download", "downloads", "untitled", "copy", "export", "attachment", "pdf", "page", "screenshot",
            "at", "of", "am", "pm",
        ]
        let alphanumerics = stem.filter { $0.isLetter || $0.isNumber }
        let hexCount = stem.filter(\.isHexDigit).count
        if hexCount >= 16, Double(hexCount) >= Double(alphanumerics.count) * 0.8 { return true }
        // A token counts when its letters aren't camera/browser filler: "DSC01234" no, "W-2" yes.
        let meaningful = stem
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty && !filler.contains($0) }
        return meaningful.isEmpty
    }

    // MARK: - Folders

    /// Folders under `root`, as `/`-separated relative paths, sorted. Hidden folders are skipped.
    public static func relativeDirectoryPaths(under root: URL, maxDepth: Int, maxItems: Int) -> [String] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var collected: [String] = []
        func visit(_ url: URL, depth: Int) {
            guard collected.count < maxItems else { return }
            if depth > 0 {
                let path = url.standardizedFileURL.path
                if path.hasPrefix(rootPath) {
                    let rel = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if !rel.isEmpty { collected.append(rel) }
                }
            }
            guard depth < maxDepth, collected.count < maxItems else { return }
            guard let kids = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            let dirs = kids.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for dir in dirs {
                visit(dir, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return collected.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Up to three safe path segments; `nil` if nothing usable is left.
    static func sanitizedRelativePath(_ raw: String) -> String? {
        let segments = raw
            .split(separator: "/")
            .map { sanitizedFilenameComponent(String($0)) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .prefix(3)
        guard !segments.isEmpty else { return nil }
        let path = segments.joined(separator: "/")
        if path.lowercased().hasPrefix(FileSortCategory.review.downloadsSubfolder.lowercased()) { return nil }
        return path
    }

    static func sanitizedFilenameComponent(_ raw: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = String(raw.unicodeScalars.filter { !banned.contains($0) })
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " .")).prefix(60))
    }

    // MARK: - Model plumbing

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    fileprivate struct Placement {
        @Guide(description: "Why, starting with 'Looks like', under eight words. Example: Looks like a tax form")
        var reason: String
        @Guide(description: "Destination folder relative to the Downloads folder, levels separated by /")
        var destination: String
    }

    @available(macOS 26.0, *)
    @Generable
    fileprivate struct FileTitle {
        @Guide(description: "Two to six words naming the file")
        var title: String
    }

    private static var visionAvailable: Bool {
        if #available(macOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
        return false
    }

    /// One fresh session per question. On macOS 27 with vision, images and PDFs are shown to the model too.
    @available(macOS 26.0, *)
    private static func ask<T: Generable>(_ type: T.Type, instructions: String, prompt: String, imageOf url: URL) async -> T? {
        let session = LanguageModelSession(instructions: instructions)
        do {
            if #available(macOS 27.0, *), visionAvailable,
               let image = imageForModel(url) {
                return try await session.respond(generating: type) {
                    prompt
                    Attachment(image)
                }.content
            }
            return try await session.respond(to: prompt, generating: type).content
        } catch {
            return nil
        }
    }

    private static func imageForModel(_ url: URL) -> CGImage? {
        let ext = url.pathExtension.lowercased()
        let isPDF = ext == "pdf"
        guard isPDF || UTType(filenameExtension: ext)?.conforms(to: .image) == true else { return nil }
        return VisualClassifier.thumbnail(for: url, isPDF: isPDF, maxPixelSize: 768)
    }
    #endif
}
