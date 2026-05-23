import BinkyCoreShared
import Foundation

// MARK: - Output

/// Output of `ClassifyStage`. Pairs a URL with the category it routes to and
/// whether the URL was classified as transient (e.g. `.crdownload`, hidden
/// file, Office lock) — the latter is exposed so subsequent stages can short-
/// circuit to a "skip, retry later" branch instead of re-checking the URL.
public struct ClassifiedFile: Equatable, Sendable {
    public let url: URL
    public let category: FileSortCategory
    /// `true` when the file looks like an in-progress / system artifact and should
    /// not be moved this pass. Mirrors `looksTransientIncomplete(_:)` semantics
    /// from `SortPipeline.swift`.
    public let isTransient: Bool

    public init(url: URL, category: FileSortCategory, isTransient: Bool = false) {
        self.url = url
        self.category = category
        self.isTransient = isTransient
    }
}

// MARK: - Stage

/// First stage of the Binky v2 sort pipeline: turns a raw `URL` into a
/// `ClassifiedFile`.
///
/// **Why this exists as a separate type**
///
/// v1 calls `FileClassification.categorize(url:)` inline from inside
/// `SortWork.processOne`. That tied the classification heuristic to the rest of
/// the v1 sort loop and made it untestable without a fixture filesystem. v2's
/// `PipelineStage` shape gives us a single `(URL) -> ClassifiedFile` boundary
/// we can mock, swap out (e.g. for an AI-based classifier), and unit-test with
/// nothing but a synthetic URL.
///
/// **Behavior parity with v1**
///
/// This stage is intentionally a thin wrapper over the existing static helpers
/// (`FileClassification.categorize`, `looksTransientIncomplete`). The v1 sort
/// loop continues to call those helpers directly — they are the single source
/// of truth. When v2 wiring is ready, the call sites in `SortWork.processOne`
/// will be replaced by a `ClassifyStage` invocation, at which point the static
/// helpers can be made internal-only or folded into the stage.
public struct ClassifyStage: PipelineStage {
    public typealias Input = URL
    public typealias Output = ClassifiedFile

    public init() {}

    public func run(_ input: URL, context: PipelineContext) async throws -> ClassifiedFile {
        let transient = looksTransientIncomplete(input)
        let category = FileClassification.categorize(url: input)
        return ClassifiedFile(url: input, category: category, isTransient: transient)
    }
}
