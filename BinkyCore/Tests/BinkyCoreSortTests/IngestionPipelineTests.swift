import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

/// Tests cover the *coordination* logic in `IngestionPipeline`. The individual
/// stages are exhaustively tested in their own files (ClassifyStageTests,
/// OriginHostStageTests, HashStageTests); here we focus on:
///
/// - All three stages run and their outputs aggregate correctly.
/// - Hash is skipped when the file looks transient.
/// - Errors propagate.
/// - The pipeline composes cleanly with a real fixture file end-to-end.
final class IngestionPipelineTests: XCTestCase {

    private let ctx = PipelineContext()

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("IngestionPipelineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Aggregation

    func test_aggregatesAllThreeStageOutputs_forNormalFile() async throws {
        let file = tmpDir.appendingPathComponent("report.pdf")
        try Data("some pdf bytes".utf8).write(to: file)

        // Use a stub hasher so the test stays deterministic and fast.
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in
                (sha256: "deterministic-sha", perceptual: nil, isImage: false)
            })
        )

        let ingested = try await pipeline.ingest(file, context: ctx)

        XCTAssertEqual(ingested.url, file)
        XCTAssertEqual(ingested.classification.category, .pdf)
        XCTAssertFalse(ingested.classification.isTransient)
        XCTAssertEqual(ingested.originHosts.hosts, [], "no xattr was set, so hosts must be empty")
        XCTAssertEqual(ingested.hashed?.sha256, "deterministic-sha")
        XCTAssertFalse(ingested.hashSkippedBecauseTransient)
    }

    func test_skipsHashing_whenFileLooksTransient_crdownload() async throws {
        let file = tmpDir.appendingPathComponent("Big Download.zip.crdownload")
        try Data().write(to: file)

        // Hasher is wired to fail loudly — if we hash a transient file, the
        // test must blow up (not silently succeed).
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in
                XCTFail("hasher must not run for transient files")
                return (sha256: "", perceptual: nil, isImage: false)
            })
        )

        let ingested = try await pipeline.ingest(file, context: ctx)
        XCTAssertTrue(ingested.classification.isTransient)
        XCTAssertNil(ingested.hashed)
        XCTAssertTrue(ingested.hashSkippedBecauseTransient)
    }

    func test_skipsHashing_whenFileIsHidden() async throws {
        let file = tmpDir.appendingPathComponent(".secret.pdf")
        try Data().write(to: file)

        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in
                XCTFail("hasher must not run for hidden files")
                return (sha256: "", perceptual: nil, isImage: false)
            })
        )

        let ingested = try await pipeline.ingest(file, context: ctx)
        XCTAssertTrue(ingested.classification.isTransient)
        XCTAssertNil(ingested.hashed)
    }

    // MARK: - Errors

    func test_propagatesHashError() async {
        let file = tmpDir.appendingPathComponent("broken.pdf")
        try? Data().write(to: file)

        struct ReadFailed: Error {}
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in throw ReadFailed() })
        )

        do {
            _ = try await pipeline.ingest(file, context: ctx)
            XCTFail("expected ReadFailed")
        } catch is ReadFailed {
            // expected
        } catch {
            XCTFail("expected ReadFailed, got \(error)")
        }
    }

    // MARK: - Cancellation

    func test_throwsCancellation_whenTaskCancelledBeforeIngest() async {
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in
                XCTFail("hasher must not run when cancelled before start")
                return (sha256: "", perceptual: nil, isImage: false)
            })
        )

        let task = Task<IngestedFile, Error> {
            try await pipeline.ingest(URL(fileURLWithPath: "/x.pdf"), context: ctx)
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

    // MARK: - End-to-end with default stages

    /// Pins the v2 dry-run pipeline behavior on a realistic-shaped input: a
    /// real file, default stages (no stubs except `hashStage`), and an actual
    /// `kMDItemWhereFroms` xattr written to disk. Acts as a smoke test for the
    /// whole `IngestionPipeline` story — if any of the three stages stops
    /// cooperating with the others, this fails first.
    func test_endToEnd_realFile_withRealXattr() async throws {
        let file = tmpDir.appendingPathComponent("invoice.pdf")
        try Data("dummy pdf content".utf8).write(to: file)

        // Set kMDItemWhereFroms via setxattr (same approach as OriginHostStageTests).
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["https://stripe.com/invoices/inv_123"],
            format: .binary,
            options: 0
        )
        let xattrResult = plist.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return setxattr(file.path, "com.apple.metadata:kMDItemWhereFroms", base, buf.count, 0, 0)
        }
        XCTAssertEqual(xattrResult, 0, "setxattr must succeed for this end-to-end check")

        // Stub hasher so the test stays deterministic. Real hashing is covered
        // by HashStageTests.test_defaultHasher_hashesFileContents.
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in (sha256: "e2e-sha", perceptual: nil, isImage: false) })
        )

        let ingested = try await pipeline.ingest(file, context: ctx)

        XCTAssertEqual(ingested.classification.category, .pdf)
        XCTAssertFalse(ingested.classification.isTransient)
        XCTAssertEqual(ingested.originHosts.primary, "stripe.com")
        XCTAssertEqual(ingested.hashed?.sha256, "e2e-sha")
    }

    // MARK: - IngestedFile struct

    func test_hashSkippedBecauseTransient_isFalse_whenHashIsPresent() {
        let f = IngestedFile(
            url: URL(fileURLWithPath: "/x"),
            classification: ClassifiedFile(url: URL(fileURLWithPath: "/x"), category: .pdf, isTransient: false),
            originHosts: OriginHosts(url: URL(fileURLWithPath: "/x"), hosts: []),
            hashed: HashedFile(url: URL(fileURLWithPath: "/x"), sha256: "abc")
        )
        XCTAssertFalse(f.hashSkippedBecauseTransient)
    }

    func test_hashSkippedBecauseTransient_isFalse_whenHashAbsentButNotTransient() {
        // Distinguishes "we skipped because transient" from "the hash was
        // never produced for some other reason" (which a future SuggestionEngine
        // path may want to handle differently).
        let f = IngestedFile(
            url: URL(fileURLWithPath: "/x"),
            classification: ClassifiedFile(url: URL(fileURLWithPath: "/x"), category: .pdf, isTransient: false),
            originHosts: OriginHosts(url: URL(fileURLWithPath: "/x"), hosts: []),
            hashed: nil
        )
        XCTAssertFalse(f.hashSkippedBecauseTransient)
    }
}
