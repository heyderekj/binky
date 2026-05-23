import Foundation

// MARK: - Stage protocol

/// One unit of work in a Binky v2 sort pipeline.
///
/// **Why this exists**
///
/// v1's `SortWork` is a single 870-line type that performs classify, hash, OCR,
/// rule-match, move, tag, and shortcut-run inline, in order. This works but:
/// - You can't unit-test "did the classifier do the right thing on this URL?"
///   without a real filesystem and the whole supporting cast.
/// - You can't compose the steps differently for different entry points (Quick
///   Sort vs Watch vs CLI vs the upcoming Daily Calm proposal phase).
/// - You can't insert an AI-suggestion step between classify and move without
///   editing the 870-line monster.
///
/// `PipelineStage` flips that: each step is a small `Sendable` struct whose only
/// surface is `run(_:context:)`. Real stages (`ClassifyStage`, `HashStage`,
/// `AISuggestStage`, `MoveStage`, `TagStage`) will live in `BinkyCoreSort` once
/// the v2 migration starts moving logic out of `SortWork`. This file only fixes
/// the *shape*.
///
/// **Why not generics + `any` directly?**
///
/// `any PipelineStage<X, Y>` exists but doesn't compose well into a heterogeneous
/// pipeline (each stage's input type matches the previous stage's output, and the
/// chain is type-erased). We solve that with `AnyPipelineStage` below, plus a
/// concrete `PipelineRunner` that owns the boxing once.
public protocol PipelineStage<Input, Output>: Sendable {
    associatedtype Input
    associatedtype Output

    /// Process one input. Throwing aborts the entire run for this input — callers
    /// decide whether to record a failure row, retry, or surface the error to the
    /// user. Stages must honour `Task.checkCancellation()` inside any long loop.
    func run(_ input: Input, context: PipelineContext) async throws -> Output
}

// MARK: - Type-erasure

/// Type-erased wrapper so a heterogeneous pipeline can be expressed as `[AnyPipelineStage]`.
///
/// We pay a single allocation per stage at pipeline-build time; per-input cost
/// is just the closure call, identical to a direct generic dispatch in practice
/// (the closure captures the typed stage by value).
public struct AnyPipelineStage: Sendable {
    private let _run: @Sendable (Any, PipelineContext) async throws -> Any

    /// The static input type the wrapped stage expects, recorded so a builder
    /// can validate "stage N's `Output` == stage N+1's `Input`" before the run
    /// starts (rather than blowing up mid-pipeline with `as!`).
    public let inputType: Any.Type
    public let outputType: Any.Type

    public init<S: PipelineStage>(_ stage: S) {
        self.inputType = S.Input.self
        self.outputType = S.Output.self
        self._run = { anyInput, ctx in
            // Force-cast is safe iff the builder validated the chain (see
            // `PipelineRunner.validate`). If it isn't valid we'd rather crash
            // a developer-mode build loudly than silently produce wrong output.
            guard let typedInput = anyInput as? S.Input else {
                throw PipelineError.typeMismatch(
                    expected: String(describing: S.Input.self),
                    got: String(describing: type(of: anyInput))
                )
            }
            return try await stage.run(typedInput, context: ctx)
        }
    }

    @discardableResult
    public func runErased(_ input: Any, context: PipelineContext) async throws -> Any {
        try await _run(input, context)
    }
}

// MARK: - Errors

public enum PipelineError: Error, Equatable {
    /// Builder detected (or `AnyPipelineStage` detected at run-time) that stage N+1's
    /// input type is incompatible with stage N's output type.
    case typeMismatch(expected: String, got: String)

    /// `PipelineRunner.run` was called on an empty stage array.
    case emptyPipeline
}

// MARK: - Runner

/// Sequentially applies a list of stages to a single input, returning the final
/// `Output`. The runner is `Sendable` and intentionally keeps no state between
/// runs — concurrent calls are safe; each call gets its own `PipelineContext`.
///
/// We deliberately do NOT model parallelism here. Most v2 pipelines will be
/// per-file sequential, with an outer concurrency loop (`TaskGroup`) at the
/// orchestrator level fanning out across files. Mixing both layers in one type
/// is the kind of complexity that produced the v1 mess in the first place.
public struct PipelineRunner: Sendable {
    public let stages: [AnyPipelineStage]

    public init(stages: [AnyPipelineStage]) {
        self.stages = stages
    }

    /// Validates that adjacent stages' types line up. Call this once at pipeline
    /// build time; running an unvalidated pipeline will still surface a
    /// `PipelineError.typeMismatch` at runtime, but at the wrong layer for a good
    /// error message.
    public func validate() throws {
        guard !stages.isEmpty else { throw PipelineError.emptyPipeline }
        for i in 1..<stages.count {
            let prevOut = String(describing: stages[i - 1].outputType)
            let nextIn = String(describing: stages[i].inputType)
            if prevOut != nextIn {
                throw PipelineError.typeMismatch(expected: prevOut, got: nextIn)
            }
        }
    }

    /// Run the pipeline. Caller is responsible for the type of `input` matching
    /// `stages.first?.inputType`, and for casting the returned `Any` to the
    /// expected final output. A typed convenience wrapper will live in
    /// `BinkyCoreSort` once the first concrete pipeline is wired up.
    public func runErased(_ input: Any, context: PipelineContext = PipelineContext()) async throws -> Any {
        guard !stages.isEmpty else { throw PipelineError.emptyPipeline }
        var current: Any = input
        for stage in stages {
            try Task.checkCancellation()
            current = try await stage.runErased(current, context: context)
        }
        return current
    }
}
