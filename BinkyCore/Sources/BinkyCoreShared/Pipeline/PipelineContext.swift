import Foundation

/// Information that travels alongside a value through every `PipelineStage` in a run.
///
/// We keep `PipelineContext` deliberately narrow at this stage. v2 will add fields
/// here as concrete stages need them (cancellation token, energy gate, progress
/// reporter, hash-store handle, etc.); the goal of the initial skeleton is just
/// to fix the *shape* — every stage takes `(input, context) async throws -> output`,
/// nothing more.
///
/// `Sendable` so stages can safely pass it across actor boundaries.
public struct PipelineContext: Sendable {
    /// Stable identifier for the run as a whole. Useful for log correlation
    /// (`os_signpost`, structured logs). Generated once at the entry point.
    public let runID: UUID

    /// Wall-clock time the run started — gives every stage a single source of
    /// truth for "now," which is essential for determinism in tests.
    public let startedAt: Date

    public init(runID: UUID = UUID(), startedAt: Date = Date()) {
        self.runID = runID
        self.startedAt = startedAt
    }
}
