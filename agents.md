# Agent notes — Binky (macOS)

Use this alongside `CLAUDE.md` (bundle size rules, brand voice, project context).

## Build & test

```bash
# Build debug
xcodebuild -project Binky.xcodeproj -scheme Binky -configuration Debug build

# Build + run unit tests (the primary verification command)
xcodebuild -project Binky.xcodeproj -scheme Binky -configuration Debug -destination 'platform=macOS' test

# Release build (used by release.sh)
xcodebuild -scheme Binky -configuration Release -derivedDataPath build clean build
```

CI runs on **macOS 26 + Xcode 26** (see `.github/workflows/ci.yml`). There is **no linter, formatter, or typecheck step** beyond what Xcode/Swift provides — `xcodebuild test` is the full gate.

Tests live in `BinkyTests/` (Xcode test target) and import `@testable import Binky` + `@testable import BinkyCoreSort`.

## Architecture

- **`Binky/`** — the Xcode app target (SwiftUI + AppKit). Entry point: `BinkyApp.swift` (`@main`).
- **`BinkyCore/`** — SwiftPM package with four targets:
  - `BinkyCoreShared` — models, prefs keys, batch/history types (no dependencies)
  - `BinkyCoreSort` — sort pipeline, content inspection, rules evaluation, Finder tags, archive/DMG services (depends on `BinkyCoreShared`)
  - `BinkyCLILib` — CLI command implementations (depends on both above)
  - `BinkyCLI` — executable entry point for the `binky` CLI binary
- The app target uses `@_exported import BinkyCoreShared` and `@_exported import BinkyCoreSort` (`BinkyExportedDependencies.swift`) so other app files don't need per-file imports.
- **`BinkyTests/`** — XCTest unit tests (classification, tag composition, routines, WhereFroms). No UI tests.
- **`site/`** — marketing site deployed via Netlify (`netlify.toml` publishes `site/`). Compare pages, screenshots, `llms.txt`, `openapi.yaml`.
- **`Casks/`** — Homebrew cask definition. Updated automatically by `release.sh`.
- **`tools/`** — Python helper scripts for localization. Paths centralized in `tools/_paths.py`; scripts run from any clone of the repo without further setup.
- **`docs/local-cli.md`** — how to build and use the `binky` CLI from `BinkyCore/`.

## Key patterns

- **Preferences**: `BinkyPreferences` (ObservableObject) is the single source of truth, shared via `@StateObject` at the app root and `.environmentObject()`.
- **Notifications**: Cross-component communication uses `NotificationCenter` with names defined in `Strings.swift` (e.g. `.binkyStartSort`, `.binkyShowMainWindow`, `.binkyOpenMacPreferences`).
- **Settings window**: Uses `Window` scene (not `Settings` scene) with `.windowToolbarStyle(.unified(showsTitle: true))` so the unified title bar matches the main window.
- **macOS version branching**: `View+AdaptiveGlass.swift` provides `adaptiveGlass()` and `adaptiveVisibleWindowToolbarBackground()` that use `#available(macOS 26, *)` / `#available(macOS 15, *)` checks. Use these instead of inline availability checks.
- **Liquid Glass**: On macOS 26+ use `.glassEffect()`; on macOS 14–25 fall back to `.ultraThinMaterial`. The `adaptiveGlass(in:)` extension handles this.

## Release process

`./release.sh <version>` handles the full flow: bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.pbxproj`, update site version tokens, build Release, create DMG + zip, update `Casks/binky.rb` (version + sha256), commit, tag, push, and publish GitHub release via `gh`.

Prerequisites: `create-dmg` (`brew install create-dmg`), `gh` (`brew install gh`). Working tree must be clean.

Use `--bump-only` for steps 1–2 only (version strings + site, no build/git/gh).

## Apple design language (macOS Settings–style UI)

- **Segmented controls** (`Picker` + `.pickerStyle(.segmented)`): Use for **2–5 mutually exclusive panes** in a single settings surface (e.g. Image / Video / PDF under Presets). This matches System Settings patterns and avoids long vertical scrolling for parallel option groups.
- **Settings window navigation**: Host preferences in a dedicated **`Window`** scene with **`windowToolbarStyle(.unified(showsTitle: true))`** (same pattern as Dinky — not the SwiftUI **`Settings`** scene, which splits the navigation chrome). Inside, use **`NavigationSplitView`** with a sidebar **`List`** (grouped sections: General, Sorting, Interface). The detail column uses **`NavigationStack`** with per-pane titles and optional back/forward history (see ``PreferencesView``).
- **Grouped `Form`**: Use section **headers** to name groups; use **footers** sparingly for secondary explanation (progressive disclosure). Prefer concise captions over long instructional blocks.
- **Accessibility**: If `.labelsHidden()` is used on a control for layout, set `.accessibilityLabel` (and related inputs when needed) so VoiceOver still describes the control.
- **Hierarchy**: Place the control that **changes scope** (segmented picker) **above** the content it affects, with a clear section header (e.g. "Media").
- **Cross-cutting settings**: If an option affects multiple panes (e.g. Smart quality and PDF/video tiers), keep it in a **dedicated section above** the segmented control so it stays visible when switching panes.

## App constraints

- See `CLAUDE.md` for bundle size and dependency rules.

## Localization

- User-facing strings use `String(localized:comment:)` with `Localizable.xcstrings` (12 locales). `InfoPlist.xcstrings` covers Info.plist strings.
- `Binky/Resources/` has per-locale `.lproj` directories for Help markdown.
- Python tools in `tools/` — all paths centralized in `tools/_paths.py` so the scripts run from any clone of the repo:
  - `fill_xcstrings_translations.py` — batch MT fill for missing xcstrings keys (Google Translate)
  - `fix_brand_in_xcstrings.py` — fix brand-name MT leaks (e.g. 丁基/Mignon→Binky)
  - `correct_zh_translations.py` — hand-curated zh-Hans/zh-Hant corrections (run after the above two)
  - `correct_ru_ja_translations.py` — hand-curated Russian/Japanese corrections; still contains some Dinky-era reference keys that no-op against Binky's catalog
  - `translate_help_md.py` — translate Help.md to all locales via Google Translate
