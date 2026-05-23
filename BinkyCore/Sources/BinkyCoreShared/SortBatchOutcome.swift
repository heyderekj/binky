import Foundation

public struct SortBatchOutcome: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let started: Date
    public let elapsed: TimeInterval
    public let entries: [SortBatchEntry]
    /// Secondary messages (Finder tag failures, offline tools, etc.) — not persisted as audit rows.
    public var ancillaryWarnings: [String]

    public var movedCount: Int { entries.filter { $0.disposition == .moved }.count }
    public var keptCount: Int { entries.filter { $0.disposition == .kept }.count }

    public var skippedCount: Int {
        entries.count(where: {
            switch $0.disposition {
            case .skippedTransient, .skippedStableCheckTimeout, .skippedError, .skippedExcluded, .skippedDuplicate:
                return true
            default:
                return false
            }
        })
    }

    public var reviewQueuedCount: Int {
        entries.filter { $0.disposition == .moved && $0.category == .review }.count
    }

    public var hasWork: Bool { !entries.isEmpty }

    public var reversibleMoves: [(destination: URL, source: URL)] {
        entries.compactMap {
            guard $0.disposition == .moved, let dst = $0.destinationPath else { return nil }
            return (URL(fileURLWithPath: dst), URL(fileURLWithPath: $0.sourcePath))
        }
    }

    public init(id: UUID, started: Date, elapsed: TimeInterval, entries: [SortBatchEntry], ancillaryWarnings: [String] = []) {
        self.id = id
        self.started = started
        self.elapsed = elapsed
        self.entries = entries
        self.ancillaryWarnings = ancillaryWarnings
    }

    enum CodingKeys: String, CodingKey {
        case id, started, elapsed, entries, ancillaryWarnings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        started = try c.decode(Date.self, forKey: .started)
        elapsed = try c.decode(TimeInterval.self, forKey: .elapsed)
        entries = try c.decode([SortBatchEntry].self, forKey: .entries)
        ancillaryWarnings = try c.decodeIfPresent([String].self, forKey: .ancillaryWarnings) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(started, forKey: .started)
        try c.encode(elapsed, forKey: .elapsed)
        try c.encode(entries, forKey: .entries)
        if !ancillaryWarnings.isEmpty {
            try c.encode(ancillaryWarnings, forKey: .ancillaryWarnings)
        }
    }
}

extension SortBatchOutcome {
    /// Most likely originating watch root, derived by tallying which routine path is the longest
    /// matching prefix of each entry's source.
    public func matchedRoutine(in presets: [Inbox]) -> Inbox? {
        guard !entries.isEmpty else { return nil }
        var tally: [UUID: (preset: Inbox, hits: Int, length: Int)] = [:]

        for entry in entries {
            let sourcePath = URL(fileURLWithPath: entry.sourcePath).standardizedFileURL.path
            var localBest: (preset: Inbox, length: Int)?
            for preset in presets {
                let raw = preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let normalized = URL(fileURLWithPath: raw).standardizedFileURL.path
                guard sourcePath == normalized || sourcePath.hasPrefix(normalized + "/") else { continue }
                if localBest == nil || normalized.count > localBest!.length {
                    localBest = (preset, normalized.count)
                }
            }
            if let lb = localBest {
                if var existing = tally[lb.preset.id] {
                    existing.hits += 1
                    tally[lb.preset.id] = existing
                } else {
                    tally[lb.preset.id] = (lb.preset, 1, lb.length)
                }
            }
        }

        return tally.values.max { lhs, rhs in
            if lhs.hits != rhs.hits { return lhs.hits < rhs.hits }
            return lhs.length < rhs.length
        }?.preset
    }

    public func sourceRootURL(in presets: [Inbox]) -> URL? {
        if let preset = matchedRoutine(in: presets),
           !preset.watchFolderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: preset.watchFolderPath).standardizedFileURL
        }
        guard let firstSource = entries.first?.sourcePath else { return nil }
        return URL(fileURLWithPath: firstSource).deletingLastPathComponent()
    }
}
