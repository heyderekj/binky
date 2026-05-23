import XCTest
@testable import Binky
@testable import BinkyCoreSort

final class DownloadSortClassificationTests: XCTestCase {

    func testPdfRoutesToPdfDestination() {
        let url = URL(fileURLWithPath: "/tmp/invoice.pdf")
        XCTAssertEqual(FileClassification.categorize(url: url), .pdf)
    }

    func testScreenshotNamedPdfRoutesToScreenshots() {
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2025-04-29 at 12.00.00.pdf")
        XCTAssertEqual(FileClassification.categorize(url: url), .screenshots)
    }

    func testUnknownExtensionRoutesToReview() {
        let url = URL(fileURLWithPath: "/tmp/weird.xyzabc")
        XCTAssertEqual(FileClassification.categorize(url: url), .review)
    }

    func testEmptyExtensionRoutesToReview() {
        let url = URL(fileURLWithPath: "/tmp/README")
        XCTAssertEqual(FileClassification.categorize(url: url), .review)
    }

    func testArchiveRoutesToArchives() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/z.zip")), .archives)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/z.tar.gz")), .archives)
    }

    func testInstallerRoutesToApps() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/Binky.dmg")), .apps)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/a/Thing.pkg")), .apps)
    }

    func testSortAnimationBucketImageLike() {
        XCTAssertEqual(FileSortCategory.images.sortAnimationBucket, .images)
        XCTAssertEqual(FileSortCategory.screenshots.sortAnimationBucket, .images)
    }

    func testSortAnimationBucketVideoLike() {
        XCTAssertEqual(FileSortCategory.video.sortAnimationBucket, .videos)
    }

    func testSortAnimationBucketDefaultsToDocuments() {
        XCTAssertEqual(FileSortCategory.pdf.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.audio.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.documents.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.archives.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.apps.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.misc.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.duplicates.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.receipts.sortAnimationBucket, .documents)
        XCTAssertEqual(FileSortCategory.folders.sortAnimationBucket, .documents)
    }

    func testTransientSuffixRoutesToReview() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/big.iso.crdownload")), .review)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/foo.part")), .review)
        // Newer browsers / download tools — added in 1.5.x harden pass.
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/foo.crswap")), .review)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/movie.opdownload")), .review)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/big.iso.aria2")), .review)
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/torrent.!ut")), .review)
        // Microsoft Office lock files like ~$Document.docx must never be treated as real docs.
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/dl/~$Document.docx")), .review)
    }

    func testDotfileRoutesToReview() {
        XCTAssertEqual(FileClassification.categorize(url: URL(fileURLWithPath: "/tmp/.DS_Store")), .review)
    }

    func testJpegRoutesToImagesWhenNotScreenshotNamed() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpeg")
        XCTAssertEqual(FileClassification.categorize(url: url), .images)
    }

    func testMp4RoutesToVideo() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        XCTAssertEqual(FileClassification.categorize(url: url), .video)
    }
}
