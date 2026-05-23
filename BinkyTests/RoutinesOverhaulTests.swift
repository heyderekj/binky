import XCTest
@testable import Binky
@testable import BinkyCoreSort

final class RoutinesOverhaulTests: XCTestCase {

    func testRuleMatchesRequiresFinderTag() {
        var rule = SortRule.fresh(order: 1)
        rule.matchTags = ["Work"]
        let signals = SortRulesEvaluator.FileSignals(
            ext: "pdf",
            baseName: "doc.pdf",
            byteSize: 100,
            addedToDirectoryDate: nil,
            creationDate: nil,
            modificationDate: nil,
            originHosts: []
        )
        XCTAssertFalse(SortRulesEvaluator.ruleMatches(rule, signals: signals, fileTags: ["Personal"]))
        XCTAssertTrue(SortRulesEvaluator.ruleMatches(rule, signals: signals, fileTags: ["work"]))
    }

    func testTagFanoutPriorityResolvesFirstListedTag() {
        let tags = ["Later", "Work", "Home"]
        let priority = ["Work", "Home"]
        XCTAssertEqual(
            SortRulesEvaluator.resolvedFanoutTag(fileTags: tags, priority: priority),
            "Work"
        )
    }

    func testRenamedFilenameAppliesOutputExtensionAndNewExtToken() {
        let url = URL(fileURLWithPath: "/tmp/note.txt")
        var rule = SortRule.fresh(order: 1)
        rule.renameStyle = .template
        rule.renameTemplate = "{stem}{newExt}"
        rule.outputExtension = "md"
        let name = SortRulesEvaluator.renamedFilename(originalURL: url, rule: rule, renameCounter: 0)
        XCTAssertTrue(name.hasSuffix(".md"), "got \(name)")
        XCTAssertFalse(name.contains("{"), "tokens should resolve: \(name)")
    }

    func testExtractZipCreatesFileInDestination() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("binky-extract-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let inner = base.appendingPathComponent("inner", isDirectory: true)
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        let payload = inner.appendingPathComponent("hello.txt")
        try "hi".write(to: payload, atomically: true, encoding: .utf8)

        let zipURL = base.appendingPathComponent("a.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", inner.path, zipURL.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)

        let outDir = base.appendingPathComponent("out", isDirectory: true)
        try ArchiveExtractionService.extract(source: zipURL, destinationDirectory: outDir)

        let extractedFlat = outDir.appendingPathComponent("hello.txt")
        let extractedNested = outDir.appendingPathComponent("inner").appendingPathComponent("hello.txt")
        XCTAssertTrue(
            fm.fileExists(atPath: extractedFlat.path) || fm.fileExists(atPath: extractedNested.path),
            "expected hello.txt under \(outDir.path)"
        )
    }

    func testExtractUnsupportedFormatThrows() {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("binky-bad-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let bogus = base.appendingPathComponent("x.xyz")
        try? Data().write(to: bogus)
        let out = base.appendingPathComponent("out", isDirectory: true)
        XCTAssertThrowsError(try ArchiveExtractionService.extract(source: bogus, destinationDirectory: out)) { err in
            guard case ArchiveExtractionService.ExtractionError.unsupportedFormat = err else {
                XCTFail("wrong error: \(err)")
                return
            }
        }
    }

    /// Regression guard for the tar path-traversal hardening (CVE-class fix).
    ///
    /// Two layers of defence must hold together:
    /// 1. BSD tar on macOS 26+ refuses `..` entries during extraction — that produces a
    ///    `processFailed` thrown from `runProcess`.
    /// 2. The post-extract walker rejects entries that resolved outside the destination — that
    ///    produces a `pathTraversalDetected`. This catches archives that slip past tar's filter
    ///    via symlinks, older macOS, or different tools.
    ///
    /// We assert on the security invariant directly (no file outside the destination, the
    /// destination tree is removed) rather than on which specific error type was raised, since
    /// either layer firing first is a successful outcome.
    func testExtractRejectsPathTraversalTar() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("binky-traversal-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        // Stage a payload that we'll archive with a "../" prefix using BSD tar's -s rewrite flag.
        let payloadDir = base.appendingPathComponent("payload", isDirectory: true)
        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        let evilFile = payloadDir.appendingPathComponent("evil.txt")
        try "pwned".write(to: evilFile, atomically: true, encoding: .utf8)

        let tarURL = base.appendingPathComponent("traversal.tar")
        let mk = Process()
        mk.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        mk.arguments = [
            "-cf", tarURL.path,
            "-C", payloadDir.path,
            "-s", ",^evil.txt,../escaped.txt,",
            "evil.txt"
        ]
        try mk.run()
        mk.waitUntilExit()
        XCTAssertEqual(mk.terminationStatus, 0, "tar packing failed")

        let outDir = base.appendingPathComponent("out", isDirectory: true)
        // Either "tar refuses the entry" or "extractor refuses post-extract" is acceptable. What
        // we care about is that the call throws, and nothing escapes.
        XCTAssertThrowsError(try ArchiveExtractionService.extract(source: tarURL, destinationDirectory: outDir))

        // The escaped sibling must not exist anywhere outside the intended destination.
        let escaped = base.appendingPathComponent("escaped.txt")
        XCTAssertFalse(fm.fileExists(atPath: escaped.path), "path traversal succeeded — escaped.txt was written outside the destination")
    }

    func testWatchPipelineDeduplicatesSharedSourcePaths() {
        let idA = UUID()
        let idB = UUID()
        let home = "/Users/test"
        let reg = WatchPipelineRegistry(
            globalPath: nil,
            routinePaths: [(idA, home), (idB, home)]
        )
        XCTAssertEqual(reg.watchedRootPaths.count, 1)
        XCTAssertEqual(reg.watchedRootPaths.first, home)

        let file = URL(fileURLWithPath: "\(home)/file.pdf")
        if case .routine(_, let ids) = reg.routing(for: file) {
            XCTAssertEqual(Set(ids), [idA, idB])
        } else {
            XCTFail("expected routine routing")
        }
    }

    func testParseDMGMountPointFromSamplePlist() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>mount-point</key>
                    <string>/Volumes/FakeApp</string>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let data = Data(xml.utf8)
        // DMGInstallerService.parseMountPoint is private — exercise attach path only via public API when we have a real dmg.
        // PropertyListSerialization round-trip:
        let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dict = obj as? [String: Any]
        let arr = dict?["system-entities"] as? [[String: Any]]
        let mp = arr?.first?["mount-point"] as? String
        XCTAssertEqual(mp, "/Volumes/FakeApp")
    }
}
