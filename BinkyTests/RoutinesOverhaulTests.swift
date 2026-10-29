import XCTest
@testable import Binky
@testable import BinkyCoreSort

final class RoutinesOverhaulTests: XCTestCase {

    // MARK: - Apple Intelligence helpers

    func testGenericNamesAreRenameable() {
        for name in ["IMG_2041.HEIC", "document (3).pdf", "Scan 2026-10-02 at 9.14.pdf", "download.pdf",
                     "3F2504E0-4F89-11D3-9A0C-0305E82C3301.png", "PXL_20261002_101112.jpg", "a1b2c3d4e5f6a7b8c9d0.pdf"] {
            XCTAssertTrue(FileUnderstanding.looksLikeGenericName(name), name)
        }
        for name in ["Lease agreement.pdf", "stripe-invoice-oct.pdf", "Mom birthday.jpg", "W-2 2025.pdf"] {
            XCTAssertFalse(FileUnderstanding.looksLikeGenericName(name), name)
        }
    }

    func testSuggestedPathsAreSanitized() {
        XCTAssertEqual(FileUnderstanding.sanitizedRelativePath("Finance/Taxes"), "Finance/Taxes")
        XCTAssertEqual(FileUnderstanding.sanitizedRelativePath("/../Finance//Taxes/2025/Q1"), "Finance/Taxes/2025")
        XCTAssertEqual(FileUnderstanding.sanitizedRelativePath("Work: Clients"), "Work Clients")
        XCTAssertNil(FileUnderstanding.sanitizedRelativePath("../.."))
        XCTAssertNil(FileUnderstanding.sanitizedRelativePath("  "))
    }

    func testReviewHabitNeedsRepeatsAndSkipsCoveredOnes() {
        let defaults = UserDefaults.standard
        let saved = (defaults.data(forKey: "review.habitLog"), defaults.stringArray(forKey: "review.habitDismissed"))
        defer {
            defaults.set(saved.0, forKey: "review.habitLog")
            defaults.set(saved.1, forKey: "review.habitDismissed")
        }
        defaults.removeObject(forKey: "review.habitLog")
        defaults.removeObject(forKey: "review.habitDismissed")

        ReviewHabits.record(originHost: "figma.com", ext: "png", destination: "Work/Figma")
        XCTAssertNil(ReviewHabits.strongestHabit(existingRules: []))
        ReviewHabits.record(originHost: "Figma.com", ext: "fig", destination: "Work/Figma")
        let habit = ReviewHabits.strongestHabit(existingRules: [])
        XCTAssertEqual(habit?.originHost, "figma.com")
        XCTAssertEqual(habit?.destination, "Work/Figma")

        var rule = SortRule.fresh(order: 1)
        rule.originDomains = ["figma.com"]
        rule.destinationRelativePath = "Work/Figma"
        XCTAssertNil(ReviewHabits.strongestHabit(existingRules: [rule]))

        ReviewHabits.dismiss(habit!)
        XCTAssertNil(ReviewHabits.strongestHabit(existingRules: []))
    }

    // MARK: - "Looks like…" content kinds

    private func imageSignals() -> SortRulesEvaluator.FileSignals {
        SortRulesEvaluator.FileSignals(
            ext: "png",
            baseName: "img.png",
            byteSize: 100,
            addedToDirectoryDate: nil,
            creationDate: nil,
            modificationDate: nil,
            originHosts: []
        )
    }

    func testVisualContentKindsMatchOnlyTheirTrait() {
        let kinds: [(SortContentMatchKind, SortVisualCategory)] = [
            (.screenshot, .screenshot), (.photo, .photo), (.documentScan, .documentScan), (.ticket, .ticket),
        ]
        for (kind, trait) in kinds {
            var rule = SortRule.fresh(order: 1)
            rule.contentMatch = SortContentMatch(kind: kind)
            let hit = SortRulesEvaluator.ContentRuleMatchInput(hasSignificantOCR: true, isReceiptLike: false, visualTraits: [trait])
            let miss = SortRulesEvaluator.ContentRuleMatchInput(hasSignificantOCR: true, isReceiptLike: true, visualTraits: [])
            XCTAssertTrue(SortRulesEvaluator.ruleMatches(rule, signals: imageSignals(), content: hit), "\(kind)")
            XCTAssertFalse(SortRulesEvaluator.ruleMatches(rule, signals: imageSignals(), content: miss), "\(kind)")
            XCTAssertFalse(SortRulesEvaluator.ruleMatches(rule, signals: imageSignals(), content: nil), "\(kind)")
        }
    }

    func testReceiptRuleAlsoMatchesVisualReceipt() {
        var rule = SortRule.fresh(order: 1)
        rule.contentMatch = SortContentMatch(kind: .receipt)
        let seen = SortRulesEvaluator.ContentRuleMatchInput(hasSignificantOCR: false, isReceiptLike: false, visualTraits: [.receipt, .photo])
        XCTAssertTrue(SortRulesEvaluator.ruleMatches(rule, signals: imageSignals(), content: seen))
    }

    func testVisualTraitsOnlyRequestedForVisualRules() {
        var receipt = SortRule.fresh(order: 1)
        receipt.contentMatch = SortContentMatch(kind: .receipt)
        var ticket = SortRule.fresh(order: 2)
        ticket.contentMatch = SortContentMatch(kind: .ticket)
        XCTAssertFalse(SortRulesEvaluator.anyRuleRequiresVisualCategory([receipt]))
        XCTAssertTrue(SortRulesEvaluator.anyRuleRequiresVisualCategory([receipt, ticket]))
        ticket.isEnabled = false
        XCTAssertFalse(SortRulesEvaluator.anyRuleRequiresVisualCategory([receipt, ticket]))
    }

    func testUnknownContentKindDecodesAsNone() throws {
        let data = Data(#"{"kind":"somethingFromTheFuture"}"#.utf8)
        let decoded = try JSONDecoder().decode(SortContentMatch.self, from: data)
        XCTAssertEqual(decoded.kind, SortContentMatchKind.none)
        let roundTrip = try JSONDecoder().decode(SortContentMatch.self, from: JSONEncoder().encode(SortContentMatch(kind: .ticket)))
        XCTAssertEqual(roundTrip.kind, .ticket)
    }

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
