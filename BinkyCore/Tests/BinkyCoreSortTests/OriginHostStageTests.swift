import XCTest
import Darwin
import BinkyCoreShared
@testable import BinkyCoreSort

/// Verifies `OriginHostStage` is a faithful wrapper around `WhereFromsReader`
/// at the stage boundary. The xattr / plist parsing itself is exhaustively
/// tested by `BinkyTests/WhereFromsTests.swift` against the v1 helpers; we
/// don't duplicate that here.
final class OriginHostStageTests: XCTestCase {

    private let stage = OriginHostStage()
    private let ctx = PipelineContext()

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OriginHostStageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tmpDir.path) {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Stage behavior

    func test_returnsEmptyHosts_whenURLDoesNotExist() async throws {
        // The reader silently returns [] on any read failure. We rely on that
        // here: no separate "file missing" error path bubbles up, so the
        // pipeline downstream never has to special-case it.
        let missing = tmpDir.appendingPathComponent("does-not-exist.pdf")
        let result = try await stage.run(missing, context: ctx)
        XCTAssertEqual(result.url, missing)
        XCTAssertEqual(result.hosts, [])
    }

    func test_returnsEmptyHosts_forFileWithoutXattr() async throws {
        let file = tmpDir.appendingPathComponent("plain.pdf")
        try Data().write(to: file)
        let result = try await stage.run(file, context: ctx)
        XCTAssertEqual(result.hosts, [])
        XCTAssertNil(result.primary)
    }

    func test_readsHostsFromWhereFromsXattr() async throws {
        // Write a synthetic kMDItemWhereFroms xattr (the same shape browsers
        // produce: a binary plist containing an array of URL strings) and
        // confirm the stage reports the host(s) extracted from it.
        let file = tmpDir.appendingPathComponent("invoice.pdf")
        try Data().write(to: file)
        try writeWhereFromsXattr(at: file, urls: [
            "https://stripe.com/invoices/inv_123",
            "https://files.stripe.com/abcdef.pdf",
        ])

        let result = try await stage.run(file, context: ctx)
        XCTAssertEqual(result.hosts, ["stripe.com", "files.stripe.com"])
        XCTAssertEqual(result.primary, "stripe.com")
    }

    func test_normalizesAndDeduplicatesHosts() async throws {
        // The reader strips `www.` and de-dupes, so two URLs that point at the
        // same logical host appear once.
        let file = tmpDir.appendingPathComponent("doc.pdf")
        try Data().write(to: file)
        try writeWhereFromsXattr(at: file, urls: [
            "https://www.example.com/page",
            "https://example.com/asset.pdf",
        ])

        let result = try await stage.run(file, context: ctx)
        XCTAssertEqual(result.hosts, ["example.com"])
    }

    // MARK: - OriginHosts struct

    func test_originHosts_primary_returnsFirstOrNil() {
        let withHosts = OriginHosts(url: URL(fileURLWithPath: "/x"), hosts: ["a.com", "b.com"])
        XCTAssertEqual(withHosts.primary, "a.com")

        let empty = OriginHosts(url: URL(fileURLWithPath: "/x"), hosts: [])
        XCTAssertNil(empty.primary)
    }

    func test_originHosts_isEquatable() {
        let a = OriginHosts(url: URL(fileURLWithPath: "/x"), hosts: ["a.com"])
        let b = OriginHosts(url: URL(fileURLWithPath: "/x"), hosts: ["a.com"])
        XCTAssertEqual(a, b)
    }

    // MARK: - Pipeline integration

    func test_originHostStage_composesWithPipelineRunner() async throws {
        let runner = PipelineRunner(stages: [AnyPipelineStage(OriginHostStage())])
        let url = URL(fileURLWithPath: "/tmp/binky-tests/no-such-file.pdf")
        let result = try await runner.runErased(url)
        let hosts = try XCTUnwrap(result as? OriginHosts)
        XCTAssertEqual(hosts.url, url)
        XCTAssertEqual(hosts.hosts, [])
    }

    // MARK: - Helpers

    /// Writes a synthetic `kMDItemWhereFroms` xattr in the format browsers use
    /// (a binary plist containing an array of URL strings). Throws on any
    /// failure so the test fails loudly rather than silently producing empty
    /// hosts.
    private func writeWhereFromsXattr(at fileURL: URL, urls: [String]) throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: urls,
            format: .binary,
            options: 0
        )
        let result = plist.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return -1 }
            return setxattr(
                fileURL.path,
                "com.apple.metadata:kMDItemWhereFroms",
                base,
                buf.count,
                0,
                0
            )
        }
        if result != 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "setxattr failed: \(String(cString: strerror(errno)))"]
            )
        }
    }
}
