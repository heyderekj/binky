import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Natural-language → ``SortRule``. On macOS 26+ uses on-device Foundation Models when available; falls back to heuristics.
enum RuleSynthesizer {

    static func synthesize(from phrase: String, order: Int) async -> SortRule? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let modelRule = await synthesizeWithFoundationModels(phrase: trimmed, order: order) {
                return modelRule
            }
        }
        #endif

        return heuristicRule(from: trimmed, order: order)
    }

    private static func heuristicRule(from phrase: String, order: Int) -> SortRule {
        var rule = SortRule.fresh(order: order)
        rule.name = String(localized: "From phrase", comment: "NL rule default name.")

        let lower = phrase.lowercased()

        if let destRange = lower.range(of: " to ") {
            let head = String(lower[..<destRange.lowerBound])
            let tail = String(lower[destRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            extractDomains(from: head, into: &rule)
            let dest = tail.split(whereSeparator: \.isWhitespace).joined(separator: "/")
            if !dest.isEmpty {
                rule.destinationRelativePath = dest
            }
        } else {
            extractDomains(from: lower, into: &rule)
        }

        if lower.contains("receipt") || lower.contains("invoice") {
            rule.contentMatch = SortContentMatch(kind: .receipt)
            rule.fileKindFilter = .pdf
        }

        return rule
    }

    private static func extractDomains(from head: String, into rule: inout SortRule) {
        if head.contains("from ") {
            let raw = head.replacingOccurrences(of: "from ", with: "")
            let parts = raw.split(whereSeparator: { $0 == "," || $0 == ";" })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            rule.originDomains = parts
        }
    }

    #if canImport(FoundationModels)
    /// Guided generation: the model fills this shape directly, so there's no JSON to parse or get wrong.
    /// Case names match the raw values of ``SortFileKindFilter`` and ``SortContentMatchKind``.
    @available(macOS 26.0, *)
    @Generable
    fileprivate struct SynthesizedRule {
        @Guide(description: "Short rule name, two to four words.")
        var name: String
        @Guide(description: "Download origin domains as globs, like *.stripe.com. Empty when the phrase names no site.")
        var originDomains: [String]
        @Guide(description: "Destination folder relative to the watched folder, like Finance/Receipts.")
        var destinationRelativePath: String
        var fileKindFilter: FileKind
        @Guide(description: "What the file's content should look like. none unless the phrase says so.")
        var contentMatchKind: ContentKind

        @Generable
        enum FileKind {
            case any, image, movie, audio, archive, pdf, document
        }

        @Generable
        enum ContentKind {
            case none, ocrText, receipt, screenshot, photo, documentScan, ticket
        }
    }

    @available(macOS 26.0, *)
    private static func synthesizeWithFoundationModels(phrase: String, order: Int) async -> SortRule? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
        let instructions = """
        Turn the user's phrase into one inbox file sort rule for a Downloads folder.
        Leave fields empty or at any/none when the phrase doesn't mention them.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let out = try await session.respond(to: phrase, generating: SynthesizedRule.self).content

            var rule = SortRule.fresh(order: order)
            let name = out.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { rule.name = name }
            let dest = out.destinationRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            if !dest.isEmpty { rule.destinationRelativePath = dest }
            rule.originDomains = out.originDomains
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            if let kind = SortFileKindFilter(rawValue: String(describing: out.fileKindFilter)) {
                rule.fileKindFilter = kind
            }
            if var content = SortContentMatchKind(rawValue: String(describing: out.contentMatchKind)) {
                if content.requiresVisionModel, !Self.visionModelAvailable {
                    content = .none
                }
                rule.contentMatch = SortContentMatch(kind: content)
            }
            return rule
        } catch {
            return nil
        }
    }

    private static var visionModelAvailable: Bool {
        if #available(macOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
        return false
    }
    #endif
}
