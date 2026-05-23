import BinkyCoreShared
import Foundation

/// Predicts where a file should go based on the user's past decisions.
///
/// Priority (high → low):
/// 1. Exact origin host match — "stripe.com PDFs always went to ~/报税/"
/// 2. Filename pattern match — "files containing 'invoice' went to ~/报税/"
/// 3. Recent context — "this week you've been putting videos in ~/杭州旅行/"
/// 4. Category default (cold-start fallback) — "PDFs → ~/Documents/"
///
/// Returns up to `maxCandidates` ranked destinations. The caller (adapter)
/// wraps each into a `Suggestion` with the corresponding confidence.
public struct DestinationPredictor: Sendable {

    /// One candidate destination with a reason the user can read.
    public struct Candidate: Equatable, Sendable {
        public let url: URL
        public let confidence: Double
        public let reason: String

        public init(url: URL, confidence: Double, reason: String) {
            self.url = url
            self.confidence = confidence
            self.reason = reason
        }
    }

    private let store: SuggestionStore
    private let fallbackRoot: URL

    /// - Parameters:
    ///   - store: Decision history to learn from.
    ///   - fallbackRoot: Root for cold-start type-based defaults (e.g. ~/Downloads).
    public init(store: SuggestionStore = .shared, fallbackRoot: URL) {
        self.store = store
        self.fallbackRoot = fallbackRoot
    }

    /// Returns up to `maxCandidates` ranked destinations for the given file.
    public func predict(
        for url: URL,
        category: FileSortCategory,
        originHost: String?,
        maxCandidates: Int = 3
    ) -> [Candidate] {
        let history = store.allAcceptedMoveRecords()
        var scored: [URL: (score: Double, reason: String)] = [:]

        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        let now = Date()

        for record in history {
            guard let dest = extractMoveDestination(from: record) else { continue }

            var score: Double = 0
            var reason = ""

            // Signal 1: exact origin host match (strongest)
            if let host = originHost, !host.isEmpty,
               record.sourcePath.lowercased().contains(host) || matchesOriginInHistory(record, host: host) {
                score += 0.5
                reason = "You filed \(host) files here before"
            }

            // Signal 2: filename pattern (keywords in common)
            let recordFilename = (record.sourcePath as NSString).lastPathComponent.lowercased()
            let commonKeywords = sharedKeywords(filename, recordFilename)
            if !commonKeywords.isEmpty {
                score += 0.3 * min(Double(commonKeywords.count), 3.0) / 3.0
                if reason.isEmpty { reason = "Similar filename pattern" }
            }

            // Signal 3: same extension
            let recordExt = (record.sourcePath as NSString).pathExtension.lowercased()
            if !ext.isEmpty && ext == recordExt {
                score += 0.1
                if reason.isEmpty { reason = "You put .\(ext) files here" }
            }

            // Signal 4: recency boost (decisions in last 7 days get a bump)
            let age = now.timeIntervalSince(record.decidedAt)
            if age < 7 * 24 * 3600 {
                score += 0.15
                if reason.isEmpty { reason = "Recently used" }
            }

            // Accumulate (same dest from multiple records → higher score)
            let destKey = dest.standardizedFileURL
            if let existing = scored[destKey] {
                scored[destKey] = (existing.score + score, existing.reason)
            } else {
                scored[destKey] = (score, reason)
            }
        }

        // Build candidates from scored destinations
        var candidates = scored.map { (dest, info) in
            Candidate(
                url: dest,
                confidence: min(info.score, 0.95), // cap below 1.0
                reason: info.reason
            )
        }
        .sorted { $0.confidence > $1.confidence }
        .prefix(maxCandidates - 1) // leave room for fallback
        .map { $0 }

        // Always include the type-based fallback as the last candidate
        let fallbackDest = fallbackRoot.appendingPathComponent(category.downloadsSubfolder, isDirectory: true)
        let alreadyHasFallback = candidates.contains { $0.url.standardizedFileURL == fallbackDest.standardizedFileURL }
        if !alreadyHasFallback {
            candidates.append(Candidate(
                url: fallbackDest,
                confidence: 0.4,
                reason: "Default for \(category.rawValue)"
            ))
        }

        return Array(candidates.prefix(maxCandidates))
    }

    // MARK: - Helpers

    private func extractMoveDestination(from record: DecisionRecord) -> URL? {
        // actionKey format is "move:/path/to/dest"
        guard record.actionKey.hasPrefix("move:") else { return nil }
        let path = String(record.actionKey.dropFirst(5))
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func matchesOriginInHistory(_ record: DecisionRecord, host: String) -> Bool {
        // Check if the record's source path suggests same origin
        // (heuristic: the host appears in the source filename or path)
        record.sourcePath.lowercased().contains(host.lowercased())
    }

    private func sharedKeywords(_ a: String, _ b: String) -> [String] {
        let stopWords: Set<String> = ["the", "a", "an", "of", "in", "to", "for", "and", "or", "at", "by"]
        let wordsA = Set(a.split { !$0.isLetter && !$0.isNumber }.map { String($0).lowercased() })
            .subtracting(stopWords)
            .filter { $0.count > 2 }
        let wordsB = Set(b.split { !$0.isLetter && !$0.isNumber }.map { String($0).lowercased() })
            .subtracting(stopWords)
            .filter { $0.count > 2 }
        return Array(wordsA.intersection(wordsB))
    }
}

// MARK: - SuggestionStore extension for DestinationPredictor
// (lives in this file because it needs access to store internals;
//  the extension is declared in SuggestionStore.swift instead)
