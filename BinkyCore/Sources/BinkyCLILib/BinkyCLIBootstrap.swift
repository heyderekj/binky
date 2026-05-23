import BinkyCoreShared
import BinkyCoreSort
import Foundation

public enum BinkyCLIBootstrap {
    /// Blocking entry (`main` awaits this synchronously).
    public nonisolated static func run(_ argv: [String]) -> Int32 {
        if argv.first == "--version" || argv.first == "-V" {
            print("\(BinkyCLIPackageMeta.toolName) \(BinkyCLIPackageMeta.version)")
            return 0
        }

        if argv.isEmpty {
            BinkyCLIHelp.printHelp(to: FileHandle.standardOutput)
            return 0
        }

        if argv.count == 1, ["help", "--help", "-h"].contains(argv[0]) {
            BinkyCLIHelp.printHelp(to: FileHandle.standardOutput)
            return 0
        }

        let prefs = BinkyPrefsStore()

        var args = argv
        if args.first == "automations" {
            BinkyCLIPrint.err(
                "warning: \"automations\" is deprecated — use \"routines\" (same syntax, same prefs)."
            )
            args[0] = "routines"
        }

        guard let verb = args.first else {
            BinkyCLIHelp.printHelp(to: FileHandle.standardOutput)
            return 0
        }

        let rest = Array(args.dropFirst())

        switch verb {
        case "sort":
            switch BinkyCLIParse.peelPathOpts(tokens: rest) {
            case let .failure(err):
                switch err {
                case let .missingFlagValue(flag):
                    BinkyCLIPrint.err("sort: missing value for \(flag).")
                case let .unknownFlag(flag):
                    BinkyCLIPrint.err("sort: unknown flag \(flag).")
                }
                return 1
            case let .success(bundle):
                if bundle.opts.dryRun {
                    BinkyCLIPrint.err("sort: --dry-run → preview semantics (nothing is moved).")
                    return BinkyCLIPreviewCommand.execute(rawArgs: rest, prefs: prefs)
                }
                return BinkyCLISortCommand.execute(rawArgs: rest, prefs: prefs)
            }

        case "preview":
            return BinkyCLIPreviewCommand.execute(rawArgs: rest, prefs: prefs)

        case "undo":
            return BinkyCLIUndoCommand.execute(rawArgs: rest, prefs: prefs)

        case "routines":
            guard let sub = rest.first else {
                BinkyCLIPrint.err("routines: try `\(BinkyCLIPackageMeta.toolName) routines list` or `… run <name>`.")
                return 1
            }
            let tail = Array(rest.dropFirst())
            switch sub {
            case "list":
                return BinkyCLIRoutinesCommand.execute(listArgs: tail, prefs: prefs)

            case "run":
                return BinkyCLIRoutinesCommand.executeRun(runArgs: tail, prefs: prefs)

            default:
                BinkyCLIPrint.err("routines: unknown subcommand “\(sub)”.")
                return 1
            }

        case "tag":
            return BinkyCLITagCommand.execute(rawArgs: rest, prefs: prefs)

        case "ingest":
            // v2 dry-run: classify + origin + hash + heuristic suggestion.
            // Read-only; never moves files. Has no preference dependency, so
            // we don't pass `prefs` here.
            return BinkyCLIIngestCommand.execute(rawArgs: rest)

        case "version":
            print("\(BinkyCLIPackageMeta.toolName) \(BinkyCLIPackageMeta.version)")
            return 0

        case "help":
            BinkyCLIHelp.printHelp(to: FileHandle.standardOutput)
            return 0

        default:
            BinkyCLIPrint.err("\(BinkyCLIPackageMeta.toolName): unknown command “\(verb)”.")
            BinkyCLIPrint.err("Run `\(BinkyCLIPackageMeta.toolName) --help`.")
            return 1
        }
    }
}
