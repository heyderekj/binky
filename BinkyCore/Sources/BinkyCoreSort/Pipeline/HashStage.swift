import BinkyCoreShared
import Foundation

// MARK: - Output

/// Output of `HashStage`. Pairs a URL with its SHA-256 digest, optional
/// perceptual hash (set only for raster image extensions), and an `isImage`
/// flag derived from the same extension list.
///
/// `Sendable` so the chain can fan in/out across actors freely.
public struct HashedFile: Equatable, Sendable {
    public let url: URL
    public let sha256: String
    public let perceptual: UInt64?
    public let isImage: Bool

    public init(url: URL, sha256: String, perceptual: UInt64? = nil, isImage: Bool = false) {
        self.url = url
        self.sha256 = sha256
        self.perceptual = perceptual
        self.isImage = isImage
    }
}

// MARK: - Stage

/// Reads the file at `input` and produces a `HashedFile`.
///
/// **Why a separate stage**
///
/// In v1, `SortWork.processOne` calls `FileHashStore.shared.digestFile(at:)`
/// inline. That couples the per-file hashing to the rest of the loop and
/// makes it impossible to:
///
/// 1. **Unit test** rule paths that depend on `isImage` / `perceptual`
///    without hitting a real filesystem and reading actual image bytes.
/// 2. **Swap implementations** — e.g. compute hashes from a memory buffer
///    when the file is already in cache, or skip the perceptual hash on
///    huge RAW files.
///
/// `HashStage` exposes a `Hasher` typealias (a `@Sendable` closure) so tests
/// inject deterministic stubs. The default hasher delegates to
/// `FileHashStore.shared.digestFile(at:)`, which itself honors task
/// cancellation between 512 KB chunks and writes through the persistent
/// SQLite cache via `recordSortedFile`. We don't reproduce that machinery
/// here.
///
/// **Performance note**
///
/// `digestFile` reads the whole file (raw image extensions read it twice —
/// once for SHA-256, once via ImageIO for the perceptual hash). For very
/// large files (>1 GB RAW), the read dominates everything else in the
/// pipeline. The cancellation hook inside `FileHashStore.digestFile` lets
/// the user stop a sort run mid-hash within ~one chunk, which is the
/// maximum useful resolution for cooperative cancellation here.
public struct HashStage: PipelineStage {
    public typealias Input = URL
    public typealias Output = HashedFile

    /// Synchronous hashing closure. The `@Sendable` annotation lets `HashStage`
    /// remain `Sendable` (and therefore safe to compose into concurrent
    /// pipelines) even though it captures arbitrary user-injected logic.
    public typealias Hasher = @Sendable (URL) throws -> (sha256: String, perceptual: UInt64?, isImage: Bool)

    private let hasher: Hasher

    /// Default hasher — calls `FileHashStore.shared.digestFile(at:)`. Tests
    /// pass a closure that returns canned values for fixture URLs.
    public init(hasher: Hasher? = nil) {
        self.hasher = hasher ?? { url in
            try FileHashStore.shared.digestFile(at: url)
        }
    }

    public func run(_ input: URL, context: PipelineContext) async throws -> HashedFile {
        // Honor cancellation before starting an expensive I/O read. The hasher
        // itself also checks cancellation between chunks (see
        // FileHashStore.digestFile) — this is the outer guard so a cancellation
        // raised between stages doesn't trigger a wasted file open.
        try Task.checkCancellation()
        let result = try hasher(input)
        return HashedFile(
            url: input,
            sha256: result.sha256,
            perceptual: result.perceptual,
            isImage: result.isImage
        )
    }
}
