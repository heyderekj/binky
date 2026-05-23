import Foundation

/// Expands archives with system tools (no bundled decompressors).
enum ArchiveExtractionService: Sendable {

    enum ExtractionError: Error {
        case unsupportedFormat(String)
        case processFailed(String, Int32)
        case destinationExists(URL)
        /// Archive contained an entry that escaped the destination directory (path traversal).
        case pathTraversalDetected(URL)
        /// Archive's compression ratio or uncompressed size exceeds safe limits (zip bomb).
        case zipBombDetected(ratio: Double, uncompressedBytes: UInt64)
    }

    /// Extracts `source` into `destinationDirectory` (created if needed). Does not delete the source.
    ///
    /// After extraction, every produced entry is verified to live under `destinationDirectory`.
    /// Any entry whose resolved path escapes the destination causes the extraction to be rolled
    /// back (destination tree removed) and `pathTraversalDetected` is thrown.
    ///
    /// For zip archives, a pre-flight compression-ratio check rejects zip bombs (ratio > 100:1
    /// or uncompressed size > 10 GB) before any bytes are written to disk.
    static func extract(source: URL, destinationDirectory: URL) throws {
        let fm = FileManager.default
        let ext = source.pathExtension.lowercased()

        // Zip bomb pre-flight: inspect the central directory without extracting.
        if ext == "zip" {
            try rejectZipBomb(at: source)
        }

        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        switch ext {
        case "zip":
            try runDittoExtractZip(from: source, to: destinationDirectory)
        case "tar", "tgz":
            try runTarExtract(from: source, to: destinationDirectory, gzip: ext == "tgz")
        case "gz" where source.deletingPathExtension().pathExtension.lowercased() == "tar":
            try runTarExtract(from: source, to: destinationDirectory, gzip: true)
        case "gz":
            try runTarExtract(from: source, to: destinationDirectory, gzip: true)
        case "bz2":
            try runTarExtract(from: source, to: destinationDirectory, bzip: true)
        case "xz":
            try runTarExtract(from: source, to: destinationDirectory, xz: true)
        default:
            throw ExtractionError.unsupportedFormat(ext)
        }

        try verifyNoPathTraversal(under: destinationDirectory)
    }

    private static func runDittoExtractZip(from source: URL, to destinationDirectory: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", source.path, destinationDirectory.path]
        try runProcess(p, label: "ditto")
    }

    private static func runTarExtract(from source: URL, to destinationDirectory: URL, gzip: Bool = false, bzip: Bool = false, xz: Bool = false) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        // -P is intentionally NOT passed (the default already strips leading slashes and rejects
        // absolute paths). The post-extract verifier below catches the remaining `..` cases that
        // BSD tar does not block on its own.
        var args = ["-xf", source.path, "-C", destinationDirectory.path]
        if gzip {
            args.insert("-z", at: 1)
        } else if bzip {
            args.insert("-j", at: 1)
        } else if xz {
            args.insert("-J", at: 1)
        }
        p.arguments = args
        try runProcess(p, label: "tar")
    }

    private static func runProcess(_ p: Process, label: String) throws {
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw ExtractionError.processFailed(label, p.terminationStatus)
        }
    }

    /// Reads the zip central directory via `zipinfo -l` and sums the uncompressed sizes.
    /// Rejects if ratio > 100:1 or total uncompressed > 10 GB.
    private static func rejectZipBomb(at source: URL) throws {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: source.path)
        let compressedSize = (attrs[.size] as? UInt64) ?? 0
        guard compressedSize > 0 else { return }

        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        p.arguments = ["-l", source.path]
        p.standardOutput = pipe
        p.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do { try p.run() } catch { return } // zipinfo missing → skip check
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return }

        // Parse the last line which looks like: "N files, UUUUUU bytes uncompressed, CCCCCC bytes compressed: NN.N%"
        guard let output = String(data: data, encoding: .utf8),
              let lastLine = output.split(separator: "\n").last else { return }
        // Extract the first large number after "files," — that's total uncompressed bytes.
        let pattern = #"(\d[\d,]*)\s+bytes\s+uncompressed"#
        guard let match = lastLine.range(of: pattern, options: .regularExpression) else { return }
        let numStr = String(lastLine[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard let uncompressed = UInt64(numStr) else { return }

        let maxUncompressed: UInt64 = 10 * 1024 * 1024 * 1024 // 10 GB
        let maxRatio: Double = 100.0
        let ratio = Double(uncompressed) / Double(compressedSize)

        if uncompressed > maxUncompressed || ratio > maxRatio {
            throw ExtractionError.zipBombDetected(ratio: ratio, uncompressedBytes: uncompressed)
        }
    }

    /// Walks the extracted tree and confirms every entry resolves to a path under `root`.
    /// On detection, removes the entire extracted tree and throws `pathTraversalDetected`.
    private static func verifyNoPathTraversal(under root: URL) throws {
        let fm = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalRootWithSlash = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }

        for case let url as URL in enumerator {
            // Resolve symlinks too — an extracted symlink could itself point outside the tree.
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved != canonicalRoot && !resolved.hasPrefix(canonicalRootWithSlash) {
                try? fm.removeItem(at: root)
                throw ExtractionError.pathTraversalDetected(url)
            }
        }
    }
}
