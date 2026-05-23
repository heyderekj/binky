import BinkyCoreShared
import Foundation

// MARK: - Aggregate output

/// Every signal v2's `SuggestionEngine` needs about a freshly-ingested file
/// before it decides what to propose.
///
/// We model it as a plain aggregate (not a builder / not a `var`-heavy struct)
/// because the producer is a single `IngestionPipeline.ingest(_:)` call and
/// the consumer (`SuggestionEngine`, `RuleEvaluator`) treats it read-only.
/// Mutating individual fields after ingestion would be a bug, so the type
/// makes that hard.
///
/// `hashed` is `Optional` because we deliberately skip hashing transient
/// files (`.crdownload`, hidden, Office lock) — see `IngestionPipeline.ingest`.
public struct IngestedFile: Equatable, Sendable {
    public let url: URL
    public let classification: ClassifiedFile
    public let originHosts: OriginHosts
    public let hashed: HashedFile?

    public init(
        url: URL,
        classification: ClassifiedFile,
        originHosts: OriginHosts,
        hashed: HashedFile? = nil
    ) {
        self.url = url
        self.classification = classification
        self.originHosts = originHosts
        self.hashed = hashed
    }

    /// Convenience: was hashing skipped because the file looked in-flight?
    public var hashSkippedBecauseTransient: Bool {
        hashed == nil && classification.isTransient
    }
}

// MARK: - Pipeline

/// Coordinates `ClassifyStage` + `OriginHostStage` + `HashStage` into one
/// `URL → IngestedFile` operation, with the right concurrency and skip rules.
///
/// **Why this is a separate type, not a `PipelineRunner` chain**
///
/// `PipelineRunner` is strictly sequential: stage N+1 consumes stage N's
/// output. Classify / origin / hash all consume the *same* input (the URL)
/// and produce *parallel* records that aggregate into `IngestedFile`. Forcing
/// them through `PipelineRunner` would either require a builder type that
/// every stage knows about (tight coupling) or a clever `flatMap`-style
/// merger inside the runner (more surface than warranted today).
///
/// `IngestionPipeline` keeps the stages independently testable while encoding
/// two real-world facts the v1 sort loop already gets right but inline:
///
/// 1. **Classify and origin can run concurrently.** Both are constant-time
///    metadata reads — running them in parallel saves ~1 ms per file on
///    SSDs, which compounds across batches of hundreds of files.
/// 2. **Hash is skipped when the file is transient.** Hashing a file that
///    Chrome is still writing produces a SHA of a partial download. v1
///    already filters transient files out before hashing; here we bake that
///    rule into the type signature (`hashed: HashedFile?`) so consumers
///    can't forget to handle the absence.
public struct IngestionPipeline: Sendable {
    private let classifyStage: ClassifyStage
    private let originStage: OriginHostStage
    private let hashStage: HashStage

    public init(
        classifyStage: ClassifyStage = ClassifyStage(),
        originStage: OriginHostStage = OriginHostStage(),
        hashStage: HashStage = HashStage()
    ) {
        self.classifyStage = classifyStage
        self.originStage = originStage
        self.hashStage = hashStage
    }

    /// Runs the ingestion stages and returns a fully-populated `IngestedFile`.
    ///
    /// **Concurrency**
    ///
    /// `classify` and `origin` start concurrently. Once `classify` completes
    /// we know whether to spawn `hash` at all (skipping it for transient
    /// files saves a full file read). This is the simplest schedule that
    /// preserves the v1 skip rule without launching speculative work we'd
    /// have to discard.
    ///
    /// Errors from any stage propagate immediately and abort the run. The
    /// caller decides whether to record the failure as a Suggestion-less
    /// row, retry, or surface to the user.
    public func ingest(
        _ url: URL,
        context: PipelineContext = PipelineContext()
    ) async throws -> IngestedFile {
        try Task.checkCancellation()

        async let classifiedTask = classifyStage.run(url, context: context)
        async let hostsTask = originStage.run(url, context: context)

        let classified = try await classifiedTask
        let hosts = try await hostsTask

        let hashed: HashedFile?
        if classified.isTransient {
            hashed = nil
        } else {
            try Task.checkCancellation()
            hashed = try await hashStage.run(url, context: context)
        }

        return IngestedFile(
            url: url,
            classification: classified,
            originHosts: hosts,
            hashed: hashed
        )
    }
}
