import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

final class HeuristicSuggestionAdapterTests: XCTestCase {

    private let ctx = PipelineContext()

    /// Maps every category to a deterministic per-category fixture URL so we
    /// can assert which destination the adapter picked.
    private func fixtureInboxRoot(for category: FileSortCategory) -> URL {
        URL(fileURLWithPath: "/tmp/binky-tests/Inbox/\(category.rawValue)/")
    }

    private func makeIngested(
        url: URL = URL(fileURLWithPath: "/tmp/binky-tests/x.pdf"),
        category: FileSortCategory = .pdf,
        isTransient: Bool = false,
        hosts: [String] = []
    ) -> IngestedFile {
        IngestedFile(
            url: url,
            classification: ClassifiedFile(url: url, category: category, isTransient: isTransient),
            originHosts: OriginHosts(url: url, hosts: hosts),
            hashed: HashedFile(url: url, sha256: "test-sha")
        )
    }

    // MARK: - Happy path

    func test_proposesMove_forNormalFile() async throws {
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(
            for: makeIngested(category: .pdf),
            context: ctx
        )
        XCTAssertEqual(suggestions.count, 1)
        let s = try XCTUnwrap(suggestions.first)
        if case .move(let dest) = s.action {
            XCTAssertEqual(dest, fixtureInboxRoot(for: .pdf))
        } else {
            XCTFail("expected .move action, got \(s.action)")
        }
    }

    func test_capsConfidenceAt_0_4_forTypeFallback() async throws {
        // Without a predictor, the adapter uses type-based fallback at 0.4.
        // With a predictor + history, confidence can go up to 0.95.
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(for: makeIngested(category: .images), context: ctx)
        let s = try XCTUnwrap(suggestions.first)
        XCTAssertEqual(s.confidence, 0.4)
    }

    func test_pendingByDefault() async throws {
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(for: makeIngested(), context: ctx)
        let s = try XCTUnwrap(suggestions.first)
        XCTAssertTrue(s.isPending)
    }

    // MARK: - Skip rules

    func test_skipsTransientFiles() async throws {
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(
            for: makeIngested(isTransient: true),
            context: ctx
        )
        XCTAssertEqual(suggestions, [],
                       "Transient files (.crdownload, hidden, ~$Office) must produce no suggestion — engine re-ingests them later.")
    }

    func test_skipsReviewCategory() async throws {
        // Files routed to .review need explicit human decision; auto-suggesting
        // them defeats the trust-first design.
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(
            for: makeIngested(category: .review),
            context: ctx
        )
        XCTAssertEqual(suggestions, [])
    }

    // MARK: - Reasoning text

    func test_reasoning_mentionsCategoryNoun_whenNoOriginHost() async throws {
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(for: makeIngested(category: .pdf), context: ctx)
        let s = try XCTUnwrap(suggestions.first)
        XCTAssertTrue(s.reasoning.contains("PDF"), "got reasoning: \(s.reasoning)")
    }

    func test_reasoning_mentionsOriginHost_whenAvailable() async throws {
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        let suggestions = try await adapter.suggest(
            for: makeIngested(category: .pdf, hosts: ["stripe.com"]),
            context: ctx
        )
        let s = try XCTUnwrap(suggestions.first)
        XCTAssertTrue(s.reasoning.contains("stripe.com"), "got reasoning: \(s.reasoning)")
    }

    func test_reasoning_pickedNounMatchesCategory() async throws {
        // Spot-check the noun mapping. Not exhaustive — exhaustive coverage is
        // overkill for stylistic copy that will eventually be reformatted into
        // a structured reason enum (see decision 5 in docs/v2-progress.md).
        let cases: [(FileSortCategory, String)] = [
            (.images, "image"),
            (.video, "video"),
            (.audio, "audio"),
            (.documents, "document"),
            (.archives, "archive"),
            (.apps, "installer"),
            (.screenshots, "screenshot"),
            (.receipts, "receipt"),
        ]
        let adapter = HeuristicSuggestionAdapter(inboxRoot: fixtureInboxRoot)
        for (cat, noun) in cases {
            let suggestions = try await adapter.suggest(for: makeIngested(category: cat), context: ctx)
            let s = try XCTUnwrap(suggestions.first)
            XCTAssertTrue(s.reasoning.lowercased().contains(noun),
                          "category \(cat) reasoning '\(s.reasoning)' missing '\(noun)'")
        }
    }
}

// MARK: - Foundation Models adapter (placeholder behavior)

final class FoundationModelsSuggestionAdapterTests: XCTestCase {

    private let ctx = PipelineContext()

    func test_returnsEmpty_untilRealImplLands() async throws {
        // Until the macOS 26 + Apple Intelligence integration is wired up the
        // adapter is required to stay quiet — the engine relies on this to
        // pick a deterministic merge branch.
        let adapter = FoundationModelsSuggestionAdapter(
            inboxRoot: { _ in URL(fileURLWithPath: "/tmp") }
        )
        let ingested = IngestedFile(
            url: URL(fileURLWithPath: "/tmp/x.pdf"),
            classification: ClassifiedFile(url: URL(fileURLWithPath: "/tmp/x.pdf"), category: .pdf),
            originHosts: OriginHosts(url: URL(fileURLWithPath: "/tmp/x.pdf"), hosts: []),
            hashed: nil
        )
        let suggestions = try await adapter.suggest(for: ingested, context: ctx)
        XCTAssertEqual(suggestions, [])
    }
}
