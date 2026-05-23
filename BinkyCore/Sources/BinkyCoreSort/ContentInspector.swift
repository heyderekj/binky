import AppKit
import BinkyCoreShared
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// On-device content inspection (Vision OCR, PDF text / receipt heuristics). Cached by file content hash.
enum ContentInspector {

    private final class CacheEntry: NSObject {
        let result: ContentInspectionResult
        let cost: Int
        init(result: ContentInspectionResult, cost: Int) {
            self.result = result
            self.cost = cost
        }
    }

    /// `NSCache` is already thread-safe — wrapping it in an extra `NSLock` only added contention
    /// across the (up to 8) concurrent sort workers without any correctness benefit.
    /// `totalCostLimit` bounds resident text bytes so a few large OCR results don't push the cache
    /// past a reasonable footprint even when `countLimit` would otherwise allow it.
    private static let cache: NSCache<NSString, CacheEntry> = {
        let c = NSCache<NSString, CacheEntry>()
        c.countLimit = 80
        c.totalCostLimit = 2 * 1024 * 1024 // 2 MB of OCR text payload
        return c
    }()

    struct ContentInspectionResult: Sendable, Equatable {
        var hasSignificantOCR: Bool
        var isReceiptLike: Bool
        var dominantOCRLine: String?
        var vendorSlug: String?
        var amountSlug: String?
    }

    static let emptyInspection = ContentInspectionResult(
        hasSignificantOCR: false,
        isReceiptLike: false,
        dominantOCRLine: nil,
        vendorSlug: nil,
        amountSlug: nil
    )

    // MARK: - Public

    static func matchInput(
        for url: URL,
        signals: SortRulesEvaluator.FileSignals,
        snapshot: SortPreferencesSnapshot
    ) async -> SortRulesEvaluator.ContentRuleMatchInput {
        let r = await inspect(url: url, signals: signals, snapshot: snapshot)
        return SortRulesEvaluator.ContentRuleMatchInput(
            hasSignificantOCR: r.hasSignificantOCR,
            isReceiptLike: r.isReceiptLike
        )
    }

    /// Full inspection for smart rename + receipt routing.
    /// - Parameter contentIdentitySHA256: When set (e.g. from duplicate-detection digest), used as cache key so the file is not hashed again.
    static func inspect(
        for url: URL,
        signals: SortRulesEvaluator.FileSignals,
        snapshot: SortPreferencesSnapshot,
        contentIdentitySHA256: String? = nil
    ) async -> ContentInspectionResult {
        await inspect(url: url, signals: signals, snapshot: snapshot, contentIdentitySHA256: contentIdentitySHA256)
    }

    private static func inspect(
        url: URL,
        signals: SortRulesEvaluator.FileSignals,
        snapshot: SortPreferencesSnapshot,
        contentIdentitySHA256: String? = nil
    ) async -> ContentInspectionResult {
        if EnergyConditions.shared.shouldPauseFully {
            return emptyInspection
        }

        let cacheKeyNSString = (cacheKeyString(path: url.path, signals: signals, contentIdentitySHA256: contentIdentitySHA256) as NSString)
        if let hit = cachedResult(for: cacheKeyNSString) {
            return hit
        }

        let ext = signals.ext
        let originHosts = signals.originHosts
        let result: ContentInspectionResult
        if ext == "pdf" {
            result = inspectPDF(at: url, snapshot: snapshot, originHosts: originHosts)
        } else if isImageExtension(ext) {
            result = await inspectImage(at: url, snapshot: snapshot, originHosts: originHosts)
        } else {
            result = emptyInspection
        }

        cacheResult(result, for: cacheKeyNSString)
        return result
    }

    /// In-process cache key: full SHA-256 when available, else path + size + mtime (no full-file read).
    private static func cacheKeyString(path: String, signals: SortRulesEvaluator.FileSignals, contentIdentitySHA256: String?) -> String {
        if let contentIdentitySHA256, !contentIdentitySHA256.isEmpty {
            return "sha256:\(contentIdentitySHA256)"
        }
        let m = signals.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(path)|\(signals.byteSize)|\(m)"
    }

    // MARK: - Smart screenshot rename (post-move)

    /// When enabled, renames screenshot-category files using OCR line. Returns nil if unchanged.
    static func preferredSmartScreenshotName(
        fileURL: URL,
        naturalCategory: FileSortCategory,
        snapshot: SortPreferencesSnapshot,
        signals: SortRulesEvaluator.FileSignals? = nil,
        contentIdentitySHA256: String? = nil
    ) async -> String? {
        guard snapshot.sortSmartScreenshotNamesEnabled else { return nil }
        guard naturalCategory == .screenshots else { return nil }
        guard isImageExtension(fileURL.pathExtension.lowercased()) else { return nil }
        if EnergyConditions.shared.shouldPauseFully { return nil }

        let sig = signals
            ?? SortRulesEvaluator.loadSignals(url: fileURL)
            ?? SortRulesEvaluator.FileSignals(
                ext: fileURL.pathExtension.lowercased(),
                baseName: fileURL.lastPathComponent,
                byteSize: 0,
                addedToDirectoryDate: nil,
                creationDate: nil,
                modificationDate: nil,
                originHosts: []
            )
        let r = await inspect(url: fileURL, signals: sig, snapshot: snapshot, contentIdentitySHA256: contentIdentitySHA256)
        guard let line = r.dominantOCRLine, wordCount(line) >= 3 else { return nil }
        let slug = slugifyOCRTitle(line, maxLen: 60)
        guard !slug.isEmpty else { return nil }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        let dateStr = df.string(from: Date())
        let ext = fileURL.pathExtension
        let dotExt = ext.isEmpty ? "" : ".\(ext)"
        return "\(dateStr) \(slug)\(dotExt)"
    }

    // MARK: - Image + PDF

    private static func inspectImage(
        at url: URL,
        snapshot: SortPreferencesSnapshot,
        originHosts: [String]
    ) async -> ContentInspectionResult {
        guard let cg = cgImageThumbnailForVision(fromFile: url, maxPixelSize: 1600) else {
            return emptyInspection
        }
        // Fast pass first. If Vision detected zero text regions at all, the image is almost
        // certainly a photo / illustration and re-running in `.accurate` mode just burns CPU+GPU
        // without producing different output. We only escalate when fast saw text observations
        // but couldn't read them confidently (`text.isEmpty && fast.observationsFound`).
        let fast = await recognizeText(on: cg, accurate: false)
        let merged: String
        if !fast.text.isEmpty {
            merged = fast.text
        } else if fast.observationsFound {
            merged = await recognizeText(on: cg, accurate: true).text
        } else {
            merged = ""
        }
        let dominant = dominantLine(from: merged)
        let ocrStrong = wordCount(merged) >= 3
        var isReceipt = false
        var vendor: String?
        var amount: String?
        if snapshot.sortDetectReceiptsEnabled {
            let bundle = receiptHeuristic(fullText: merged, originHosts: originHosts)
            isReceipt = bundle.isReceipt
            vendor = bundle.vendor
            amount = bundle.amount
        }
        return ContentInspectionResult(
            hasSignificantOCR: ocrStrong,
            isReceiptLike: isReceipt,
            dominantOCRLine: dominant,
            vendorSlug: vendor.map { slugifyOCRTitle($0, maxLen: 40) },
            amountSlug: amount
        )
    }

    /// Downsampled bitmap for Vision (avoids decoding full-resolution screenshots).
    private static func cgImageThumbnailForVision(fromFile url: URL, maxPixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    private static func inspectPDF(at url: URL, snapshot: SortPreferencesSnapshot, originHosts: [String]) -> ContentInspectionResult {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0, let page = doc.page(at: 0) else {
            return emptyInspection
        }
        let rawText = page.string ?? ""
        var fullText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        if fullText.count < 40 {
            let thumb = page.thumbnail(of: CGSize(width: 512, height: 512), for: .mediaBox)
            var prop = CGRect(origin: .zero, size: thumb.size)
            if let cg = thumb.cgImage(forProposedRect: &prop, context: nil, hints: nil),
               let ocrResult = try? recognizeTextSync(on: cg, accurate: false),
               ocrResult.text.count > fullText.count {
                fullText = ocrResult.text
            }
        }

        let dominant = dominantLine(from: fullText)
        let ocrStrong = wordCount(fullText) >= 3
        var isReceipt = false
        var vendor: String?
        var amount: String?
        if snapshot.sortDetectReceiptsEnabled {
            let bundle = receiptHeuristic(fullText: fullText, originHosts: originHosts)
            isReceipt = bundle.isReceipt
            vendor = bundle.vendor
            amount = bundle.amount
        }
        return ContentInspectionResult(
            hasSignificantOCR: ocrStrong,
            isReceiptLike: isReceipt,
            dominantOCRLine: dominant,
            vendorSlug: vendor.map { slugifyOCRTitle($0, maxLen: 40) },
            amountSlug: amount
        )
    }

    private static func recognizeTextSync(on cgImage: CGImage, accurate: Bool) throws -> (text: String, observationsFound: Bool) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let obs = request.results ?? []
        let text = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return (text, !obs.isEmpty)
    }

    private static func recognizeText(on cgImage: CGImage, accurate: Bool) async -> (text: String, observationsFound: Bool) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    cont.resume(returning: try recognizeTextSync(on: cgImage, accurate: accurate))
                } catch {
                    cont.resume(returning: ("", false))
                }
            }
        }
    }

    // MARK: - Receipt heuristic

    private struct ReceiptBundle {
        var isReceipt: Bool
        var vendor: String?
        var amount: String?
    }

    private static func receiptHeuristic(fullText: String, originHosts: [String]) -> ReceiptBundle {
        let lower = fullText.lowercased()
        let keyword = #"(invoice|receipt|tax invoice|amount due|total due|paid|statement)"#
        let hasKeyword = lower.range(of: keyword, options: .regularExpression) != nil
        let amountPat = #"(?:\$|€|£)\s*\d[\d,]*\.\d{2}\b"#
        let hasMoney = fullText.range(of: amountPat, options: .regularExpression) != nil
        let firstLine = fullText.split(separator: "\n").map(String.init).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var vendor = firstLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = vendor, v.count > 48 { vendor = String(v.prefix(48)) }
        if let host = originHosts.first {
            if vendor == nil || (vendor?.count ?? 0) < 2 {
                vendor = host.split(separator: ".").first.map { String($0).capitalized }
            }
        }
        var amountStr: String?
        if let m = fullText.range(of: amountPat, options: .regularExpression) {
            amountStr = String(fullText[m]).filter { "0123456789.".contains($0) || $0 == "," }
        }
        let isReceipt = (hasKeyword && hasMoney) || (hasMoney && vendor != nil)
        return ReceiptBundle(isReceipt: isReceipt, vendor: vendor, amount: amountStr)
    }

    // MARK: - Helpers

    private static func isImageExtension(_ ext: String) -> Bool {
        let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif"]
        if images.contains(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }

    private static func wordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static func dominantLine(from text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.max { a, b in
            let wa = wordCount(a), wb = wordCount(b)
            if wa != wb { return wa < wb }
            return a.count < b.count
        }
    }

    private static func slugifyOCRTitle(_ raw: String, maxLen: Int) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(raw.unicodeScalars.filter { allowed.contains($0) })
        let parts = cleaned.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        var out = parts.joined(separator: "-")
        if out.count > maxLen {
            out = String(out.prefix(maxLen)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return out
    }

    private static func cachedResult(for key: NSString) -> ContentInspectionResult? {
        cache.object(forKey: key)?.result
    }

    private static func cacheResult(_ result: ContentInspectionResult, for key: NSString) {
        // Approximate the resident cost: dominant line + vendor + amount strings (UTF-16 bytes).
        // Per-entry cost is small but matters when many large screenshots are inspected in a row.
        let textBytes =
            (result.dominantOCRLine?.utf16.count ?? 0) +
            (result.vendorSlug?.utf16.count ?? 0) +
            (result.amountSlug?.utf16.count ?? 0)
        // Each UTF-16 unit is 2 bytes. Add a ~64-byte overhead for the NSObject + struct itself.
        let cost = textBytes * 2 + 64
        cache.setObject(CacheEntry(result: result, cost: cost), forKey: key, cost: cost)
    }
}
