import BinkyCoreShared
import Foundation

/// Coordinates `IngestionPipeline` and one or more `ContentSuggestionAdapter`s
/// into a single `URL → [Suggestion]` operation, with the merge / dedupe /
/// sort discipline Daily Calm relies on.
///
/// **Why this exists**
///
/// Adapters are intentionally single-source: a `HeuristicSuggestionAdapter`
/// might propose `move → ~/Documents/`, while a future
/// `FoundationModelsSuggestionAdapter` proposes `move → ~/Clients/Acme/` for
/// the same file. Without a coordinator, the consumer (Daily Calm UI, CLI
/// dry-run) would have to reason about how to merge the outputs themselves —
/// which is exactly the kind of cross-cutting logic that produced v1's
/// 870-line `SortWork`. `SuggestionEngine` keeps that discipline in one place.
///
/// **Concurrency**
///
/// Adapters run **in parallel** via a TaskGroup. One adapter throwing does
/// not abort the others — its output is treated as `[]` for the merge. This
/// mirrors what we want at the Daily Calm UI level: if a remote-AI adapter
/// happens to fail, the heuristic adapter's suggestions still land. Failure
/// of the underlying `IngestionPipeline` *does* propagate (no signals at all
/// is a different kind of failure than "one adapter had a bad day").
///
/// **Stateless across calls**
///
/// `SuggestionEngine` keeps no per-run state. Two concurrent calls to
/// `suggest(for:)` on the same engine instance are safe and isolated.
public struct SuggestionEngine: Sendable {
    private let pipeline: IngestionPipeline
    private let adapters: [any ContentSuggestionAdapter]

    public init(
        pipeline: IngestionPipeline = IngestionPipeline(),
        adapters: [any ContentSuggestionAdapter]
    ) {
        self.pipeline = pipeline
        self.adapters = adapters
    }

    /// URL entry: ingest first, then run adapters. Errors from the ingestion
    /// stages propagate (caller decides whether to surface as a row in Daily
    /// Calm or skip silently).
    public func suggest(
        for url: URL,
        context: PipelineContext = PipelineContext()
    ) async throws -> [Suggestion] {
        let ingested = try await pipeline.ingest(url, context: context)
        return await suggest(for: ingested, context: context)
    }

    /// IngestedFile entry: skip the pipeline (e.g. caller already ingested
    /// this file in a previous step and is now re-asking adapters with
    /// different config). Doesn't throw — adapter failures are absorbed.
    public func suggest(
        for ingested: IngestedFile,
        context: PipelineContext = PipelineContext()
    ) async -> [Suggestion] {
        guard !adapters.isEmpty else { return [] }

        // Run all adapters concurrently. We use TaskGroup (not async let) so
        // the pattern scales when a future engine has 3+ adapters wired in.
        var collected: [Suggestion] = []
        await withTaskGroup(of: [Suggestion].self) { group in
            for adapter in adapters {
                group.addTask {
                    // Adapter failure is absorbed: returning [] keeps the
                    // engine's contract simple ("you always get an array,
                    // possibly empty"). The cost of suppressing an error
                    // here is one fewer suggestion in this run; the cost of
                    // propagating it is the user losing every other adapter's
                    // output too. The latter is a worse UX trade.
                    (try? await adapter.suggest(for: ingested, context: context)) ?? []
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }
        return Self.merge(collected)
    }

    // MARK: - Merge / dedupe / sort

    /// Public for tests; the merge contract is part of the engine's behavior
    /// users can rely on (Daily Calm assumes ordering and uniqueness on
    /// what we hand it).
    public static func merge(_ suggestions: [Suggestion]) -> [Suggestion] {
        // Dedupe key collapses suggestions that propose the *same action* on
        // the *same source*. Two adapters arriving at the same conclusion
        // shouldn't crowd the UI with duplicates — we keep the higher-
        // confidence one.
        var byKey: [String: Suggestion] = [:]
        for s in suggestions {
            let key = dedupeKey(for: s)
            if let existing = byKey[key] {
                let existingConf = existing.confidence ?? 0
                let newConf = s.confidence ?? 0
                if newConf > existingConf {
                    byKey[key] = s
                }
            } else {
                byKey[key] = s
            }
        }

        // Sort: confidence descending, ties broken by createdAt ascending so
        // the order is deterministic across runs (essential for snapshot
        // tests and stable Daily Calm scrolling).
        return byKey.values.sorted { lhs, rhs in
            let lc = lhs.confidence ?? 0
            let rc = rhs.confidence ?? 0
            if lc != rc { return lc > rc }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func dedupeKey(for suggestion: Suggestion) -> String {
        let actionTag: String
        switch suggestion.action {
        case .move(let dest):
            actionTag = "move:\(dest.standardizedFileURL.path)"
        case .rename(let name):
            actionTag = "rename:\(name)"
        case .trash:
            actionTag = "trash"
        case .keep:
            actionTag = "keep"
        case .runShortcut(let name):
            actionTag = "shortcut:\(name)"
        }
        return "\(suggestion.source.standardizedFileURL.path)|\(actionTag)"
    }
}
