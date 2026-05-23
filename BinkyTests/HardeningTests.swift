import XCTest
@testable import Binky
@testable import BinkyCoreSort

final class HardeningTests: XCTestCase {

    // MARK: - DMG installer atomic install

    func testAtomicInstallLandsWhenDestinationMissing() throws {
        let fm = FileManager.default
        let base = makeTmp("atomic-fresh")
        defer { try? fm.removeItem(at: base) }

        let source = base.appendingPathComponent("Binky.app", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try "v2".write(to: source.appendingPathComponent("v.txt"), atomically: true, encoding: .utf8)

        let dest = base.appendingPathComponent("Apps/Binky.app", isDirectory: true)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        try DMGInstallerService.atomicallyInstall(appURL: source, finalDestination: dest)

        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("v.txt"), encoding: .utf8), "v2")
    }

    func testAtomicInstallSwapsExistingDestination() throws {
        let fm = FileManager.default
        let base = makeTmp("atomic-upgrade")
        defer { try? fm.removeItem(at: base) }

        let dest = base.appendingPathComponent("Apps/Binky.app", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try "v1".write(to: dest.appendingPathComponent("v.txt"), atomically: true, encoding: .utf8)

        let source = base.appendingPathComponent("new/Binky.app", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try "v2".write(to: source.appendingPathComponent("v.txt"), atomically: true, encoding: .utf8)

        try DMGInstallerService.atomicallyInstall(appURL: source, finalDestination: dest)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("v.txt"), encoding: .utf8), "v2")
    }

    func testAtomicInstallPreservesExistingWhenSourceMissing() throws {
        let fm = FileManager.default
        let base = makeTmp("atomic-fail")
        defer { try? fm.removeItem(at: base) }

        let dest = base.appendingPathComponent("Apps/Binky.app", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try "keep".write(to: dest.appendingPathComponent("v.txt"), atomically: true, encoding: .utf8)

        let bogus = base.appendingPathComponent("missing/Binky.app", isDirectory: true)
        XCTAssertThrowsError(try DMGInstallerService.atomicallyInstall(appURL: bogus, finalDestination: dest))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("v.txt"), encoding: .utf8), "keep")
    }

    // MARK: - Zip integrity

    func testVerifyZipIntegrityAcceptsValid() throws {
        let fm = FileManager.default
        let base = makeTmp("zip-valid")
        defer { try? fm.removeItem(at: base) }

        let payload = base.appendingPathComponent("a.txt")
        try "hi".write(to: payload, atomically: true, encoding: .utf8)
        let zipURL = base.appendingPathComponent("a.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", payload.path, zipURL.path]
        try p.run(); p.waitUntilExit()

        XCTAssertNoThrow(try SortZipViaDitto.verifyZipIntegrity(at: zipURL))
        XCTAssertTrue(fm.fileExists(atPath: zipURL.path))
    }

    func testVerifyZipIntegrityRejectsEmpty() throws {
        let fm = FileManager.default
        let base = makeTmp("zip-empty")
        defer { try? fm.removeItem(at: base) }

        let zipURL = base.appendingPathComponent("e.zip")
        try Data().write(to: zipURL)

        XCTAssertThrowsError(try SortZipViaDitto.verifyZipIntegrity(at: zipURL))
        XCTAssertFalse(fm.fileExists(atPath: zipURL.path))
    }

    func testVerifyZipIntegrityRejectsCorrupt() throws {
        let fm = FileManager.default
        let base = makeTmp("zip-corrupt")
        defer { try? fm.removeItem(at: base) }

        let zipURL = base.appendingPathComponent("bad.zip")
        try Data(repeating: 0xAB, count: 256).write(to: zipURL)

        XCTAssertThrowsError(try SortZipViaDitto.verifyZipIntegrity(at: zipURL))
        XCTAssertFalse(fm.fileExists(atPath: zipURL.path))
    }

    // MARK: - Cross-process lock

    func testCrossProcessLockAcquireAndRelease() {
        let lock = SortCrossProcessLock()
        XCTAssertTrue(lock.tryLock())
        lock.unlock()
    }

    func testCrossProcessLockSecondAcquirerFails() {
        let first = SortCrossProcessLock()
        XCTAssertTrue(first.tryLock())

        let second = SortCrossProcessLock()
        XCTAssertFalse(second.tryLock())

        first.unlock()
        let third = SortCrossProcessLock()
        XCTAssertTrue(third.tryLock())
        third.unlock()
    }

    // MARK: - looksTransientIncomplete

    func testTransientDetectsDownloadSuffixes() {
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.crdownload")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.crswap")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.opdownload")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.aria2")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.!ut")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.part")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.partial")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.download")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.tmp")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x.temp")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/x~")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/~$Doc.docx")))
        XCTAssertTrue(looksTransientIncomplete(URL(fileURLWithPath: "/dl/.hidden")))
    }

    func testTransientAllowsRealFiles() {
        XCTAssertFalse(looksTransientIncomplete(URL(fileURLWithPath: "/dl/photo.jpg")))
        XCTAssertFalse(looksTransientIncomplete(URL(fileURLWithPath: "/dl/doc.pdf")))
        XCTAssertFalse(looksTransientIncomplete(URL(fileURLWithPath: "/dl/.DS_Store")))
    }

    // MARK: - Helpers

    private func makeTmp(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("binky-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
