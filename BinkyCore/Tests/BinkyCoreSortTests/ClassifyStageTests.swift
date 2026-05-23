import XCTest
import BinkyCoreShared
@testable import BinkyCoreSort

/// Verifies `ClassifyStage` is a faithful, side-effect-free wrapper around the
/// existing v1 `FileClassification.categorize` heuristic. We test the heuristic's
/// behavior here (rather than re-testing it elsewhere) because this stage is the
/// new public surface for classification — every other v2 caller will go through
/// it, so any regression should fail at this boundary first.
final class ClassifyStageTests: XCTestCase {

    private let stage = ClassifyStage()
    private let ctx = PipelineContext()

    // MARK: - Helpers

    private func classify(_ path: String) async throws -> ClassifiedFile {
        try await stage.run(URL(fileURLWithPath: path), context: ctx)
    }

    // MARK: - Documents

    func test_classifies_pdf_asPDF() async throws {
        let result = try await classify("/tmp/binky-tests/report.pdf")
        XCTAssertEqual(result.category, .pdf)
        XCTAssertFalse(result.isTransient)
    }

    func test_classifies_docx_asDocuments() async throws {
        let result = try await classify("/tmp/binky-tests/contract.docx")
        XCTAssertEqual(result.category, .documents)
    }

    func test_classifies_md_asDocuments() async throws {
        let result = try await classify("/tmp/binky-tests/notes.md")
        XCTAssertEqual(result.category, .documents)
    }

    // MARK: - Images

    func test_classifies_jpg_asImages() async throws {
        let result = try await classify("/tmp/binky-tests/photo.jpg")
        XCTAssertEqual(result.category, .images)
    }

    func test_classifies_heic_asImages() async throws {
        let result = try await classify("/tmp/binky-tests/photo.heic")
        XCTAssertEqual(result.category, .images)
    }

    func test_classifies_png_withScreenshotName_asScreenshots() async throws {
        // Screenshot-naming heuristic: any image whose basename includes
        // "screen shot" / "screenshot" routes to .screenshots. PDF gets the same
        // override, so we cover both below.
        let result = try await classify("/tmp/binky-tests/Screen Shot 2024-03-01 at 10.00.00.png")
        XCTAssertEqual(result.category, .screenshots)
    }

    func test_classifies_pdf_withScreenshotName_asScreenshots() async throws {
        let result = try await classify("/tmp/binky-tests/Screenshot of receipt.pdf")
        XCTAssertEqual(result.category, .screenshots)
    }

    // MARK: - Media

    func test_classifies_mp4_asVideo() async throws {
        let result = try await classify("/tmp/binky-tests/recording.mp4")
        XCTAssertEqual(result.category, .video)
    }

    func test_classifies_mp3_asAudio() async throws {
        let result = try await classify("/tmp/binky-tests/song.mp3")
        XCTAssertEqual(result.category, .audio)
    }

    func test_classifies_flac_asAudio() async throws {
        let result = try await classify("/tmp/binky-tests/album.flac")
        XCTAssertEqual(result.category, .audio)
    }

    // MARK: - Archives & installers

    func test_classifies_zip_asArchives() async throws {
        let result = try await classify("/tmp/binky-tests/source.zip")
        XCTAssertEqual(result.category, .archives)
    }

    func test_classifies_tarGz_asArchives() async throws {
        let result = try await classify("/tmp/binky-tests/source.tar.gz")
        XCTAssertEqual(result.category, .archives)
    }

    func test_classifies_dmg_asApps() async throws {
        let result = try await classify("/tmp/binky-tests/Installer.dmg")
        XCTAssertEqual(result.category, .apps)
    }

    func test_classifies_pkg_asApps() async throws {
        let result = try await classify("/tmp/binky-tests/Installer.pkg")
        XCTAssertEqual(result.category, .apps)
    }

    // MARK: - Review (trust-first)

    func test_classifies_unknownExtension_asReview() async throws {
        // Trust-first: anything we can't confidently route lands in Review.
        let result = try await classify("/tmp/binky-tests/mystery.xyz123")
        XCTAssertEqual(result.category, .review)
    }

    func test_classifies_noExtension_asReview() async throws {
        let result = try await classify("/tmp/binky-tests/README")
        XCTAssertEqual(result.category, .review)
    }

    // MARK: - Transient detection

    func test_marksAsTransient_crdownload() async throws {
        let result = try await classify("/tmp/binky-tests/Big Download.zip.crdownload")
        XCTAssertTrue(result.isTransient,
                      "Chrome's .crdownload partial download must be flagged transient.")
    }

    func test_marksAsTransient_part() async throws {
        let result = try await classify("/tmp/binky-tests/firefox-download.part")
        XCTAssertTrue(result.isTransient)
    }

    func test_marksAsTransient_dotPrefix() async throws {
        // Hidden files should be flagged transient even when the extension would
        // otherwise classify (e.g. `.report.pdf`).
        let result = try await classify("/tmp/binky-tests/.report.pdf")
        XCTAssertTrue(result.isTransient)
    }

    func test_marksAsTransient_officeLockFile() async throws {
        // Microsoft Office writes `~$Document.docx` while a doc is open.
        let result = try await classify("/tmp/binky-tests/~$Brief.docx")
        XCTAssertTrue(result.isTransient)
    }

    func test_doesNotMarkAsTransient_dsStore() async throws {
        // .DS_Store is the one dotfile we explicitly opt out of the transient
        // rule for — it's not in-flight, it's just Finder metadata.
        let result = try await classify("/tmp/binky-tests/.DS_Store")
        XCTAssertFalse(result.isTransient)
    }

    func test_doesNotMarkAsTransient_normalFile() async throws {
        let result = try await classify("/tmp/binky-tests/normal.pdf")
        XCTAssertFalse(result.isTransient)
    }

    // MARK: - ClassifiedFile struct

    func test_classifiedFile_isEquatable() {
        let a = ClassifiedFile(url: URL(fileURLWithPath: "/a.pdf"), category: .pdf)
        let b = ClassifiedFile(url: URL(fileURLWithPath: "/a.pdf"), category: .pdf)
        XCTAssertEqual(a, b)
    }

    func test_classifiedFile_defaultsTransientToFalse() {
        let f = ClassifiedFile(url: URL(fileURLWithPath: "/x.pdf"), category: .pdf)
        XCTAssertFalse(f.isTransient)
    }

    // MARK: - Pipeline integration

    func test_classifyStage_composesWithPipelineRunner() async throws {
        let runner = PipelineRunner(stages: [AnyPipelineStage(ClassifyStage())])
        let result = try await runner.runErased(URL(fileURLWithPath: "/tmp/binky-tests/photo.jpg"))
        let classified = try XCTUnwrap(result as? ClassifiedFile)
        XCTAssertEqual(classified.category, .images)
    }
}
