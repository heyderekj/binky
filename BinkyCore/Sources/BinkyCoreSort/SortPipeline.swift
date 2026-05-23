import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers
import BinkyCoreShared

// MARK: - Transient filenames

/// File-name fragments that indicate a download or app temp file is still being written.
///
/// Coverage by tool:
/// - `.crdownload`, `.crswap` — Chrome / Chromium / Edge / Brave (newer builds use `.crswap` for atomic replacement of an in-progress file)
/// - `.download` — Safari, older WebKit downloaders
/// - `.part`, `.partial` — Firefox, plain HTTP downloaders
/// - `.opdownload` — Opera
/// - `.aria2` — aria2 download manager
/// - `.!ut` — µTorrent / qBittorrent in-progress chunks
/// - `~`, `.tmp`, `.temp` — generic editor/installer temp files
private let suspiciousSuffixes: [String] = [
    ".crdownload", ".crswap", ".download", ".part", ".partial",
    ".opdownload", ".aria2", ".!ut",
    "~", ".tmp", ".temp",
]

func looksTransientIncomplete(_ url: URL) -> Bool {
    let n = url.lastPathComponent.lowercased()
    if n == ".ds_store" { return false }
    // Microsoft Office writes hidden lock files like `~$Document.docx` while the file is open.
    // Treat the `~$` prefix the same way we treat dotfiles — never sortable.
    if n.hasPrefix("~$") { return true }
    if n.hasPrefix(".") { return true }
    return suspiciousSuffixes.contains(where: { n.hasSuffix($0) })
}

// MARK: - Stability waits

func waitUntilStable(
    at url: URL,
    maxSeconds: Double = 120,
    continueCheck: (() async -> Bool)? = nil
) async -> Bool {
    let fm = FileManager.default
    var lastBytes: Int64?
    var lastMod: Date?
    var unchangedHits = 0
    let end = Date().addingTimeInterval(maxSeconds)

    while Date() < end {
        if let continueCheck, await continueCheck() == false {
            return false
        }
        guard fm.fileExists(atPath: url.path) else { return false }
        do {
            let v = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let sz = Int64(v.fileSize ?? -1)
            let m = v.contentModificationDate
            if sz == lastBytes, m == lastMod {
                unchangedHits += 1
                if unchangedHits >= 2 {
                    try await Task.sleep(nanoseconds: 600_000_000)
                    return true
                }
            } else {
                unchangedHits = 0
            }
            lastBytes = sz
            lastMod = m
            try await Task.sleep(nanoseconds: 380_000_000)
        } catch {
            return false
        }
    }
    return false
}

/// Skips the multi-second stability poll when the file clearly finished landing (not a fresh download).
func fileLooksStableWithoutPolling(url: URL) -> Bool {
    guard !looksTransientIncomplete(url) else { return false }
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else { return false }
    guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey]),
          let modified = vals.contentModificationDate else {
        return false
    }
    let anchor = vals.addedToDirectoryDate.map { max($0, modified) } ?? modified
    return Date().timeIntervalSince(anchor) >= 3
}

func directoryLooksStableWithoutPolling(url: URL) -> Bool {
    guard !looksTransientIncomplete(url) else { return false }
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
    guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey]),
          let modified = vals.contentModificationDate else {
        return false
    }
    let anchor = vals.addedToDirectoryDate.map { max($0, modified) } ?? modified
    return Date().timeIntervalSince(anchor) >= 3
}

func waitUntilStableDirectory(
    at url: URL,
    maxSeconds: Double = 120,
    continueCheck: (() async -> Bool)? = nil
) async -> Bool {
    let fm = FileManager.default
    var lastMod: Date?
    var unchangedHits = 0
    let end = Date().addingTimeInterval(maxSeconds)

    while Date() < end {
        if let continueCheck, await continueCheck() == false {
            return false
        }
        guard fm.fileExists(atPath: url.path) else { return false }
        do {
            let v = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let m = v.contentModificationDate
            if m == lastMod {
                unchangedHits += 1
                if unchangedHits >= 2 {
                    try await Task.sleep(nanoseconds: 600_000_000)
                    return true
                }
            } else {
                unchangedHits = 0
            }
            lastMod = m
            try await Task.sleep(nanoseconds: 380_000_000)
        } catch {
            return false
        }
    }
    return false
}

public func isAppBundleURL(_ url: URL) -> Bool {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
    return url.pathExtension.lowercased() == "app"
}

// MARK: - Classification

func screenshotHeuristic(_ url: URL) -> Bool {
    let base = url.deletingPathExtension().lastPathComponent.lowercased()
    return base.contains("screen shot") || base.contains("screenshot") || base.hasPrefix("screenshot ")
}

enum FileClassification {

    /// Unknown → Review for trust-first behavior.
    static func categorize(url: URL) -> FileSortCategory {
        let ext = url.pathExtension.lowercased()

        if looksTransientIncomplete(url) { return .review }

        if isAppBundleURL(url) { return .apps }

        let archives: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
        let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif"]
        let videos: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"]
        let audio: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg"]
        let documentsNoPDF: Set<String> = ["doc", "docx", "rtf", "txt", "md", "pages", "key", "numbers", "ppt", "pptx", "xls", "xlsx", "csv", "json", "html", "xml", "swift"]
        /// PDF treated separately unless screenshot-like name.
        if ext == "pdf" {
            return screenshotHeuristic(url) ? .screenshots : .pdf
        }
        if ext == "dmg" || ext == "pkg" { return .apps }
        if archives.contains(ext) { return .archives }

        let utOptional = UTType(filenameExtension: ext)
        let utMatchesImage = utOptional?.conforms(to: .image) ?? false

        switch true {
        case utMatchesImage, images.contains(ext):
            return screenshotHeuristic(url) ? .screenshots : .images
        case utOptional?.conforms(to: .movie) == true || utOptional?.conforms(to: .video) == true || videos.contains(ext):
            return .video
        case utOptional?.conforms(to: .audio) == true || audio.contains(ext):
            return .audio
        case documentsNoPDF.contains(ext):
            return .documents
        case ext.isEmpty:
            return .review
        default:
            return .review
        }
    }
}

// MARK: - Finder tags (optional)

/// Applies Finder-visible tags via the `com.apple.metadata:_kMDItemUserTags` extended attribute,
/// avoiding Swift overlays that declare `NSURLResourceValues.tagNames` accessors only on macOS 26+.
public enum FinderTagApplicator {

    private static let xattrName = "com.apple.metadata:_kMDItemUserTags"

    /// Finder-visible tag display names on a file (from xattr), for rule matching / exclusions.
    static func readTagNames(for url: URL) -> [String] {
        normalizedTagStrings(existingPlistData(onPath: url.path))
    }

    /// - Returns: Whether the xattr write succeeded (or was a no-op merge).
    @discardableResult
    public static func merge(_ newTags: [String], onto url: URL) -> Bool {
        let trimmed = newTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return true }

        let path = url.path

        let existingNormalized = normalizedTagStrings(existingPlistData(onPath: path))
        let merged = Array(Set(existingNormalized).union(trimmed)).sorted()

        guard let data = try? PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0),
              merged != existingNormalized || existingPlistData(onPath: path) == nil
        else { return true }

        var ok = false
        path.withCString { cPath in
            data.withUnsafeBytes { ptr in
                guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else {
                    ok = false
                    return
                }
                let rc = Darwin.setxattr(cPath, xattrName, base, data.count, 0, 0)
                ok = (rc == 0)
            }
        }
        return ok
    }

    /// Removes tag names (case-insensitive) from Finder tags, rewriting the xattr as a simple string list.
    public static func remove(tagNames: Set<String>, from url: URL) {
        guard !tagNames.isEmpty else { return }
        let lower = Set(tagNames.map { $0.lowercased() })
        let path = url.path
        let existing = normalizedTagStrings(existingPlistData(onPath: path))
        let filtered = existing.filter { tag in
            let fragment = (tag.components(separatedBy: "\n").first ?? tag)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !lower.contains(fragment.lowercased())
        }
        guard filtered.count != existing.count else { return }

        if filtered.isEmpty {
            _ = path.withCString { Darwin.removexattr($0, xattrName, 0) }
            return
        }

        guard let data = try? PropertyListSerialization.data(fromPropertyList: filtered, format: .binary, options: 0)
        else { return }

        path.withCString { cPath in
            data.withUnsafeBytes { ptr in
                let buf = UnsafeRawPointer(ptr.bindMemory(to: UInt8.self).baseAddress!)
                let _ = Darwin.setxattr(cPath, xattrName, buf, data.count, 0, 0)
            }
        }
    }

    private static func existingPlistData(onPath path: String) -> Data? {
        let need = path.withCString { getxattr($0, xattrName, nil, 0, 0, 0) }
        guard need > 0 else { return nil }
        var raw = Data(count: need)
        let written = raw.withUnsafeMutableBytes { blob in
            path.withCString { getxattr($0, xattrName, blob.bindMemory(to: UInt8.self).baseAddress!, need, 0, 0) }
        }
        guard written == need else { return nil }
        return raw
    }

    private static func normalizedTagStrings(_ data: Data?) -> [String] {
        guard let data else { return [] }
        let plistOpt: Any? = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainers], format: nil)
        guard let obj = plistOpt else { return [] }
        switch obj {
        case let strings as [String]:
            return strings.map { String($0) }
        case let arr as NSArray:
            /// Modern Finder plist entries can bundle display text + Finder color identifiers in small dictionaries.
            return arr.flatMap(Self.tagStringFragments(fromTaggedPlistEntry:)).filter { !$0.isEmpty }
        default:
            return []
        }
    }

    private static func tagStringFragments(fromTaggedPlistEntry entry: Any) -> [String] {
        if let s = entry as? String { return [s.components(separatedBy: "\n").first ?? s] }
        if let dict = entry as? [String: Any] {
            for key in candidateTagDictionaryKeys {
                if let s = dict[key] as? String, !s.isEmpty { return [s.components(separatedBy: "\n").first ?? s] }
            }
        }
        return []
    }

    /// Keys sometimes present for serialized Finder-tag rows (varies by OS revision).
    private static let candidateTagDictionaryKeys: [String] = [
        "kMDItemUserTags",
        "NSDisplayString",
        "displayString",
        "tag",
        "_kMDItemUserTags",
        "NSTaggedFilenameKey",
    ]
}

private enum PostSortShortcutRunner {
    static func run(shortcutName: String, fileURL: URL) {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Use URLComponents to properly encode query parameters. The previous manual
        // percent-encoding with `CharacterSet.urlQueryAllowed` minus `&+=` still allowed `#`
        // through, which fragments the URL and truncates the shortcut name or input.
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: fileURL.absoluteString),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}

public func sortInboxContext(for fileURL: URL, snapshot: SortPreferencesSnapshot) -> (inboxRoot: URL, presets: [Inbox]) {
    let reg = snapshot.watchRegistry
    switch reg.routing(for: fileURL) {
    case .global:
        return (snapshot.globalInboxRoot, [])
    case .routine(let root, let ids):
        let idSet = Set(ids)
        let presets = snapshot.savedPresetOrder.compactMap { snapshot.presetsByID[$0] }.filter { idSet.contains($0.id) }
        return (root, presets)
    }
}

func isRasterImageExtensionForSort(_ ext: String) -> Bool {
    ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(ext)
}

func isURLExcludedForSort(url: URL, snapshot: SortPreferencesSnapshot) -> Bool {
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

func activeSortRulesForSnapshot(snapshot: SortPreferencesSnapshot, presets: [Inbox]) -> [SortRule] {
    let combined = presets.flatMap(\.sortRules)
    if !combined.isEmpty {
        return combined
    }
    return snapshot.sortCustomRulesEnabled ? snapshot.sortRoutingRules : []
}

func composedFinderTagsForSort(
    snapshot: SortPreferencesSnapshot,
    naturalCategory: FileSortCategory,
    presets: [Inbox],
    matchedRule: SortRule?
) -> [String] {
    FinderTagComposer.compose(
        naturalCategory: naturalCategory,
        globalDefaults: snapshot.finderTagDefaultsByCategory,
        preset: presets.first,
        matchedRule: matchedRule,
        appendNewSemanticTag: snapshot.sortAppendNewSemanticTagEnabled
    )
}

func fileURLMatchesGlobalSkipTags(_ url: URL, snapshot: SortPreferencesSnapshot) -> Bool {
    guard !snapshot.globalSkipTagSet.isEmpty else { return false }
    let tags = FinderTagApplicator.readTagNames(for: url)
    return tags.contains { snapshot.globalSkipTagSet.contains($0.lowercased()) }
}

func combinedTagFanoutPriority(presets: [Inbox]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for p in presets {
        for t in p.tagFanoutPriority {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let k = trimmed.lowercased()
            if seen.insert(k).inserted {
                out.append(trimmed)
            }
        }
    }
    return out
}

func newTagExpiryDays(from presets: [Inbox]) -> Int {
        presets.first(where: { $0.newTagExpiryDays > 0 })?.newTagExpiryDays ?? 0
}

func postSortShortcutName(from presets: [Inbox]) -> String {
    for p in presets {
        let t = p.postSortShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
    }
    return ""
}

func destinationDisplayLabelForSort(root: URL, destinationDir: URL) -> String {
    let rootPath = root.path
    let destPath = destinationDir.path
    guard destPath.hasPrefix(rootPath) else { return destinationDir.lastPathComponent }
    let tail = String(destPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return tail.isEmpty ? destinationDir.lastPathComponent : tail
}

func localizedMoveReasonForSort(matchedRuleName: String?, destinationDir: URL, inboxRoot: URL) -> String {
    let label = destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destinationDir)
    if let matchedRuleName {
        return String.localizedStringWithFormat(
            String(localized: "Moved into “%1$@” (rule “%2$@”).", comment: "Sort audit when a custom rule matched."),
            label,
            matchedRuleName
        )
    }
    return String.localizedStringWithFormat(
        String(localized: "Moved into “%@”.", comment: "Sort audit reason; formatted folder name."),
        label
    )
}

public final class SortRunGate: @unchecked Sendable {
    private enum ControlState {
        case running
        case paused
        case stopRequested
    }

    private let lock = NSLock()
    private var control: ControlState = .running
    private var sessionActive = true

    public init() {}

    public func setRunning() {
        lock.lock()
        control = .running
        lock.unlock()
    }

    public func setPaused() {
        lock.lock()
        control = .paused
        lock.unlock()
    }

    public func setStopRequested() {
        lock.lock()
        control = .stopRequested
        lock.unlock()
    }

    public func stopRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return control == .stopRequested
    }

    public func endSession() {
        lock.lock()
        sessionActive = false
        lock.unlock()
    }

    public func continueWhenSortPermitsProgress() async -> Bool {
        while true {
            let (c, active) = snapshot()
            if !active { return false }
            if c == .paused {
                try? await Task.sleep(for: .milliseconds(130))
                if Task.isCancelled { return false }
                continue
            }
            return c != .stopRequested
        }
    }

    private func snapshot() -> (ControlState, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (control, sessionActive)
    }
}

// MARK: - Parallel sort helpers

private struct SortIndexedFileResult: Sendable {
    let rows: [SortBatchEntry]
    let tagWriteFailures: Int
}

private actor SortRenameCounterActor {
    private var value = 1

    func nextValue(forRenameStyle style: SortRenameStyle) -> Int {
        let out = value
        if style != .none { value += 1 }
        return out
    }
}

/// Serializes uniquify + move into the same destination folder across concurrent sort tasks.
public final class PerDestinationUniquifyGate: @unchecked Sendable {
    private let master = NSLock()
    private var locks: [String: NSLock] = [:]

    public init() {}

    func sync<R>(directory: URL, _ body: () throws -> R) rethrows -> R {
        let key = directory.standardizedFileURL.path
        master.lock()
        let lock: NSLock
        if let existing = locks[key] {
            lock = existing
        } else {
            let fresh = NSLock()
            locks[key] = fresh
            lock = fresh
        }
        master.unlock()
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// Wraps `/usr/bin/ditto` zip creation with a post-write integrity check. `internal` rather than
/// `private` so the test target (`@testable import BinkyCoreSort`) can verify both the
/// happy-path zip-then-delete behavior and the failure path where a corrupted archive must not
/// trigger a source delete.
enum SortZipViaDitto {
    /// Creates a zip at `zipDestinationURL` from `sourceFile`, verifies the produced archive is
    /// readable, then removes the source on success.
    ///
    /// `ditto` returning exit 0 is necessary but not sufficient — a disk that fills mid-write or
    /// a half-flushed APFS snapshot can leave a truncated archive that ditto still considers a
    /// "successful" partial extract. We re-validate via `unzip -tq` before deleting the source so
    /// a corrupt archive never silently destroys the original.
    static func zipReplacingSource(file sourceFile: URL, zipDestinationURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: zipDestinationURL.path) {
            try fm.removeItem(at: zipDestinationURL)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", sourceFile.path, zipDestinationURL.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(
                domain: "BinkySortZip",
                code: Int(p.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Couldn’t create zip archive."]
            )
        }

        try verifyZipIntegrity(at: zipDestinationURL)

        try fm.removeItem(at: sourceFile)
    }

    /// Throws if the zip is missing, empty, or fails `unzip -tq` (CRC mismatch, truncation, etc).
    /// Cleans up the bad archive on failure so the caller can retry without colliding with itself.
    /// `internal` for direct testing — production code reaches it via `zipReplacingSource`.
    static func verifyZipIntegrity(at zipURL: URL) throws {
        let fm = FileManager.default

        // (1) Cheap size sanity check — a 0-byte file is never a valid zip and almost always means
        // the disk filled before ditto could write the central directory.
        let attrs = try fm.attributesOfItem(atPath: zipURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            try? fm.removeItem(at: zipURL)
            throw NSError(
                domain: "BinkySortZip",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Zip archive is empty after creation."]
            )
        }

        // (2) Structural check via `unzip -tq` (system tool, available on every macOS).
        let test = Process()
        test.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        test.arguments = ["-tq", zipURL.path]
        // Discard test output — `unzip -tq` prints "OK" on success, error detail on failure.
        let devNull = FileHandle(forWritingAtPath: "/dev/null")
        if let devNull {
            test.standardOutput = devNull
            test.standardError = devNull
        }
        do {
            try test.run()
        } catch {
            // Should be impossible (unzip ships with macOS), but if the launch itself fails,
            // err on the side of keeping the source file by treating the archive as bad.
            try? fm.removeItem(at: zipURL)
            throw NSError(
                domain: "BinkySortZip",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Couldn’t verify zip archive: \(error.localizedDescription)"]
            )
        }
        test.waitUntilExit()
        guard test.terminationStatus == 0 else {
            try? fm.removeItem(at: zipURL)
            throw NSError(
                domain: "BinkySortZip",
                code: Int(test.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Zip archive failed integrity check; original file kept."]
            )
        }
    }
}

public enum SortWork {
    nonisolated static func applyEnergyThrottleBetweenFiles(batchSize: Int, hooks: SortWorkHooks) async {
        if !EnergyConditions.shared.shouldPauseFully {
            if batchSize < SortEnergy.bigBatchFileCount {
                let sleepNanos = EnergyConditions.shared.interFileSleepNanos(batchSize: batchSize)
                if sleepNanos == 0 { return }
                try? await Task.sleep(nanoseconds: sleepNanos)
                return
            }
            await Task.yield()
            let sleepNanos = EnergyConditions.shared.interFileSleepNanos(batchSize: batchSize)
            if sleepNanos > 0 {
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
            return
        }
        let holdKind = EnergyConditions.shared.energyHoldKindForProgressUI()
        if let onHold = hooks.onEnergyHold {
            await MainActor.run { onHold(holdKind) }
        }
        await EnergyConditions.shared.waitUntilOK()
        if let clearHold = hooks.onEnergyHoldClear {
            await MainActor.run { clearHold() }
        }
        let sleepNanos = EnergyConditions.shared.interFileSleepNanos(batchSize: batchSize)
        if sleepNanos > 0 {
            try? await Task.sleep(nanoseconds: sleepNanos)
        }
    }

    /// Relocates loose directories under each watch root when enabled (sequential).
    nonisolated public static func runLooseFolderMoves(
        folderURLs: [URL],
        snapshot: SortPreferencesSnapshot,
        rootOverride: [URL: URL],
        destGate: PerDestinationUniquifyGate,
        gate: SortRunGate,
        progress: (@Sendable (SortProgressEvent) -> Void)?,
        hooks: SortWorkHooks
    ) async -> (rows: [SortBatchEntry], tagWriteFailures: Int) {
        guard snapshot.sortMoveLooseFoldersEnabled, !folderURLs.isEmpty else { return ([], 0) }
        let throttleDenom = max(1, folderURLs.count)
        var rows: [SortBatchEntry] = []
        var tagWriteFailures = 0
        let fm = FileManager.default
        let rel = snapshot.resolvedLooseFoldersRelativePath()

        for standardized in folderURLs {
            let standardized = standardized.standardizedFileURL
            guard await gate.continueWhenSortPermitsProgress() else { break }
            let pathKey = standardized.path
            let displayName = standardized.lastPathComponent

            progress?(.fileStarted(path: pathKey, displayName: displayName, animationBucket: FileSortCategory.folders.sortAnimationBucket))
            defer { progress?(.fileFinished(path: pathKey)) }

            if looksTransientIncomplete(standardized) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .review,
                    disposition: .skippedTransient,
                    reason: String(localized: "Temporary artifact — skipping folder until finalized.", comment: "Sort loose folder log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
                continue
            }

            let stableOK: Bool
            if directoryLooksStableWithoutPolling(url: standardized) {
                stableOK = true
            } else {
                stableOK = await waitUntilStableDirectory(at: standardized, continueCheck: {
                    await gate.continueWhenSortPermitsProgress()
                })
            }
            guard stableOK else {
                if gate.stopRequested() { break }
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .review,
                    disposition: .skippedStableCheckTimeout,
                    reason: String(localized: "Folder never stabilized before timeout.", comment: "Sort loose folder log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
                continue
            }

            if isURLExcludedForSort(url: standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .misc,
                    disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — matches your ignore list.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
                continue
            }

            if fileURLMatchesGlobalSkipTags(standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .misc,
                    disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — folder has a protected Finder tag.", comment: "Sort loose folder log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
                continue
            }

            let (defaultRoot, presets) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let destRoot = inboxRoot.appendingPathComponent(rel, isDirectory: true)

            let parent = standardized.deletingLastPathComponent().standardizedFileURL
            if parent == destRoot.standardizedFileURL {
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: standardized.path,
                    category: .folders,
                    disposition: .kept,
                    reason: String(localized: "Already in Folders destination.", comment: "Sort loose folder log."),
                    matchedRuleName: nil,
                    originHost: nil
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
                continue
            }

            do {
                let target = try destGate.sync(directory: destRoot) {
                    try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
                    return SortCollision.uniquify(
                        destinationDirectory: destRoot,
                        preferredFilename: standardized.lastPathComponent
                    )
                }
                if target.standardizedFileURL == standardized {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: standardized.path,
                        category: .folders,
                        disposition: .kept,
                        reason: String(localized: "Already at target path.", comment: "Sort loose folder log."),
                        matchedRuleName: nil,
                        originHost: nil
                    ))
                    await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
                    continue
                }
                try fm.moveItem(at: standardized, to: target)

                if snapshot.assignFinderTagsOnSortEnabled {
                    let tags = FinderTagComposer.compose(
                        naturalCategory: .folders,
                        globalDefaults: snapshot.finderTagDefaultsByCategory,
                        preset: presets.first,
                        matchedRule: nil,
                        appendNewSemanticTag: snapshot.sortAppendNewSemanticTagEnabled
                    )
                    let okTag = FinderTagApplicator.merge(tags, onto: target)
                    if !okTag { tagWriteFailures += 1 }
                }

                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: target.path,
                    category: .folders,
                    disposition: .moved,
                    reason: String(localized: "Moved loose folder into Folders destination.", comment: "Sort loose folder log."),
                    matchedRuleName: nil,
                    originHost: nil
                ))
            } catch {
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .folders,
                    disposition: .skippedError,
                    reason: error.localizedDescription,
                    matchedRuleName: nil,
                    originHost: nil
                ))
            }
            await applyEnergyThrottleBetweenFiles(batchSize: throttleDenom, hooks: hooks)
        }

        return (rows, tagWriteFailures)
    }

    /// Runs the per-file pipeline off the main actor. Progress closure is ``Sendable`` and safe to call from here.
    /// `rootOverride` lets the caller pin specific files to an ad-hoc inbox root (e.g. a right-clicked folder).
    nonisolated public static func runSortWorkLoop(
        workURLs: [URL],
        snapshot: SortPreferencesSnapshot,
        rootOverride: [URL: URL],
        gate: SortRunGate,
        progress: (@Sendable (SortProgressEvent) -> Void)?,
        hooks: SortWorkHooks,
        destGate: PerDestinationUniquifyGate? = nil
    ) async -> (rows: [SortBatchEntry], tagWriteFailures: Int) {
        guard !workURLs.isEmpty else { return (rows: [], tagWriteFailures: 0) }
        let batchSize = workURLs.count
        let destGateResolved = destGate ?? PerDestinationUniquifyGate()
        let renameCounter = SortRenameCounterActor()
        // Slow mode forces sequential processing so each file's progress UI is readable.
        let maxConcurrent = snapshot.slowMode
            ? 1
            : min(8, max(1, ProcessInfo.processInfo.processorCount))
        let runOne: @Sendable (URL) async -> SortIndexedFileResult = { standardized in
            let fm = FileManager.default
            var rows: [SortBatchEntry] = []
            var tagWriteFailures = 0

            guard await gate.continueWhenSortPermitsProgress() else {
                return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
            }
            let pathKey = standardized.path
            let displayName = standardized.lastPathComponent
            var didReportFileStarted = false
            defer {
                if didReportFileStarted {
                    progress?(.fileFinished(path: pathKey))
                }
            }

            func emitFileStarted(categoryForAnimation: FileSortCategory) {
                progress?(.fileStarted(path: pathKey, displayName: displayName, animationBucket: categoryForAnimation.sortAnimationBucket))
                didReportFileStarted = true
            }

            if looksTransientIncomplete(standardized) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .review)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .review, disposition: .skippedTransient,
                    reason: String(localized: "Temporary download artifact — skipping until finalized.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            guard await gate.continueWhenSortPermitsProgress() else {
                return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
            }
            let stableOK: Bool
            if isAppBundleURL(standardized) {
                if directoryLooksStableWithoutPolling(url: standardized) {
                    stableOK = true
                } else {
                    stableOK = await waitUntilStableDirectory(at: standardized, continueCheck: {
                        await gate.continueWhenSortPermitsProgress()
                    })
                }
            } else if fileLooksStableWithoutPolling(url: standardized) {
                stableOK = true
            } else {
                stableOK = await waitUntilStable(at: standardized, continueCheck: {
                    await gate.continueWhenSortPermitsProgress()
                })
            }
            guard stableOK else {
                if gate.stopRequested() {
                    return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
                }
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .review)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .review, disposition: .skippedStableCheckTimeout,
                    reason: String(localized: "File never stabilized before timeout.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            guard await gate.continueWhenSortPermitsProgress() else {
                return SortIndexedFileResult(rows: [], tagWriteFailures: 0)
            }
            if isURLExcludedForSort(url: standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .misc)
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: nil, category: .misc, disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — file matches your ignore list.", comment: "Sort log."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if fileURLMatchesGlobalSkipTags(standardized, snapshot: snapshot) {
                let oh = WhereFromsReader.primaryOriginHost(forFileAt: standardized)
                emitFileStarted(categoryForAnimation: .misc)
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: .misc,
                    disposition: .skippedExcluded,
                    reason: String(localized: "Skipped — file has a protected Finder tag.", comment: "Sort log: global skip tag."),
                    matchedRuleName: nil,
                    originHost: oh
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            let signals = SortRulesEvaluator.loadSignals(url: standardized)
                ?? SortRulesEvaluator.FileSignals(
                    ext: standardized.pathExtension.lowercased(),
                    baseName: standardized.lastPathComponent,
                    byteSize: 0,
                    addedToDirectoryDate: nil,
                    creationDate: nil,
                    modificationDate: nil,
                    originHosts: WhereFromsReader.originHosts(forFileAt: standardized)
                )

            let fileTags = FinderTagApplicator.readTagNames(for: standardized)

            let originHost = signals.originHosts.first

            let (defaultRoot, presets) = sortInboxContext(for: standardized, snapshot: snapshot)
            let inboxRoot = rootOverride[standardized] ?? defaultRoot
            let activeRules = activeSortRulesForSnapshot(snapshot: snapshot, presets: presets)

            var pendingFileDigest: (sha256: String, perceptual: UInt64?, isImage: Bool)?
            if snapshot.sortDuplicateMode != .off {
                do {
                    let digestTry = try FileHashStore.shared.digestFile(at: standardized)
                    let lookup = FileHashStore.shared.lookup(
                        sha256: digestTry.sha256,
                        perceptual: digestTry.perceptual,
                        isImage: digestTry.isImage
                    )
                    if lookup.isByteDuplicate || lookup.isNearImageDuplicate {
                        emitFileStarted(categoryForAnimation: .duplicates)
                        let dupReason = String(
                            localized: "Duplicate of a file Binky has seen before — skipping per your settings.",
                            comment: "Sort log duplicate."
                        )
                        if snapshot.sortDuplicateMode == .moveToTrash {
                            do {
                                try fm.trashItem(at: standardized, resultingItemURL: nil)
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: nil,
                                    category: .duplicates,
                                    disposition: .skippedDuplicate,
                                    reason: dupReason,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            } catch {
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: nil,
                                    category: .duplicates,
                                    disposition: .skippedError,
                                    reason: error.localizedDescription,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            }
                        } else {
                            let dupDir = StarterDestinations.directory(for: .duplicates, root: inboxRoot)
                            do {
                                let dest: URL = try destGateResolved.sync(directory: dupDir) {
                                    try fm.createDirectory(at: dupDir, withIntermediateDirectories: true)
                                    let destInner = SortCollision.uniquify(
                                        destinationDirectory: dupDir,
                                        preferredFilename: standardized.lastPathComponent
                                    )
                                    try fm.moveItem(at: standardized, to: destInner)
                                    return destInner
                                }
                                FileHashStore.shared.recordSortedFile(
                                    url: dest,
                                    sha256: digestTry.sha256,
                                    byteSize: signals.byteSize,
                                    perceptual: digestTry.perceptual,
                                    isImage: digestTry.isImage
                                )
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: dest.path,
                                    category: .duplicates,
                                    disposition: .moved,
                                    reason: dupReason,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            } catch {
                                rows.append(SortBatchEntry(
                                    id: UUID(),
                                    sourcePath: standardized.path,
                                    destinationPath: nil,
                                    category: .duplicates,
                                    disposition: .skippedError,
                                    reason: error.localizedDescription,
                                    matchedRuleName: nil,
                                    originHost: originHost
                                ))
                            }
                        }
                        await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                        return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
                    }
                    pendingFileDigest = (digestTry.sha256, digestTry.perceptual, digestTry.isImage)
                } catch {
                    pendingFileDigest = nil
                }
            }

            let taxonomyCategory = FileClassification.categorize(url: standardized)
            let ext = signals.ext
            let isImageFile = isRasterImageExtensionForSort(ext)
            let needsInspection =
                (snapshot.sortDetectReceiptsEnabled && (ext == "pdf" || isImageFile))
                || SortRulesEvaluator.anyRuleRequiresContentInspection(activeRules)
                || (snapshot.sortSmartScreenshotNamesEnabled && taxonomyCategory == .screenshots && isImageFile)

            let inspection: ContentInspector.ContentInspectionResult = if needsInspection {
                await ContentInspector.inspect(
                    for: standardized,
                    signals: signals,
                    snapshot: snapshot,
                    contentIdentitySHA256: pendingFileDigest?.sha256
                )
            } else {
                ContentInspector.emptyInspection
            }

            let contentInput = SortRulesEvaluator.ContentRuleMatchInput(
                hasSignificantOCR: inspection.hasSignificantOCR,
                isReceiptLike: inspection.isReceiptLike
            )
            let matchedRule = SortRulesEvaluator.firstMatchingRule(in: activeRules, signals: signals, content: contentInput, fileTags: fileTags)

            if let rule = matchedRule, rule.matchAction == .moveToTrash {
                emitFileStarted(categoryForAnimation: .misc)
                let trashReason = String.localizedStringWithFormat(
                    String(localized: "Trashed (rule “%@”).", comment: "Sort log when rule sends file to Trash."),
                    rule.name
                )
                do {
                    try fm.trashItem(at: standardized, resultingItemURL: nil)
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: .misc,
                        disposition: .moved,
                        reason: trashReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: .misc,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if let rule = matchedRule, rule.matchAction == .extractAndTrash {
                emitFileStarted(categoryForAnimation: .archives)
                let category = SortRulesEvaluator.customRuleTagCategory
                let destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                let extractReason = String.localizedStringWithFormat(
                    String(localized: "Extracted archive (rule “%@”).", comment: "Sort log extract rule."),
                    rule.name
                )
                do {
                    _ = try destGateResolved.sync(directory: destinationDir) {
                        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                    }
                    try ArchiveExtractionService.extract(source: standardized, destinationDirectory: destinationDir)
                    try fm.trashItem(at: standardized, resultingItemURL: nil)
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: destinationDir.path,
                        category: category,
                        disposition: .moved,
                        reason: extractReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: category,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if let rule = matchedRule, rule.matchAction == .installFromDMG {
                emitFileStarted(categoryForAnimation: .apps)
                let category = FileSortCategory.apps
                let appsDest: URL = {
                    if let p = presets.first {
                        return p.resolvedApplicationsInstallDirectory()
                    }
                    return FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications", isDirectory: true)
                        .standardizedFileURL
                }()
                let installReason = String.localizedStringWithFormat(
                    String(localized: "Installed from disk image (rule “%@”).", comment: "Sort log DMG install."),
                    rule.name
                )
                do {
                    let installed = try DMGInstallerService.installApps(fromDmg: standardized, applicationsDestination: appsDest)
                    try fm.trashItem(at: standardized, resultingItemURL: nil)
                    let destPath = installed.first?.path ?? appsDest.path
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: destPath,
                        category: category,
                        disposition: .moved,
                        reason: installReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: category,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            let useReceiptAutoRoute =
                matchedRule == nil
                && snapshot.sortDetectReceiptsEnabled
                && inspection.isReceiptLike
                && (ext == "pdf" || isImageFile)

            let category: FileSortCategory
            let destinationDir: URL
            var preferredFilename: String
            let ruleName: String?
            let naturalCategoryForTags: FileSortCategory
            let dominantOCRSlug: String? = inspection.dominantOCRLine.flatMap {
                let s = SortRulesEvaluator.slugifyForRenameToken(from: $0, maxLen: 60)
                return s.isEmpty ? nil : s
            }

            if let rule = matchedRule, rule.matchAction != .moveToTrash {
                category = SortRulesEvaluator.customRuleTagCategory
                if rule.matchAction == .renameInPlace {
                    destinationDir = standardized.deletingLastPathComponent().standardizedFileURL
                } else if rule.matchAction == .tagFanout {
                    destinationDir = SortRulesEvaluator.tagFanoutDestinationDirectory(
                        rule: rule,
                        inboxRoot: inboxRoot,
                        fileTags: fileTags,
                        priority: combinedTagFanoutPriority(presets: presets)
                    )
                } else {
                    destinationDir = SortRulesEvaluator.destinationDirectory(rule: rule, category: category, inboxRoot: inboxRoot)
                }
                let rc = await renameCounter.nextValue(forRenameStyle: rule.renameStyle)
                preferredFilename = SortRulesEvaluator.renamedFilename(
                    originalURL: standardized,
                    rule: rule,
                    renameCounter: rc,
                    originHost: originHost,
                    ocrSlug: dominantOCRSlug,
                    vendorSlug: inspection.vendorSlug,
                    amountSlug: inspection.amountSlug
                )
                ruleName = rule.name
                naturalCategoryForTags = taxonomyCategory
            } else if useReceiptAutoRoute {
                category = .receipts
                let vendorFolder = inspection.vendorSlug ?? "Receipt"
                destinationDir = StarterDestinations.directory(for: .receipts, root: inboxRoot)
                    .appendingPathComponent(vendorFolder, isDirectory: true)
                let df = ISO8601DateFormatter()
                df.formatOptions = [.withFullDate]
                let dateStr = df.string(from: Date())
                let amt = inspection.amountSlug ?? "0.00"
                preferredFilename = "\(vendorFolder) — \(dateStr) — \(amt).\(ext)"
                ruleName = nil
                naturalCategoryForTags = .receipts
            } else {
                category = taxonomyCategory
                destinationDir = StarterDestinations.directory(for: category, root: inboxRoot)
                preferredFilename = standardized.lastPathComponent
                if category == .screenshots, snapshot.sortSmartScreenshotNamesEnabled, isImageFile,
                   let smart = await ContentInspector.preferredSmartScreenshotName(
                    fileURL: standardized,
                    naturalCategory: category,
                    snapshot: snapshot,
                    signals: signals,
                    contentIdentitySHA256: pendingFileDigest?.sha256
                   ) {
                    preferredFilename = smart
                }
                ruleName = nil
                naturalCategoryForTags = taxonomyCategory
            }

            emitFileStarted(categoryForAnimation: category)

            if standardized.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL,
               standardized.lastPathComponent == preferredFilename {
                rows.append(SortBatchEntry(
                    id: UUID(), sourcePath: standardized.path, destinationPath: standardized.path, category: category, disposition: .kept,
                    reason: String(localized: "Already sorted into this destination.", comment: "Sort log."),
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            if let rule = matchedRule, rule.matchAction == .zipToDestination {
                let zipStem = standardized.deletingPathExtension().lastPathComponent
                let zipPreferred = "\(zipStem).zip"
                let zipReason = String.localizedStringWithFormat(
                    String(localized: "Zipped into “%1$@” (rule “%2$@”).", comment: "Sort log zip rule."),
                    destinationDisplayLabelForSort(root: inboxRoot, destinationDir: destinationDir),
                    rule.name
                )
                do {
                    let zipURL: URL = try destGateResolved.sync(directory: destinationDir) {
                        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                        return SortCollision.uniquify(destinationDirectory: destinationDir, preferredFilename: zipPreferred)
                    }
                    try SortZipViaDitto.zipReplacingSource(file: standardized, zipDestinationURL: zipURL)
                    if snapshot.assignFinderTagsOnSortEnabled {
                        let okTag = FinderTagApplicator.merge(
                            composedFinderTagsForSort(snapshot: snapshot, naturalCategory: naturalCategoryForTags, presets: presets, matchedRule: matchedRule),
                            onto: zipURL
                        )
                        if !okTag {
                            tagWriteFailures += 1
                        }
                    }
                    if snapshot.assignFinderTagsOnSortEnabled, snapshot.sortAppendNewSemanticTagEnabled,
                       newTagExpiryDays(from: presets) > 0, let regNew = hooks.registerNewTagExpiry {
                        let daysNew = newTagExpiryDays(from: presets)
                        await regNew(zipURL, daysNew)
                    }
                    let shortcut = postSortShortcutName(from: presets)
                    if !shortcut.isEmpty {
                        await MainActor.run {
                            PostSortShortcutRunner.run(shortcutName: shortcut, fileURL: zipURL)
                        }
                    }
                    if let digest = pendingFileDigest {
                        FileHashStore.shared.recordSortedFile(
                            url: zipURL,
                            sha256: digest.sha256,
                            byteSize: signals.byteSize,
                            perceptual: digest.perceptual,
                            isImage: digest.isImage
                        )
                    }
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: zipURL.path,
                        category: category,
                        disposition: .moved,
                        reason: zipReason,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                } catch {
                    rows.append(SortBatchEntry(
                        id: UUID(),
                        sourcePath: standardized.path,
                        destinationPath: nil,
                        category: category,
                        disposition: .skippedError,
                        reason: error.localizedDescription,
                        matchedRuleName: rule.name,
                        originHost: originHost
                    ))
                }
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            let target: URL
            do {
                target = try destGateResolved.sync(directory: destinationDir) {
                    try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
                    return SortCollision.uniquify(destinationDirectory: destinationDir, preferredFilename: preferredFilename)
                }
            } catch {
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: category,
                    disposition: .skippedError,
                    reason: error.localizedDescription,
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))
                await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
                return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
            }

            do {
                try fm.moveItem(at: standardized, to: target)

                if snapshot.assignFinderTagsOnSortEnabled {
                    let okTag = FinderTagApplicator.merge(
                        composedFinderTagsForSort(snapshot: snapshot, naturalCategory: naturalCategoryForTags, presets: presets, matchedRule: matchedRule),
                        onto: target
                    )
                    if !okTag {
                        tagWriteFailures += 1
                    }
                }

                if snapshot.assignFinderTagsOnSortEnabled, snapshot.sortAppendNewSemanticTagEnabled,
                   newTagExpiryDays(from: presets) > 0, let regNew = hooks.registerNewTagExpiry {
                    let daysNew = newTagExpiryDays(from: presets)
                    await regNew(target, daysNew)
                }

                let shortcut = postSortShortcutName(from: presets)
                if !shortcut.isEmpty {
                    await MainActor.run {
                        PostSortShortcutRunner.run(shortcutName: shortcut, fileURL: target)
                    }
                }

                if let digest = pendingFileDigest {
                    FileHashStore.shared.recordSortedFile(
                        url: target,
                        sha256: digest.sha256,
                        byteSize: signals.byteSize,
                        perceptual: digest.perceptual,
                        isImage: digest.isImage
                    )
                }

                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: target.path,
                    category: category,
                    disposition: .moved,
                    reason: localizedMoveReasonForSort(matchedRuleName: ruleName, destinationDir: destinationDir, inboxRoot: inboxRoot),
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))

            } catch {
                rows.append(SortBatchEntry(
                    id: UUID(),
                    sourcePath: standardized.path,
                    destinationPath: nil,
                    category: category,
                    disposition: .skippedError,
                    reason: error.localizedDescription,
                    matchedRuleName: ruleName,
                    originHost: originHost
                ))
            }

            await applyEnergyThrottleBetweenFiles(batchSize: batchSize, hooks: hooks)
            return SortIndexedFileResult(rows: rows, tagWriteFailures: tagWriteFailures)
        }

        var mergedRows: [SortBatchEntry] = []
        var mergedTagFails = 0
        let n = batchSize
        var slots: [SortIndexedFileResult?] = Array(repeating: nil, count: n)
        // 1.5s pacing fits the organizer empty-state flight (~1.25s) so each file’s card can land
        // before the next pulse (`OrganizerEmptyStateView.runFlightCycle`).
        let slowModeNanos: UInt64 = 1_500_000_000
        await withTaskGroup(of: (Int, SortIndexedFileResult).self) { group in
            var nextIndex = 0
            for _ in 0..<min(maxConcurrent, n) {
                let idx = nextIndex
                nextIndex += 1
                let url = workURLs[idx]
                group.addTask {
                    let r = await runOne(url)
                    return (idx, r)
                }
            }
            for await (idx, res) in group {
                slots[idx] = res
                if snapshot.slowMode, nextIndex < n {
                    try? await Task.sleep(nanoseconds: slowModeNanos)
                    guard await gate.continueWhenSortPermitsProgress() else { continue }
                }
                if nextIndex < n {
                    let j = nextIndex
                    nextIndex += 1
                    let url = workURLs[j]
                    group.addTask {
                        let r = await runOne(url)
                        return (j, r)
                    }
                }
            }
        }
        for i in 0..<n {
            if let s = slots[i] {
                mergedRows.append(contentsOf: s.rows)
                mergedTagFails += s.tagWriteFailures
            }
        }
        return (mergedRows, mergedTagFails)
    }
}
