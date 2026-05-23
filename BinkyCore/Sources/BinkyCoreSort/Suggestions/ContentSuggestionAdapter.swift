import BinkyCoreShared
import Foundation

// MARK: - Adapter protocol

/// Source of `Suggestion`s for a single ingested file.
///
/// `SuggestionEngine` (next session) will hold one or more adapters and merge
/// their outputs. We deliberately keep adapters single-source — they never
/// know about each other and never call back into the engine. That makes
/// them trivially mockable and lets us run them in parallel when more than
/// one is configured.
///
/// Returning an empty array means "no opinion." The engine treats that as a
/// neutral signal (other adapters can still propose; if no one proposes,
/// the file shows up in Daily Calm with the user's manual options only).
public protocol ContentSuggestionAdapter: Sendable {
    func suggest(
        for ingested: IngestedFile,
        context: PipelineContext
    ) async throws -> [Suggestion]
}

// MARK: - Inbox-root resolver

/// Strategy for "given a category, where do you want it filed?" Adapters need
/// this to translate `FileSortCategory.images` etc. into a concrete URL for
/// `ProposedAction.move(to:)`.
///
/// Decoupling this from `BinkyPreferences` means the adapter test suite
/// doesn't need to spin up `UserDefaults` plumbing — tests just pass a
/// closure mapping category → fixture URL.
public typealias InboxRootResolver = @Sendable (FileSortCategory) -> URL

// MARK: - Heuristic adapter (works everywhere, no AI)

/// Conservative, deterministic suggestions derived purely from the signals
/// already in `IngestedFile` — extension/UTType classification, transient
/// flag, and (when present) WhereFroms host. Runs on macOS 14+ unchanged.
///
/// **Confidence policy**
///
/// We cap heuristic confidence at 0.6: enough to surface in Daily Calm and
/// be the default selected action, but not high enough that the engine
/// would auto-apply the suggestion under any "approved N times → auto" rule
/// the future SuggestionEngine adds. AI adapters running on macOS 26 can
/// raise confidence past that threshold when they see corroborating signal.
///
/// **Decision 1a alignment**
///
/// Per the Calm Inbox redesign, macOS 14–25 keeps the same Daily Calm UI
/// driven entirely by this adapter — no visible AI downgrade banner. The
/// difference is purely in what `Suggestion.reasoning` reads (heuristic
/// language vs. semantic language) and in confidence ceiling.
public struct HeuristicSuggestionAdapter: ContentSuggestionAdapter {
    private let inboxRoot: InboxRootResolver
    private let predictor: DestinationPredictor?

    public init(inboxRoot: @escaping InboxRootResolver, predictor: DestinationPredictor? = nil) {
        self.inboxRoot = inboxRoot
        self.predictor = predictor
    }

    public func suggest(
        for ingested: IngestedFile,
        context: PipelineContext
    ) async throws -> [Suggestion] {
        // Transient files (in-flight downloads, Office locks, hidden) → no
        // proposal yet. The engine will re-ingest them once they stabilize.
        if ingested.classification.isTransient { return [] }

        // Files we routed to .review get no automatic suggestion — that's
        // exactly what Review is for: explicit human decision.
        if ingested.classification.category == .review { return [] }

        let category = ingested.classification.category

        // Intent-based: use DestinationPredictor if available (learns from history).
        // Falls back to type-based default when no predictor or no history.
        if let predictor {
            let candidates = predictor.predict(
                for: ingested.url,
                category: category,
                originHost: ingested.originHosts.primary
            )
            guard !candidates.isEmpty else {
                return [typeFallbackSuggestion(for: ingested)]
            }
            return candidates.map { candidate in
                Suggestion(
                    source: ingested.url,
                    action: .move(to: candidate.url),
                    confidence: candidate.confidence,
                    reasoning: candidate.reason
                )
            }
        }

        // No predictor → single type-based suggestion (cold start / tests).
        return [typeFallbackSuggestion(for: ingested)]
    }

    private func typeFallbackSuggestion(for ingested: IngestedFile) -> Suggestion {
        let category = ingested.classification.category
        return Suggestion(
            source: ingested.url,
            action: .move(to: inboxRoot(category)),
            confidence: 0.4,
            reasoning: Self.reasoning(for: ingested)
        )
    }

    /// One-line user-visible explanation. Currently English-only — will be
    /// converted to a structured reason enum (`HeuristicReason`) and
    /// localized at the view layer once Daily Calm UI lands. See decision 5
    /// in docs/v2-progress.md.
    static func reasoning(for ingested: IngestedFile) -> String {
        let cat = ingested.classification.category
        if let host = ingested.originHosts.primary {
            return "From \(host) — looks like \(categoryNoun(cat))."
        }
        return "Looks like \(categoryNoun(cat))."
    }

    private static func categoryNoun(_ category: FileSortCategory) -> String {
        switch category {
        case .images: return "an image"
        case .pdf: return "a PDF"
        case .video: return "a video"
        case .audio: return "audio"
        case .documents: return "a document"
        case .archives: return "an archive"
        case .apps: return "an installer"
        case .screenshots: return "a screenshot"
        case .receipts: return "a receipt"
        case .duplicates: return "a duplicate"
        case .folders: return "a folder"
        case .misc, .review: return "an unknown file"
        }
    }
}

// MARK: - Foundation Models adapter (macOS 26+; placeholder)

/// Eventual home for the `FoundationModels` (Apple Intelligence) integration
/// that will read the file's content and propose semantic moves / renames.
///
/// **Status: placeholder.** The real implementation needs:
///  - macOS 26 SDK access to the `FoundationModels` API surface.
///  - A test device with Apple Intelligence enabled (Apple Silicon, region-
///    eligible account).
///  - Apple Developer ID for distribution (see decision 4 — currently 'no').
///
/// Until those are in place, this adapter returns `[]` so the engine can
/// already reason about "AI not available, fall back to heuristic" without
/// the caller branching on macOS version. The engine will eventually skip
/// instantiating this adapter at all on pre-26 systems; for now, returning
/// empty is equivalent.
public struct FoundationModelsSuggestionAdapter: ContentSuggestionAdapter {
    private let inboxRoot: InboxRootResolver

    public init(inboxRoot: @escaping InboxRootResolver) {
        self.inboxRoot = inboxRoot
    }

    public func suggest(
        for ingested: IngestedFile,
        context: PipelineContext
    ) async throws -> [Suggestion] {
        // TODO(v2.x): implement once macOS 26 + Apple Intelligence is on the
        // build/test path. Read PDF text or image OCR via FoundationModels,
        // produce semantic move/rename proposals with confidence > 0.6.
        // Until then we explicitly produce nothing so the engine's "merge
        // adapter outputs" code path stays on a known branch.
        _ = inboxRoot   // silence unused warning until the real impl arrives
        return []
    }
}
