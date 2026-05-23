import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SQLite3

private let sqliteTransient: (@convention(c) (UnsafeMutableRawPointer?) -> Void) = unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

/// Persistent store for SHA-256 and perceptual image fingerprints — duplicate detection across sort runs.
///
/// **Concurrency model**
/// - One persistent SQLite connection (opened in `init`, closed on app exit / `clearAllRecords`).
/// - WAL journal mode + NORMAL synchronous so concurrent sort workers don't block each other.
/// - All public methods are serialized via `lock` because SQLite handles are not thread-safe.
///
/// **Perceptual-duplicate index**
/// - dHash64 fingerprints are kept in memory as `(UInt64, String)` pairs.
/// - Lookups iterate the in-memory array, computing 64-bit XOR + popcount per entry. For 100k
///   images that's ≈ 100k × ~10ns = 1ms per lookup, vs. the previous full-table SQL scan that
///   re-prepared statements and re-decoded hex on every call.
/// - The cache is hydrated lazily on the first lookup that needs it, so cold starts only pay the
///   cost when the user actually hits an image that asks for near-duplicate detection.
public final class FileHashStore: @unchecked Sendable {

    public static let shared = FileHashStore()

    private let dbPath: String
    private let lock = NSLock()
    private var db: OpaquePointer?

    /// Cache of (perceptual hash, path) for `is_image = 1` rows. Hydrated lazily.
    /// Keeping it as parallel arrays of UInt64/String would shave another 10–20% but the gain isn't
    /// worth losing the simplicity of a single tuple array.
    private var perceptualIndex: [(hash: UInt64, path: String)] = []
    private var perceptualIndexLoaded = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Binky", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dbPath = base.appendingPathComponent("file_hashes.sqlite3").path
        openPersistent()
        setupSchema()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public struct LookupResult: Sendable {
        public var priorPath: String?
        public var isByteDuplicate: Bool
        public var isNearImageDuplicate: Bool

        public init(priorPath: String?, isByteDuplicate: Bool, isNearImageDuplicate: Bool) {
            self.priorPath = priorPath
            self.isByteDuplicate = isByteDuplicate
            self.isNearImageDuplicate = isNearImageDuplicate
        }
    }

    // MARK: - API

    public func lookup(sha256: String, perceptual: UInt64?, isImage: Bool) -> LookupResult {
        lock.lock()
        defer { lock.unlock() }
        var out = LookupResult(priorPath: nil, isByteDuplicate: false, isNearImageDuplicate: false)
        guard let db else { return out }

        if let rowPath = Self.fetchPath(db: db, sha256: sha256) {
            out.priorPath = rowPath
            out.isByteDuplicate = true
            return out
        }

        if isImage, let p = perceptual {
            ensurePerceptualIndexLoaded()
            if let near = nearestImageDuplicate(target: p) {
                out.priorPath = near
                out.isNearImageDuplicate = true
            }
        }
        return out
    }

    public func recordSortedFile(url: URL, sha256: String, byteSize: Int64, perceptual: UInt64?, isImage: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let phex: String? = perceptual.map { String(format: "%016llx", $0) }
        let ts = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO file_hashes (sha256, path, byte_size, perceptual_hex, is_image, first_seen)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(sha256) DO UPDATE SET
          path = excluded.path,
          byte_size = excluded.byte_size,
          perceptual_hex = excluded.perceptual_hex,
          is_image = excluded.is_image;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sha256, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, url.path, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 3, byteSize)
        if let phex {
            sqlite3_bind_text(stmt, 4, phex, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_int(stmt, 5, isImage ? 1 : 0)
        sqlite3_bind_double(stmt, 6, ts)
        _ = sqlite3_step(stmt)

        // Mirror the new image row into the in-memory perceptual index so subsequent lookups in
        // this session don't have to re-read from SQLite. We only mirror once the index has been
        // hydrated — otherwise hydration on first lookup picks it up anyway.
        if isImage, perceptualIndexLoaded, let p = perceptual {
            perceptualIndex.append((hash: p, path: url.path))
        }
    }

    public func digestFile(at url: URL) throws -> (sha256: String, perceptual: UInt64?, isImage: Bool) {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            throw NSError(domain: "FileHashStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read file"])
        }
        defer { try? fh.close() }
        var hasher = SHA256()
        // Mid-loop cancellation: very large files (multi-GB photos / RAW) used to ignore stop
        // requests until hashing completed. Honoring `Task.checkCancellation()` between chunks
        // means the user can press Stop and have the in-flight hash bail out within ~one 512KB
        // read, instead of waiting for the whole file.
        while true {
            try Task.checkCancellation()
            let chunk = try fh.read(upToCount: 512 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.lowercased()
        let isImg = Self.isRasterImageExtension(ext)
        let p: UInt64? = isImg ? Self.perceptualHash(url: url) : nil
        return (sha, p, isImg)
    }

    // MARK: - DB

    private func openPersistent() {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath, &handle, flags, nil) == SQLITE_OK {
            db = handle
            // WAL: lets readers proceed in parallel with a single writer — perfect for our
            // pattern of one batch-writer + many lookup-readers.
            _ = sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            // NORMAL is durable enough for a cache (we can always re-hash from disk if a power
            // loss truncates the latest batch) and avoids an extra fsync per commit.
            _ = sqlite3_exec(handle, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
            // 30s busy timeout absorbs the rare case where another Binky instance starts up at the
            // same time as the CLI and they briefly contend on the WAL.
            _ = sqlite3_exec(handle, "PRAGMA busy_timeout=30000;", nil, nil, nil)
        }
    }

    private func setupSchema() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        let ddl = """
        CREATE TABLE IF NOT EXISTS file_hashes (
            sha256 TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            byte_size INTEGER NOT NULL,
            perceptual_hex TEXT,
            is_image INTEGER NOT NULL DEFAULT 0,
            first_seen REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_file_hashes_image_perceptual
            ON file_hashes (is_image, perceptual_hex)
            WHERE is_image = 1 AND perceptual_hex IS NOT NULL;
        """
        _ = sqlite3_exec(db, ddl, nil, nil, nil)
    }

    private static func fetchPath(db: OpaquePointer, sha256: String) -> String? {
        let sql = "SELECT path FROM file_hashes WHERE sha256 = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, sha256, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    /// Loads the entire image-perceptual-hash table into memory once per process.
    /// For a power user with 100k images, this is ~2.4 MB of resident memory — well below the
    /// threshold where we'd need a streaming approach.
    private func ensurePerceptualIndexLoaded() {
        guard !perceptualIndexLoaded, let db else { return }
        var stmt: OpaquePointer?
        let sql = "SELECT path, perceptual_hex FROM file_hashes WHERE is_image = 1 AND perceptual_hex IS NOT NULL;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            perceptualIndexLoaded = true
            return
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let hex = String(cString: sqlite3_column_text(stmt, 1))
            guard let val = UInt64(hex, radix: 16) else { continue }
            perceptualIndex.append((hash: val, path: path))
        }
        perceptualIndexLoaded = true
    }

    /// Linear scan with early-exit on first match within Hamming distance ≤ 10 (matches the
    /// historical threshold). Each comparison is XOR + popcount, ~5–10ns.
    private func nearestImageDuplicate(target: UInt64) -> String? {
        for entry in perceptualIndex {
            if (target ^ entry.hash).nonzeroBitCount <= 10 {
                return entry.path
            }
        }
        return nil
    }

    // MARK: - Perceptual hash

    private static func isRasterImageExtension(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(ext)
    }

    private static func perceptualHash(url: URL) -> UInt64? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return dHash64(from: cg)
    }

    private static func dHash64(from cgImage: CGImage) -> UInt64? {
        // Reject pathologically tiny images: they would all hash to similar values and produce
        // false near-duplicate matches against unrelated thumbnails.
        guard cgImage.width >= 16, cgImage.height >= 16 else { return nil }
        let w = 9
        let h = 8
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h)
        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                guard bitIndex < 64 else { break }
                let left = Int(ptr[y * w + x])
                let right = Int(ptr[y * w + x + 1])
                if left > right {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }
        return hash
    }

    /// Rows in the duplicate-memory database (for Settings).
    public func storedRecordCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM file_hashes;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Clears all remembered fingerprints (user explicitly requests this in Settings).
    public func clearAllRecords() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        _ = sqlite3_exec(db, "DELETE FROM file_hashes;", nil, nil, nil)
        perceptualIndex.removeAll(keepingCapacity: false)
        // Force re-hydration so a subsequent lookup in this same session sees the cleared state.
        perceptualIndexLoaded = true
    }
}
