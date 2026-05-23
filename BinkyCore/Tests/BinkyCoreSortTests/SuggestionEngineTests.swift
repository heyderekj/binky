import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

final class SuggestionEngineTests: XCTestCase {

    private let ctx = PipelineContext()

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SuggestionEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Test doubles

    /// Stub adapter that returns a fixed list of suggestions regardless of
    /// input. Used to assert merge behavior independent of any real adapter
    /// logic.
    private struct FixedAdapter: ContentSuggestionAdapter {
        let suggestions: [Suggestion]
        func suggest(
            for ingested: IngestedFile,
            context: PipelineContext
        ) async throws -> [Suggestion] {
            suggestions
        }
    }

    private struct ThrowingAdapter: ContentSuggestionAdapter {
        struct Boom: Error {}
        func suggest(
            for ingested: IngestedFile,
            context: PipelineContext
        ) async throws -> [Suggestion] {
            throw Boom()
        }
    }

    private func makeIngested() -> IngestedFile {
        let url = URL(fileURLWithPath: "/tmp/binky-tests/x.pdf")
        return IngestedFile(
            url: url,
            classification: ClassifiedFile(url: url, category: .pdf),
            originHosts: OriginHosts(url: url, hosts: []),
            hashed: HashedFile(url: url, sha256: "abc")
        )
    }

    private func makeSuggestion(
        source: URL = URL(fileURLWithPath: "/tmp/binky-tests/x.pdf"),
        action: ProposedAction = .move(to: URL(fileURLWithPath: "/tmp/Inbox/")),
        confidence: SuggestionConfidence? = 0.6,
        reasoning: String = "test",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Suggestion {
        Suggestion(
            id: UUID(),
            source: source,
            action: action,
            confidence: confidence,
            reasoning: reasoning,
            createdAt: createdAt
        )
    }

    // MARK: - Adapter wiring

    func test_emptyAdapters_returnsEmpty() async {
        let engine = SuggestionEngine(adapters: [])
        let result = await engine.suggest(for: makeIngested(), context: ctx)
        XCTAssertEqual(result, [])
    }

    func test_singleAdapter_returnsItsSuggestions() async {
        let s = makeSuggestion()
        let engine = SuggestionEngine(adapters: [FixedAdapter(suggestions: [s])])
        let result = await engine.suggest(for: makeIngested(), context: ctx)
        XCTAssertEqual(result, [s])
    }

    func test_multipleAdapters_outputsAreCombined() async {
        let s1 = makeSuggestion(action: .move(to: URL(fileURLWithPath: "/a")), confidence: 0.7)
        let s2 = makeSuggestion(action: .rename(to: "renamed.pdf"), confidence: 0.5)
        let engine = SuggestionEngine(adapters: [
            FixedAdapter(suggestions: [s1]),
            FixedAdapter(suggestions: [s2]),
        ])
        let result = await engine.suggest(for: makeIngested(), context: ctx)
        // Compare by id set — Suggestion is not Hashable, but id is.
        XCTAssertEqual(Set(result.map(\.id)), Set([s1.id, s2.id]))
        XCTAssertEqual(result.count, 2)
    }

    func test_throwingAdapter_doesNotPreventOthers() async {
        let s = makeSuggestion()
        let engine = SuggestionEngine(adapters: [
            ThrowingAdapter(),
            FixedAdapter(suggestions: [s]),
        ])
        let result = await engine.suggest(for: makeIngested(), context: ctx)
        XCTAssertEqual(result, [s],
                       "An adapter throwing must not abort the engine — Daily Calm should still see the surviving adapter's output.")
    }

    func test_allAdaptersThrowing_returnsEmpty() async {
        let engine = SuggestionEngine(adapters: [ThrowingAdapter(), ThrowingAdapter()])
        let result = await engine.suggest(for: makeIngested(), context: ctx)
        XCTAssertEqual(result, [])
    }

    // MARK: - merge: dedupe

    func test_merge_deduplicatesSameSourceAndAction_keepsHigherConfidence() {
        let high = makeSuggestion(confidence: 0.9, reasoning: "AI is sure")
        let low = makeSuggestion(confidence: 0.6, reasoning: "Heuristic guess")
        let merged = SuggestionEngine.merge([low, high])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.confidence, 0.9)
        XCTAssertEqual(merged.first?.reasoning, "AI is sure")
    }

    func test_merge_keepsBothWhenSameSourceButDifferentActions() {
        let move = makeSuggestion(action: .move(to: URL(fileURLWithPath: "/Inbox/")), confidence: 0.6)
        let rename = makeSuggestion(action: .rename(to: "x.pdf"), confidence: 0.5)
        let merged = SuggestionEngine.merge([move, rename])
        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_keepsBothWhenSameActionButDifferentSources() {
        let urlA = URL(fileURLWithPath: "/tmp/binky-tests/a.pdf")
        let urlB = URL(fileURLWithPath: "/tmp/binky-tests/b.pdf")
        let a = makeSuggestion(source: urlA, action: .trash, confidence: 0.7)
        let b = makeSuggestion(source: urlB, action: .trash, confidence: 0.7)
        let merged = SuggestionEngine.merge([a, b])
        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_treatsNilConfidenceAsLowest() {
        // A deterministic-rule suggestion (confidence == nil, not 0) should
        // lose to any explicit-confidence suggestion in dedupe.
        let nilSuggestion = makeSuggestion(confidence: nil, reasoning: "rule")
        let lowConfidence = makeSuggestion(confidence: 0.3, reasoning: "weak heuristic")
        let merged = SuggestionEngine.merge([nilSuggestion, lowConfidence])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.confidence, 0.3)
    }

    func test_merge_normalizesPathsForDedupe() {
        // Dedupe must collapse URLs that point at the same file via different
        // representations (e.g. `/tmp/foo` vs `/tmp/./foo`). Otherwise users
        // would see "duplicate" rows in Daily Calm just because adapters
        // differ in how they construct URLs.
        let urlPlain = URL(fileURLWithPath: "/tmp/binky-tests/x.pdf")
        let urlNoisy = URL(fileURLWithPath: "/tmp/binky-tests/./x.pdf")
        let s1 = makeSuggestion(source: urlPlain, confidence: 0.6)
        let s2 = makeSuggestion(source: urlNoisy, confidence: 0.7)
        let merged = SuggestionEngine.merge([s1, s2])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.confidence, 0.7)
    }

    // MARK: - merge: sort

    func test_merge_sortsByConfidenceDescending() {
        let low = makeSuggestion(action: .move(to: URL(fileURLWithPath: "/A/")), confidence: 0.3)
        let high = makeSuggestion(action: .move(to: URL(fileURLWithPath: "/B/")), confidence: 0.9)
        let mid = makeSuggestion(action: .move(to: URL(fileURLWithPath: "/C/")), confidence: 0.6)
        let merged = SuggestionEngine.merge([low, high, mid])
        XCTAssertEqual(merged.map(\.confidence), [0.9, 0.6, 0.3])
    }

    func test_merge_breaksConfidenceTiesByCreatedAtAscending() {
        // Stable order in Daily Calm matters when confidence ties up; we
        // pick the earlier-created suggestion first so the "first thing the
        // user sees" doesn't shuffle on every render.
        let earlier = makeSuggestion(
            action: .move(to: URL(fileURLWithPath: "/A/")),
            confidence: 0.6,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let later = makeSuggestion(
            action: .move(to: URL(fileURLWithPath: "/B/")),
            confidence: 0.6,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let merged = SuggestionEngine.merge([later, earlier])
        XCTAssertEqual(merged.map(\.createdAt), [
            Date(timeIntervalSince1970: 1_000),
            Date(timeIntervalSince1970: 2_000),
        ])
    }

    // MARK: - URL entry (full pipeline)

    func test_suggestForURL_runsIngestionPipeline_thenAdapters() async throws {
        let file = tmpDir.appendingPathComponent("invoice.pdf")
        try Data().write(to: file)

        // Inject a stub hasher so the pipeline doesn't actually read the file
        // bytes (we don't care about hash content for this test).
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in (sha256: "fixed", perceptual: nil, isImage: false) })
        )
        let adapter = HeuristicSuggestionAdapter(inboxRoot: { category in
            URL(fileURLWithPath: "/Inbox/\(category.rawValue)/")
        })
        let engine = SuggestionEngine(pipeline: pipeline, adapters: [adapter])

        let result = try await engine.suggest(for: file, context: ctx)
        XCTAssertEqual(result.count, 1)
        let s = try XCTUnwrap(result.first)
        if case .move(let dest) = s.action {
            // URL.path strips the trailing slash for directories — check by
            // last path component instead, which is what users see in Daily
            // Calm anyway.
            XCTAssertEqual(dest.lastPathComponent, "pdf")
            XCTAssertTrue(dest.path.contains("/Inbox/"), "got: \(dest.path)")
        } else {
            XCTFail("expected .move action, got \(s.action)")
        }
    }

    func test_suggestForURL_propagatesIngestionErrors() async {
        // Pipeline stage errors are NOT absorbed — caller decides whether to
        // surface as a Daily Calm row or skip. (Adapter errors ARE absorbed
        // — see test_throwingAdapter_doesNotPreventOthers.)
        let pipeline = IngestionPipeline(
            hashStage: HashStage(hasher: { _ in throw URLError(.cannotOpenFile) })
        )
        let engine = SuggestionEngine(
            pipeline: pipeline,
            adapters: [HeuristicSuggestionAdapter(inboxRoot: { _ in URL(fileURLWithPath: "/x") })]
        )

        let file = tmpDir.appendingPathComponent("a.pdf")
        try? Data().write(to: file)

        do {
            _ = try await engine.suggest(for: file, context: ctx)
            XCTFail("expected ingestion error to propagate")
        } catch {
            // expected
        }
    }
}
