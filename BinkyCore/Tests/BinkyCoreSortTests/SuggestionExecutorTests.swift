import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

final class SuggestionExecutorTests: XCTestCase {

    private let executor = SuggestionExecutor()
    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SuggestionExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        try super.tearDownWithError()
    }

    private func makeSuggestion(
        source: URL,
        action: ProposedAction
    ) -> Suggestion {
        Suggestion(source: source, action: action, reasoning: "test")
    }

    // MARK: - Move

    func test_move_createsDestinationAndMovesFile() throws {
        let file = tmpDir.appendingPathComponent("report.pdf")
        try Data("pdf".utf8).write(to: file)
        let dest = tmpDir.appendingPathComponent("Inbox/Documents", isDirectory: true)

        let s = makeSuggestion(source: file, action: .move(to: dest))
        let result = executor.execute(s)

        XCTAssertTrue(result.succeeded)
        if case .success(let path) = result.outcome {
            XCTAssertNotNil(path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path!))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "source should be gone")
        } else {
            XCTFail("expected success, got \(result.outcome)")
        }
    }

    func test_move_uniquifiesOnCollision() throws {
        let file1 = tmpDir.appendingPathComponent("a.pdf")
        let file2 = tmpDir.appendingPathComponent("b.pdf")
        try Data("1".utf8).write(to: file1)
        try Data("2".utf8).write(to: file2)
        let dest = tmpDir.appendingPathComponent("Out", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Move file1 → Out/a.pdf
        let r1 = executor.execute(makeSuggestion(source: file1, action: .move(to: dest)))
        XCTAssertTrue(r1.succeeded)

        // Create another a.pdf and move it — should become "a 2.pdf"
        let file3 = tmpDir.appendingPathComponent("a.pdf")
        try Data("3".utf8).write(to: file3)
        let r2 = executor.execute(makeSuggestion(source: file3, action: .move(to: dest)))
        XCTAssertTrue(r2.succeeded)
        if case .success(let path) = r2.outcome {
            XCTAssertTrue(path!.contains("a 2.pdf"), "expected uniquified name, got: \(path!)")
        }
    }

    func test_move_failsGracefully_whenSourceMissing() {
        let missing = tmpDir.appendingPathComponent("ghost.pdf")
        let dest = tmpDir.appendingPathComponent("Out", isDirectory: true)
        let result = executor.execute(makeSuggestion(source: missing, action: .move(to: dest)))
        XCTAssertFalse(result.succeeded)
        if case .failure(let reason) = result.outcome {
            XCTAssertTrue(reason.contains("no longer exists"))
        }
    }

    // MARK: - Rename

    func test_rename_renamesInPlace() throws {
        let file = tmpDir.appendingPathComponent("IMG_1234.jpg")
        try Data("img".utf8).write(to: file)

        let result = executor.execute(makeSuggestion(source: file, action: .rename(to: "vacation-beach.jpg")))
        XCTAssertTrue(result.succeeded)
        if case .success(let path) = result.outcome {
            XCTAssertTrue(path!.hasSuffix("vacation-beach.jpg"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: path!))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func test_rename_uniquifiesOnCollision() throws {
        let file = tmpDir.appendingPathComponent("a.pdf")
        try Data("a".utf8).write(to: file)
        // Pre-create the target name so it collides
        let existing = tmpDir.appendingPathComponent("renamed.pdf")
        try Data("existing".utf8).write(to: existing)

        let result = executor.execute(makeSuggestion(source: file, action: .rename(to: "renamed.pdf")))
        XCTAssertTrue(result.succeeded)
        if case .success(let path) = result.outcome {
            XCTAssertTrue(path!.contains("renamed 2.pdf"), "got: \(path!)")
        }
    }

    // MARK: - Trash

    func test_trash_movesToTrash() throws {
        let file = tmpDir.appendingPathComponent("junk.txt")
        try Data("junk".utf8).write(to: file)

        let result = executor.execute(makeSuggestion(source: file, action: .trash))
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        // trashItem moves to ~/.Trash; we can't easily assert the exact path
        // but success + source gone is sufficient.
    }

    // MARK: - Keep

    func test_keep_isNoOp() throws {
        let file = tmpDir.appendingPathComponent("keep-me.pdf")
        try Data("keep".utf8).write(to: file)

        let result = executor.execute(makeSuggestion(source: file, action: .keep))
        XCTAssertTrue(result.succeeded)
        if case .kept = result.outcome {} else { XCTFail("expected .kept") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "file must remain")
    }

    // MARK: - Source missing

    func test_allActions_failGracefully_whenSourceMissing() {
        let missing = tmpDir.appendingPathComponent("nope.pdf")
        let actions: [ProposedAction] = [
            .move(to: tmpDir),
            .rename(to: "x.pdf"),
            .trash,
            // .keep doesn't check existence (it's a no-op)
        ]
        for action in actions {
            let result = executor.execute(makeSuggestion(source: missing, action: action))
            XCTAssertFalse(result.succeeded, "action \(action) should fail for missing source")
        }
    }
}
