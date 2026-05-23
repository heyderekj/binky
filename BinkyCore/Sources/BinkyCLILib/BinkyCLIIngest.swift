import BinkyCoreShared
import BinkyCoreSort
import Foundation

/// `binky ingest` — runs the v2 ingestion pipeline (`IngestionPipeline` +
/// `HeuristicSuggestionAdapter`) over one or more files and prints a
/// human-readable or JSON report. **Read-only**: nothing on disk is moved.
///
/// This is the first user-visible touch point for the v2 redesign. It does
/// not replace `binky sort` (which still drives the v1 `SortWork` engine and
/// actually moves files); it's a parallel inspection command so the
/// developer can verify the v2 pipeline output against expectations before
/// the engine is wired into Daily Calm UI.
///
/// Usage:
///   binky ingest <paths…> [--json] [--inbox-root <dir>]
///
/// Defaults:
///   --inbox-root  ~/Documents/Binky-v2-preview
///                 (per-category subfolders are appended automatically;
///                  e.g. an ingested PDF suggests moving to
///                  ~/Documents/Binky-v2-preview/Documents/)
enum BinkyCLIIngestCommand {

    private struct ResultEnvelope: Codable {
        let schema: String
        let file: FileResult
    }

    private struct FileResult: Codable {
        let url: String
        let category: String
        let isTransient: Bool
        let originHosts: [String]
        let primaryOriginHost: String?
        let sha256: String?
        let perceptualHex: String?
        let isImage: Bool
        let suggestion: SuggestionPayload?
    }

    private struct SuggestionPayload: Codable {
        let action: String
        let destination: String?
        let renameTo: String?
        let shortcutName: String?
        let confidence: Double?
        let reasoning: String
    }

    nonisolated static func execute(rawArgs: [String]) -> Int32 {
        var paths: [String] = []
        var jsonOutput = false
        var inboxRootPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Documents/Binky-v2-preview")

        var i = 0
        while i < rawArgs.count {
            let arg = rawArgs[i]
            switch arg {
            case "--json":
                jsonOutput = true
                i += 1
            case "--inbox-root":
                guard i + 1 < rawArgs.count else {
                    BinkyCLIPrint.err("ingest: missing value for --inbox-root.")
                    return 1
                }
                inboxRootPath = rawArgs[i + 1]
                i += 2
            case "--quiet":
                // Accept for symmetry with other subcommands; ingest's text mode
                // is the human-readable view, so --quiet is ignored unless
                // combined with --json (in which case we wouldn't print headers
                // anyway). Reserved here so a typo doesn't get treated as a path.
                i += 1
            case let flag where flag.hasPrefix("--"):
                BinkyCLIPrint.err("ingest: unknown flag \(flag).")
                return 1
            default:
                paths.append(arg)
                i += 1
            }
        }

        guard !paths.isEmpty else {
            BinkyCLIPrint.err("ingest: no paths given.")
            BinkyCLIPrint.err("Usage: binky ingest <paths…> [--json] [--inbox-root <dir>]")
            return 1
        }

        let inboxRoot = URL(
            fileURLWithPath: (inboxRootPath as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL

        let inboxRootResolver: InboxRootResolver = { category in
            inboxRoot.appendingPathComponent(category.downloadsSubfolder, isDirectory: true)
        }

        // Wire the engine with DestinationPredictor so CLI output matches
        // what the app would suggest (intent-based, learns from history).
        let predictor = DestinationPredictor(fallbackRoot: inboxRoot)
        let pipeline = IngestionPipeline()
        let engine = SuggestionEngine(
            pipeline: pipeline,
            adapters: [
                HeuristicSuggestionAdapter(inboxRoot: inboxRootResolver, predictor: predictor),
                FoundationModelsSuggestionAdapter(inboxRoot: inboxRootResolver),
            ]
        )

        var anyFailure = false
        let fm = FileManager.default

        for raw in paths {
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
                .standardizedFileURL

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                BinkyCLIPrint.err("ingest: not a regular file — \(url.path)")
                anyFailure = true
                continue
            }

            let outcome = BinkyCLIAsync.runBlocking { () -> Result<(IngestedFile, [Suggestion]), Error> in
                do {
                    // The engine ingests + runs adapters + merges in one call.
                    // We re-ingest separately for the text/JSON view because
                    // we want to surface category/host/SHA-256 alongside the
                    // engine's final merged suggestions.
                    let ingested = try await pipeline.ingest(url)
                    let suggestions = await engine.suggest(for: ingested, context: PipelineContext())
                    return .success((ingested, suggestions))
                } catch {
                    return .failure(error)
                }
            }

            switch outcome {
            case .failure(let error):
                BinkyCLIPrint.err("ingest: \(url.path) — \(error.localizedDescription)")
                anyFailure = true
            case .success(let (ingested, suggestions)):
                if jsonOutput {
                    BinkyCLIPrint.jsonLine(ResultEnvelope(
                        schema: "binky.ingest.result/1.0.0",
                        file: makePayload(url: url, ingested: ingested, suggestions: suggestions)
                    ))
                } else {
                    printPlainText(url: url, ingested: ingested, suggestions: suggestions)
                }
            }
        }

        return anyFailure ? 1 : 0
    }

    // MARK: - JSON payload

    private static func makePayload(
        url: URL,
        ingested: IngestedFile,
        suggestions: [Suggestion]
    ) -> FileResult {
        let suggestion: SuggestionPayload? = suggestions.first.map { s in
            switch s.action {
            case .move(let dest):
                return SuggestionPayload(
                    action: "move",
                    destination: dest.path,
                    renameTo: nil,
                    shortcutName: nil,
                    confidence: s.confidence,
                    reasoning: s.reasoning
                )
            case .rename(let name):
                return SuggestionPayload(
                    action: "rename",
                    destination: nil,
                    renameTo: name,
                    shortcutName: nil,
                    confidence: s.confidence,
                    reasoning: s.reasoning
                )
            case .trash:
                return SuggestionPayload(action: "trash", destination: nil, renameTo: nil, shortcutName: nil, confidence: s.confidence, reasoning: s.reasoning)
            case .keep:
                return SuggestionPayload(action: "keep", destination: nil, renameTo: nil, shortcutName: nil, confidence: s.confidence, reasoning: s.reasoning)
            case .runShortcut(let name):
                return SuggestionPayload(
                    action: "runShortcut",
                    destination: nil,
                    renameTo: nil,
                    shortcutName: name,
                    confidence: s.confidence,
                    reasoning: s.reasoning
                )
            }
        }

        return FileResult(
            url: url.path,
            category: ingested.classification.category.rawValue,
            isTransient: ingested.classification.isTransient,
            originHosts: ingested.originHosts.hosts,
            primaryOriginHost: ingested.originHosts.primary,
            sha256: ingested.hashed?.sha256,
            perceptualHex: ingested.hashed?.perceptual.map { String(format: "%016llx", $0) },
            isImage: ingested.hashed?.isImage ?? false,
            suggestion: suggestion
        )
    }

    // MARK: - Plain-text view

    private static func printPlainText(
        url: URL,
        ingested: IngestedFile,
        suggestions: [Suggestion]
    ) {
        print("File:         \(url.path)")
        print("Category:     \(ingested.classification.category.rawValue)")
        print("Transient:    \(ingested.classification.isTransient ? "yes" : "no")")
        print("Origin:       \(ingested.originHosts.primary ?? "—")")
        if let hashed = ingested.hashed {
            // Truncate SHA-256 for display; the full value is in --json.
            let head = String(hashed.sha256.prefix(12))
            print("SHA-256:      \(head)…  (\(hashed.sha256.count) chars total)")
            if let perceptual = hashed.perceptual {
                print("Perceptual:   \(String(format: "%016llx", perceptual))")
            }
        } else {
            print("SHA-256:      (skipped — transient)")
        }

        if let s = suggestions.first {
            let conf = s.confidence.map { String(format: "%.2f", $0) } ?? "—"
            switch s.action {
            case .move(let dest):
                print("Suggestion:   Move → \(dest.path)   (confidence \(conf))")
            case .rename(let name):
                print("Suggestion:   Rename → \(name)   (confidence \(conf))")
            case .trash:
                print("Suggestion:   Move to Trash   (confidence \(conf))")
            case .keep:
                print("Suggestion:   Keep where it is   (confidence \(conf))")
            case .runShortcut(let name):
                print("Suggestion:   Run Shortcut: \(name)   (confidence \(conf))")
            }
            print("Reason:       \(s.reasoning)")
        } else {
            print("Suggestion:   (none — file is transient or in Review)")
        }
        print("")
    }
}
