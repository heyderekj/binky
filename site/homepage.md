# Binky

**Tagline:** Binky sorts your files.

A native macOS sorter that follows your rules — no cloud, no guessing. **Quick Sort** tidies a fussy folder in one tap; **Routines** watch continuously with the same routing logic. Binky waits for files to finish landing, then sorts them into sensible sorted folders — Images, PDFs, Media, Documents, Archives, Apps, Screenshots, Misc. Source-aware routing, plain-English rules, receipt detection, duplicate guard, smart screenshot names, optional housekeeping (stale-file aging), daily and optional weekly digest reminders, and a shareable weekly digest card from history. Unknowns route to **Review** so nothing sketchy silently disappears. Optional Finder tags; history with reveal and undo where macOS allows.

- **Site:** [binkyfiles.com](https://binkyfiles.com)
- **Repo:** [GitHub — heyderekj/binky](https://github.com/heyderekj/binky)
- **Support:** [derek@testamentmade.com](mailto:derek@testamentmade.com)
- **Version line:** Apple Silicon & Intel · macOS 14 Sonoma or later · 1.x free · Open source (MIT) · 2.0 adds one-time license for official builds (see site FAQ)
- **Sister app:** [Dinky](https://dinkyfiles.com) (compression) — current releases need Apple Silicon and **macOS 15**; see dinkyfiles.com

## Highlights

- **Quick Sort** — one-tap sweep for any folder (defaults to `~/Downloads`); waits for downloads to finish, collision-safe moves
- **Routines** — named watchers with their own sources, rules, and optional Finder tags; plain-English rule building on macOS 26+
- **Source-aware routing** — match by download origin and content, not just filename
- **Receipt & invoice detection** — routes financial PDFs when content looks like a receipt
- **Duplicate guard** — hashing before files settle
- **CLI (`binky`)** — sort, preview, and run Routines from Terminal; same rules and prefs as the app; build from source with SwiftPM
- **Shortcuts** — “Sort Files” App Intent passes paths to the running app
- **Daily & weekly digest** — optional notifications; weekly share card (PNG) from session history
- **Review folder** — ambiguous types land here first
- **History** — batch summaries; undo where possible

## Install

**Download:** [Binky for macOS (DMG)](https://github.com/heyderekj/binky/releases/download/v1.7.0/Binky-1.7.0.dmg) — or install with [Homebrew](https://brew.sh): `brew tap heyderekj/binky https://github.com/heyderekj/binky` then `brew install --cask binky`

**GitHub:** Latest release and DMG/ZIP: [github.com/heyderekj/binky/releases/latest](https://github.com/heyderekj/binky/releases/latest)

**Homebrew:**

```bash
brew tap heyderekj/binky https://github.com/heyderekj/binky
brew install --cask binky
```

**Gatekeeper:** if macOS blocks the first launch, **System Settings → Privacy & Security → Open Anyway**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Binky.app
```

## More

Machine-readable site summary: [llms.txt](https://binkyfiles.com/llms.txt)

© Testament Made, LLC
