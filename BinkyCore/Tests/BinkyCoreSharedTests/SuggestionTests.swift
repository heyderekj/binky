import XCTest
@testable import BinkyCoreShared

final class SuggestionTests: XCTestCase {

    // MARK: - Helpers

    private static let fixtureURL = URL(fileURLWithPath: "/tmp/binky-tests/some-file.pdf")
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    private func makeSuggestion(
        action: ProposedAction = .move(to: URL(fileURLWithPath: "/tmp/binky-tests/Inbox/")),
        decision: UserDecision? = nil,
        confidence: SuggestionConfidence? = 0.85
    ) -> Suggestion {
        Suggestion(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            source: Self.fixtureURL,
            action: action,
            confidence: confidence,
            reasoning: "Looks like an invoice (vendor: Acme, $1,200)",
            createdAt: Self.fixedDate,
            userDecision: decision
        )
    }

    // MARK: - Predicates

    func test_isPending_whenDecisionIsNil() {
        let s = makeSuggestion(decision: nil)
        XCTAssertTrue(s.isPending)
        XCTAssertFalse(s.isAccepted)
        XCTAssertFalse(s.isRejected)
        XCTAssertFalse(s.isSnoozed)
    }

    func test_isPending_whenDecisionIsExplicitlyPending() {
        // .pending and nil should both report as pending — the engine treats them
        // identically for "show in Daily Calm" purposes.
        let s = makeSuggestion(decision: .pending)
        XCTAssertTrue(s.isPending)
    }

    func test_isAccepted() {
        let s = makeSuggestion(decision: .accepted)
        XCTAssertFalse(s.isPending)
        XCTAssertTrue(s.isAccepted)
    }

    func test_isRejected() {
        let s = makeSuggestion(decision: .rejected)
        XCTAssertTrue(s.isRejected)
        XCTAssertFalse(s.isAccepted)
    }

    func test_isSnoozed() {
        let s = makeSuggestion(decision: .snoozed)
        XCTAssertTrue(s.isSnoozed)
        XCTAssertFalse(s.isPending)
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip_movesAction_preservesAllFields() throws {
        let original = makeSuggestion(
            action: .move(to: URL(fileURLWithPath: "/tmp/binky-tests/Out/")),
            decision: .pending
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func test_codable_roundTrip_renameAction() throws {
        let original = makeSuggestion(action: .rename(to: "Acme-Invoice-2024-03.pdf"))
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.action, .rename(to: "Acme-Invoice-2024-03.pdf"))
        XCTAssertEqual(decoded, original)
    }

    func test_codable_roundTrip_trashAction() throws {
        let original = makeSuggestion(action: .trash, decision: .accepted)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.action, .trash)
        XCTAssertEqual(decoded.userDecision, .accepted)
    }

    func test_codable_roundTrip_keepAction() throws {
        let original = makeSuggestion(action: .keep, confidence: nil)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.action, .keep)
        XCTAssertNil(decoded.confidence)
    }

    func test_codable_roundTrip_runShortcutAction() throws {
        let original = makeSuggestion(action: .runShortcut(name: "Send to Things"))
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.action, .runShortcut(name: "Send to Things"))
    }

    func test_codable_persistsURLAsPath_notFileURLBlob() throws {
        // We deliberately serialize URLs as plain POSIX paths (under the
        // `sourcePath` key) so the JSON stays human-readable. Foundation's
        // JSONEncoder escapes forward slashes as `\/` by default, so we don't
        // assert on the raw JSON substring — instead we check that the
        // `sourcePath` key is present and that decoding the value back yields
        // the original path.
        let original = makeSuggestion()
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"sourcePath\""), "expected sourcePath key, got: \(json)")
        let decoded = try JSONDecoder().decode(Suggestion.self, from: data)
        XCTAssertEqual(decoded.source.path, Self.fixtureURL.path)
    }

    func test_codable_userDecisionOptionalIsOmittedWhenNil() throws {
        // `userDecision` is declared `decodeIfPresent` / `encodeIfPresent`, so the
        // JSON for a pending suggestion shouldn't carry a key for it. This keeps
        // historical records compact and migrations forgiving.
        let original = makeSuggestion(decision: nil)
        let data = try JSONEncoder().encode(original)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("userDecision"))
    }

    func test_codable_allUserDecisionCasesRoundTrip() throws {
        for decision in UserDecision.allCases {
            let original = makeSuggestion(decision: decision)
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded.userDecision, decision, "round-trip lost \(decision)")
        }
    }

    // MARK: - Defaults

    func test_initWithDefaults_generatesUUIDAndCurrentDate() {
        let before = Date()
        let s = Suggestion(
            source: Self.fixtureURL,
            action: .keep,
            reasoning: "User keeps these every time"
        )
        let after = Date()
        XCTAssertGreaterThanOrEqual(s.createdAt, before)
        XCTAssertLessThanOrEqual(s.createdAt, after)
        XCTAssertNil(s.confidence)
        XCTAssertNil(s.userDecision)
        XCTAssertTrue(s.isPending)
    }

    // MARK: - Test helpers

    private func roundTrip(_ s: Suggestion) throws -> Suggestion {
        let data = try JSONEncoder().encode(s)
        return try JSONDecoder().decode(Suggestion.self, from: data)
    }
}
