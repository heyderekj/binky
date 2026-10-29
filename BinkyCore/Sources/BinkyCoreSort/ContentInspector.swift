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
        init(result: ContentInspectionResult) {
            self.result = result
        }
    }

    private static let cacheLock = NSLock()
    private static let cache: NSCache<NSString, CacheEntry> = {
        let c = NSCache<NSString, CacheEntry>()
        c.countLimit = 80
        return c
    }()

    struct ContentInspectionResult: Sendable, Equatable {
        var hasSignificantOCR: Bool
        var isReceiptLike: Bool
        var dominantOCRLine: String?
        var vendorSlug: String?
        var amountSlug: String?
        /// Only filled when a rule asked (``SortRulesEvaluator/anyRuleRequiresVisualCategory(_:)``).
        var visualTraits: Set<SortVisualCategory> = []
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
        return r.ruleMatchInput
    }

    /// Full inspection for smart rename + receipt routing.
    /// - Parameter contentIdentitySHA256: When set (e.g. from duplicate-detection digest), used as cache key so the file is not hashed again.
    static func inspect(
        for url: URL,
        signals: SortRulesEvaluator.FileSignals,
        snapshot: SortPreferencesSnapshot,
        contentIdentitySHA256: String? = nil,
        wantsVisualTraits: Bool = false
    ) async -> ContentInspectionResult {
        await inspect(
            url: url,
            signals: signals,
            snapshot: snapshot,
            contentIdentitySHA256: contentIdentitySHA256,
            wantsVisualTraits: wantsVisualTraits
        )
    }

    private static func inspect(
        url: URL,
        signals: SortRulesEvaluator.FileSignals,
        snapshot: SortPreferencesSnapshot,
        contentIdentitySHA256: String? = nil,
        wantsVisualTraits: Bool = false
    ) async -> ContentInspectionResult {
        if EnergyConditions.shared.shouldPauseFully {
            return emptyInspection
        }

        var cacheKey = cacheKeyString(path: url.path, signals: signals, contentIdentitySHA256: contentIdentitySHA256)
        if wantsVisualTraits { cacheKey += "|visual" }
        let cacheKeyNSString = cacheKey as NSString
        if let hit = cachedResult(for: cacheKeyNSString) {
            return hit
        }

        let ext = signals.ext
        let originHosts = signals.originHosts
        var result: ContentInspectionResult
        if ext == "pdf" {
            result = inspectPDF(at: url, snapshot: snapshot, originHosts: originHosts)
        } else if isImageExtension(ext) {
            result = await inspectImage(at: url, snapshot: snapshot, originHosts: originHosts)
        } else {
            result = emptyInspection
        }
        if wantsVisualTraits, ext == "pdf" || isImageExtension(ext) {
            result.visualTraits = await VisualClassifier.traits(for: url, isPDF: ext == "pdf")
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

    // MARK: - Text sample (for the language model)

    /// Up to `maxChars` of readable text: the PDF text layer (OCR when it has none), OCR for images,
    /// or the start of a plain-text file. Empty when there's nothing to read.
    static func textSample(for url: URL, maxChars: Int) async -> String {
        let ext = url.pathExtension.lowercased()
        var text = ""
        if ext == "pdf" {
            if let doc = PDFDocument(url: url), doc.pageCount > 0 {
                text = (0..<min(doc.pageCount, 2)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40, let page = doc.page(at: 0) {
                    let thumb = page.thumbnail(of: CGSize(width: 1024, height: 1024), for: .mediaBox)
                    var rect = CGRect(origin: .zero, size: thumb.size)
                    if let cg = thumb.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                        text = await recognizeText(on: cg, accurate: false)
                    }
                }
            }
        } else if isImageExtension(ext) {
            if let cg = cgImageThumbnailForVision(fromFile: url, maxPixelSize: 1600) {
                text = await recognizeText(on: cg, accurate: false)
            }
        } else if UTType(filenameExtension: ext)?.conforms(to: .plainText) == true,
                  let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: maxChars * 4)) ?? Data()
            text = String(decoding: data, as: UTF8.self)
        }
        let collapsed = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return String(collapsed.prefix(maxChars))
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
        let text = await recognizeText(on: cg, accurate: false)
        let merged = text.isEmpty ? await recognizeText(on: cg, accurate: true) : text
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
               let ocrText = try? recognizeTextSync(on: cg, accurate: false),
               ocrText.count > fullText.count {
                fullText = ocrText
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

    private static func recognizeTextSync(on cgImage: CGImage, accurate: Bool) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let obs = request.results ?? []
        return obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func recognizeText(on cgImage: CGImage, accurate: Bool) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try recognizeTextSync(on: cgImage, accurate: accurate)
                    cont.resume(returning: text)
                } catch {
                    cont.resume(returning: "")
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
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache.object(forKey: key)?.result
    }

    private static func cacheResult(_ result: ContentInspectionResult, for key: NSString) {
        cacheLock.lock()
        cache.setObject(CacheEntry(result: result), forKey: key)
        cacheLock.unlock()
    }
}

extension ContentInspector.ContentInspectionResult {
    var ruleMatchInput: SortRulesEvaluator.ContentRuleMatchInput {
        SortRulesEvaluator.ContentRuleMatchInput(
            hasSignificantOCR: hasSignificantOCR,
            isReceiptLike: isReceiptLike,
            visualTraits: visualTraits
        )
    }
}
