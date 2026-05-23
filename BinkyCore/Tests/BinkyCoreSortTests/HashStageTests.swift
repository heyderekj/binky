import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

final class HashStageTests: XCTestCase {

    private let ctx = PipelineContext()

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("HashStageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - With injected hasher (most tests live here)

    func test_returnsHashedFile_withSha256_fromInjectedHasher() async throws {
        let stage = HashStage(hasher: { _ in
            (sha256: "abc123", perceptual: nil, isImage: false)
        })
        let input = URL(fileURLWithPath: "/tmp/binky-tests/file.txt")
        let result = try await stage.run(input, context: ctx)
        XCTAssertEqual(result.url, input)
        XCTAssertEqual(result.sha256, "abc123")
        XCTAssertNil(result.perceptual)
        XCTAssertFalse(result.isImage)
    }

    func test_carriesPerceptualHash_whenHasherProvidesOne() async throws {
        let stage = HashStage(hasher: { _ in
            (sha256: "img-sha", perceptual: 0xDEAD_BEEF_1234_5678, isImage: true)
        })
        let result = try await stage.run(
            URL(fileURLWithPath: "/tmp/binky-tests/photo.jpg"),
            context: ctx
        )
        XCTAssertEqual(result.perceptual, 0xDEAD_BEEF_1234_5678)
        XCTAssertTrue(result.isImage)
    }

    func test_propagatesHasherError() async {
        struct ReadFailed: Error, Equatable {}
        let stage = HashStage(hasher: { _ in throw ReadFailed() })
        do {
            _ = try await stage.run(URL(fileURLWithPath: "/x.pdf"), context: ctx)
            XCTFail("expected ReadFailed")
        } catch is ReadFailed {
            // expected
        } catch {
            XCTFail("expected ReadFailed, got \(error)")
        }
    }

    // MARK: - Cancellation

    func test_throwsCancellation_whenTaskCancelledBeforeRun() async {
        let stage = HashStage(hasher: { _ in
            XCTFail("hasher should not be invoked when the task is already cancelled")
            return (sha256: "", perceptual: nil, isImage: false)
        })

        let task = Task<HashedFile, Error> {
            try await stage.run(URL(fileURLWithPath: "/x.pdf"), context: ctx)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    // MARK: - HashedFile struct

    func test_hashedFile_isEquatable() {
        let a = HashedFile(url: URL(fileURLWithPath: "/x"), sha256: "abc", perceptual: 1, isImage: true)
        let b = HashedFile(url: URL(fileURLWithPath: "/x"), sha256: "abc", perceptual: 1, isImage: true)
        XCTAssertEqual(a, b)
    }

    func test_hashedFile_defaultsForOptionalFields() {
        let f = HashedFile(url: URL(fileURLWithPath: "/x"), sha256: "abc")
        XCTAssertNil(f.perceptual)
        XCTAssertFalse(f.isImage)
    }

    // MARK: - Pipeline integration

    func test_hashStage_composesWithPipelineRunner() async throws {
        let stage = HashStage(hasher: { _ in (sha256: "fixed", perceptual: nil, isImage: false) })
        let runner = PipelineRunner(stages: [AnyPipelineStage(stage)])
        let url = URL(fileURLWithPath: "/tmp/binky-tests/x.pdf")
        let result = try await runner.runErased(url)
        let hashed = try XCTUnwrap(result as? HashedFile)
        XCTAssertEqual(hashed.sha256, "fixed")
    }

    // MARK: - Default hasher smoke test (real file system)

    /// One end-to-end check that `HashStage()` (no hasher injected) actually
    /// produces a SHA-256 from a real file on disk. The byte sequence and its
    /// expected hash are pinned so a regression in the default hasher path or
    /// in `FileHashStore.digestFile` (e.g. accidentally hashing the file path
    /// instead of its contents) is loud.
    func test_defaultHasher_hashesFileContents() async throws {
        let file = tmpDir.appendingPathComponent("hello.txt")
        // ASCII "hello\n" has a known SHA-256.
        let payload = Data("hello\n".utf8)
        try payload.write(to: file)

        let stage = HashStage()
        let result = try await stage.run(file, context: ctx)
        XCTAssertEqual(
            result.sha256,
            "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03",
            "Default hasher must hash file contents, not the URL."
        )
        XCTAssertFalse(result.isImage)
        XCTAssertNil(result.perceptual)
    }
}
