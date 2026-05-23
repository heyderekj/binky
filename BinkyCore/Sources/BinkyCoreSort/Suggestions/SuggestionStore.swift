import BinkyCoreShared
import Foundation

// MARK: - DecisionRecord

/// One persisted user decision about a `Suggestion`.
///
/// The record's identity is `(sourcePath, actionKey)` rather than the
/// `Suggestion.id` UUID — `Suggestion` UUIDs are minted fresh on every
/// engine call, so they're unstable across app launches. The
/// path-plus-action key matches `SuggestionEngine.merge`'s dedupe rule, which
/// means a Daily Calm "you already decided this" lookup behaves exactly the
/// same way the merge does.
public struct DecisionRecord: Codable, Equatable, Sendable {
    /// Standardized POSIX path of the source file.
    public let sourcePath: String

    /// Stable string form of the proposed action. See `SuggestionStore.actionKey`.
    public let actionKey: String

    public let decision: UserDecision

    public let decidedAt: Date

    public init(sourcePath: String, actionKey: String, decision: UserDecision, decidedAt: Date) {
        self.sourcePath = sourcePath
        self.actionKey = actionKey
        self.decision = decision
        self.decidedAt = decidedAt
    }
}

// MARK: - Store

/// Persists user decisions about `Suggestion`s so v2 can:
/// 1. Skip suggestions the user already rejected once (no nag).
/// 2. Promote suggestions the user accepted N times to "auto-apply" tier.
/// 3. Show a "you decided X about this last week" hint in Daily Calm.
///
/// **Storage format**
///
/// Append-only JSON-lines at
/// `~/Library/Application Support/Binky/v2-suggestions.jsonl`. Each line is
/// one `DecisionRecord` JSON object. Append-only means a write is one
/// `seekToEnd + write + write(\n)` — no parse-modify-rewrite of the whole
/// file. On read, we slurp the file once into an in-memory dict keyed by
/// `(sourcePath, actionKey)`. Later writes for the same key are still
/// appended (so the file is the audit log) but supersede earlier records in
/// the dict (so lookups return the latest decision).
///
/// We could've used SQLite (`FileHashStore` already does), but the
/// access pattern for decisions is "append once on user click, lookup
/// occasionally on render" — a few hundred records per power user per
/// year. JSON-lines keeps the file human-readable for debugging, doesn't
/// pull SQLite into a code path that doesn't need transactions, and the
/// in-memory dict makes lookups O(1).
///
/// **Concurrency**
///
/// `@unchecked Sendable` because the lock makes mutation safe. All public
/// methods take the lock once. The lazy hydration in `ensureLoaded` is
/// guarded so the first lookup pays the I/O cost; subsequent calls are pure
/// dict reads.
public final class SuggestionStore: @unchecked Sendable {

    public static let shared = SuggestionStore()

    private let storeURL: URL
    private let lock = NSLock()
    private var loaded = false
    private var byKey: [String: DecisionRecord] = [:]

    /// `directory: nil` → default location under Application Support. Tests
    /// pass a temp directory so they don't pollute the real store.
    public init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.storeURL = base.appendingPathComponent("v2-suggestions.jsonl")
    }

    private static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Binky", isDirectory: true)
    }

    // MARK: - API

    /// Latest persisted decision for the (source, action) pair, if any.
    public func decision(for suggestion: Suggestion) -> UserDecision? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return byKey[Self.dedupeKey(for: suggestion)]?.decision
    }

    /// Whole record (decision + timestamp) for the suggestion, or nil.
    public func record(for suggestion: Suggestion) -> DecisionRecord? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return byKey[Self.dedupeKey(for: suggestion)]
    }

    /// Persist a decision. Appends a new line; later reads will see the
    /// latest record for this (source, action) pair.
    public func record(_ suggestion: Suggestion, decision: UserDecision, at date: Date = Date()) {
        let entry = DecisionRecord(
            sourcePath: suggestion.source.standardizedFileURL.path,
            actionKey: Self.actionKey(for: suggestion.action),
            decision: decision,
            decidedAt: date
        )
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        byKey[Self.dedupeKey(for: suggestion)] = entry
        appendToDiskLocked(entry)
    }

    /// Number of unique (source, action) decisions known to the store.
    /// `Equatable`-style "two records with the same key" counts as one.
    public func recordCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return byKey.count
    }

    /// Remove every persisted decision and start fresh. Used by Settings →
    /// Privacy → "Forget v2 decisions" (when that lands) and by tests.
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        byKey.removeAll()
        try? FileManager.default.removeItem(at: storeURL)
        loaded = true // Mark loaded so the next ensureLoaded is a no-op.
    }

    /// All records where the user accepted a move action. Used by
    /// `DestinationPredictor` to learn from past decisions.
    public func allAcceptedMoveRecords() -> [DecisionRecord] {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return Array(byKey.values.filter { $0.decision == .accepted && $0.actionKey.hasPrefix("move:") })
    }

    // MARK: - Internals

    private func ensureLoadedLocked() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        // Split on LF. Trailing newline → trailing empty slice; skip those.
        for chunk in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let record = try? decoder.decode(DecisionRecord.self, from: Data(chunk)) else {
                continue
            }
            let key = Self.dedupeKey(forPath: record.sourcePath, actionKey: record.actionKey)
            byKey[key] = record // later record for same key overwrites earlier
        }
    }

    private func appendToDiskLocked(_ record: DecisionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: storeURL.path) {
            fm.createFile(atPath: storeURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: storeURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {
            // Best-effort: if disk is full or path went away, the in-memory
            // dict is still up to date for this session. Next launch will
            // miss this decision; that's the right failure mode for
            // append-only logs (vs corrupting the existing file).
        }
    }

    // MARK: - Keying

    static func dedupeKey(for suggestion: Suggestion) -> String {
        let actionKey = actionKey(for: suggestion.action)
        return dedupeKey(forPath: suggestion.source.standardizedFileURL.path, actionKey: actionKey)
    }

    static func dedupeKey(forPath path: String, actionKey: String) -> String {
        "\(path)|\(actionKey)"
    }

    /// Stable string form of `ProposedAction`. Mirrors
    /// `SuggestionEngine.dedupeKey`'s switch — duplicating ~10 lines of pure
    /// switch is cheaper than creating a shared protocol just to dodge
    /// duplication.
    static func actionKey(for action: ProposedAction) -> String {
        switch action {
        case .move(let dest):
            return "move:\(dest.standardizedFileURL.path)"
        case .rename(let name):
            return "rename:\(name)"
        case .trash:
            return "trash"
        case .keep:
            return "keep"
        case .runShortcut(let name):
            return "shortcut:\(name)"
        }
    }
}
