import Foundation

enum BinkyCLIHelp {
    static func printHelp(to handle: FileHandle) {
        let exe = BinkyCLIPackageMeta.toolName
        let text = """
        \(exe) — Binky sorting from Terminal (same rules & prefs as the app).

        Build:
          cd BinkyCore && swift build -c release  → .build/release/\(exe)

        Usage:
          \(exe) sort [--root <dir>] [--json] [--quiet] [--dry-run] <paths…|->
          \(exe) preview [--root <dir>] [--json] [--quiet] <paths…|->
          \(exe) undo [--batch <uuid>] [--json] [--quiet]
          \(exe) routines list [--json] [--quiet]
          \(exe) routines run <name…> [--json] [--quiet]
          \(exe) tag [--json] [--quiet] <paths…|->
          \(exe) ingest [--inbox-root <dir>] [--json] <paths…>     (v2 dry-run; read-only)
          \(exe) help | \(exe) --help | \(exe) -h
          \(exe) version | \(exe) --version

          \(exe) automations …   # hidden alias → routines (stderr warning)

        Paths may include "-" to merge newline-separated paths from stdin.

        Docs (repo): docs/local-cli.md

        Sandbox: Terminal is not sandboxed; it only touches paths you pass. It cannot reuse the GUI app's security-scoped bookmarks.

        """
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
    }
}
