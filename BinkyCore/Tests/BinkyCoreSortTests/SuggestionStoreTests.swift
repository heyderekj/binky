import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

final class SuggestionStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SuggestionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeSuggestion(
        sourcePath: String = "/tmp/binky-tests/x.pdf",
        action: ProposedAction = .move(to: URL(fileURLWithPath: "/tmp/Inbox/"))
    ) -> Suggestion {
        Suggestion(
            id: UUID(),
            source: URL(fileURLWithPath: sourcePath),
            action: action,
            confidence: 0.6,
            reasoning: "test"
        )
    }

    // MARK: - In-memory behavior

    func test_decision_unknownSuggestion_returnsNil() {
        let store = SuggestionStore(directory: tmpDir)
        XCTAssertNil(store.decision(for: makeSuggestion()))
    }

    func test_record_thenLookup_returnsLatestDecision() {
        let store = SuggestionStore(directory: tmpDir)
        let s = makeSuggestion()
        store.record(s, decision: .accepted)
        XCTAssertEqual(store.decision(for: s), .accepted)
    }

    func test_record_isPerSourceAndAction() {
        // Two suggestions with the same source but different actions should
        // not overwrite each other's decisions.
        let store = SuggestionStore(directory: tmpDir)
        let move = makeSuggestion(action: .move(to: URL(fileURLWithPath: "/A/")))
        let trash = makeSuggestion(action: .trash)

        store.record(move, decision: .accepted)
        store.record(trash, decision: .rejected)

        XCTAssertEqual(store.decision(for: move), .accepted)
        XCTAssertEqual(store.decision(for: trash), .rejected)
        XCTAssertEqual(store.recordCount(), 2)
    }

    func test_record_sameKey_overwritesPreviousDecision() {
        let store = SuggestionStore(directory: tmpDir)
        let s = makeSuggestion()
        store.record(s, decision: .accepted)
        store.record(s, decision: .rejected)
        XCTAssertEqual(store.decision(for: s), .rejected)
        // Append-only file may grow, but the in-memory dedupe view reports
        // one logical record for this (source, action).
        XCTAssertEqual(store.recordCount(), 1)
    }

    func test_pathNormalization_treatsEquivalentURLsAsSame() {
        // Same file expressed two ways should collapse to one decision.
        // Otherwise users would see "you already accepted this" miss because
        // an adapter constructed the URL with /./ in it.
        let store = SuggestionStore(directory: tmpDir)
        let plain = makeSuggestion(sourcePath: "/tmp/binky-tests/x.pdf")
        let noisy = makeSuggestion(sourcePath: "/tmp/binky-tests/./x.pdf")
        store.record(plain, decision: .accepted)
        XCTAssertEqual(store.decision(for: noisy), .accepted)
    }

    // MARK: - Persistence

    func test_persistsAcrossInstances() throws {
        let s = makeSuggestion()

        let writer = SuggestionStore(directory: tmpDir)
        writer.record(s, decision: .accepted)

        // A fresh instance reading the same directory must see the decision.
        let reader = SuggestionStore(directory: tmpDir)
        XCTAssertEqual(reader.decision(for: s), .accepted)
    }

    func test_persistsAllUserDecisionCases() {
        let store = SuggestionStore(directory: tmpDir)
        for (i, decision) in UserDecision.allCases.enumerated() {
            let s = makeSuggestion(
                sourcePath: "/tmp/binky-tests/case-\(i).pdf",
                action: .move(to: URL(fileURLWithPath: "/Inbox/case-\(i)/"))
            )
            store.record(s, decision: decision)
        }
        let reader = SuggestionStore(directory: tmpDir)
        XCTAssertEqual(reader.recordCount(), UserDecision.allCases.count)
    }

    func test_recordedTimestampIsPreserved() throws {
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let s = makeSuggestion()

        let writer = SuggestionStore(directory: tmpDir)
        writer.record(s, decision: .accepted, at: pinned)

        let reader = SuggestionStore(directory: tmpDir)
        let r = try XCTUnwrap(reader.record(for: s))
        XCTAssertEqual(r.decidedAt, pinned)
    }

    func test_persistedFile_isNewlineDelimitedJSON() throws {
        // The on-disk format is part of the contract — debug tooling and
        // future migration tools can rely on JSON-lines. Pin it.
        let s = makeSuggestion()
        let store = SuggestionStore(directory: tmpDir)
        store.record(s, decision: .accepted)

        let storeFile = tmpDir.appendingPathComponent("v2-suggestions.jsonl")
        let bytes = try Data(contentsOf: storeFile)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(text.contains("\"sourcePath\""))
        XCTAssertTrue(text.contains("\"decision\""))
    }

    func test_appendOnly_keepsHistory_evenAfterOverwrite() throws {
        // An overwriting record() must add a line, not rewrite existing
        // lines — the file is the audit log.
        let s = makeSuggestion()
        let store = SuggestionStore(directory: tmpDir)
        store.record(s, decision: .accepted)
        store.record(s, decision: .rejected)

        let storeFile = tmpDir.appendingPathComponent("v2-suggestions.jsonl")
        let bytes = try Data(contentsOf: storeFile)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2, "Append-only: 2 records on disk; latest wins in dedupe.")

        // And the in-memory view reflects the latest.
        XCTAssertEqual(store.decision(for: s), .rejected)

        // A fresh instance reading the file picks up the same latest decision.
        let reader = SuggestionStore(directory: tmpDir)
        XCTAssertEqual(reader.decision(for: s), .rejected)
    }

    // MARK: - clearAll

    func test_clearAll_dropsInMemoryAndOnDisk() throws {
        let s = makeSuggestion()
        let store = SuggestionStore(directory: tmpDir)
        store.record(s, decision: .accepted)
        store.clearAll()

        XCTAssertNil(store.decision(for: s))
        XCTAssertEqual(store.recordCount(), 0)

        // A fresh instance shouldn't resurrect anything either.
        let reader = SuggestionStore(directory: tmpDir)
        XCTAssertNil(reader.decision(for: s))

        let storeFile = tmpDir.appendingPathComponent("v2-suggestions.jsonl")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeFile.path))
    }

    func test_clearAll_thenRecord_writesFreshFile() {
        let s = makeSuggestion()
        let store = SuggestionStore(directory: tmpDir)
        store.record(s, decision: .accepted)
        store.clearAll()
        store.record(s, decision: .rejected)

        let reader = SuggestionStore(directory: tmpDir)
        XCTAssertEqual(reader.decision(for: s), .rejected)
        XCTAssertEqual(reader.recordCount(), 1)
    }

    // MARK: - Concurrency smoke

    func test_concurrentRecord_isSafe() async {
        let store = SuggestionStore(directory: tmpDir)
        let total = 50

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<total {
                group.addTask {
                    let s = self.makeSuggestion(
                        sourcePath: "/tmp/binky-tests/concurrent-\(i).pdf",
                        action: .trash
                    )
                    store.record(s, decision: i.isMultiple(of: 2) ? .accepted : .rejected)
                }
            }
        }

        XCTAssertEqual(store.recordCount(), total)
    }

    // MARK: - Action keying

    func test_actionKey_distinguishesAllProposedActionCases() {
        // A regression in actionKey would cause Daily Calm to think a user
        // who accepted "move → A" had also accepted "move → B" / "trash" /
        // etc. Pin every case.
        let cases: [(ProposedAction, String)] = [
            (.move(to: URL(fileURLWithPath: "/A/")), "move:/A"),
            (.rename(to: "x.pdf"), "rename:x.pdf"),
            (.trash, "trash"),
            (.keep, "keep"),
            (.runShortcut(name: "Send to Things"), "shortcut:Send to Things"),
        ]
        let seen = Set(cases.map { SuggestionStore.actionKey(for: $0.0) })
        XCTAssertEqual(seen.count, cases.count, "actionKey collisions: \(seen)")
        for (action, expected) in cases {
            XCTAssertEqual(SuggestionStore.actionKey(for: action), expected)
        }
    }
}
