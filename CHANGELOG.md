# Changelog

## Unreleased

### Added — macOS 27 and Apple Intelligence

- **Review toolbar badge** no longer clipped by Liquid Glass (system badge on macOS 26+). Settings back/forward share one glass capsule.
- **Menu bar panel** (macOS 27): the icon opens a glass panel with status, live progress, Review count and **Sort Now**. Earlier releases keep the menu.
- **“Looks like…” rules**: screenshot, photo, scanned page, ticket or pass. macOS 27 asks the on-device model what an image or PDF page shows; screenshot and photo use file metadata on older releases. Rules using these kinds can’t be read by older Binky builds; unknown kinds now decode as “Any content” going forward.
- **Review suggestions**: the triage sheet suggests a folder for each file (“Looks like a tax form → Finance/Taxes”) with one-click move, and offers a rule when the same site or file type keeps landing in the same folder.
- **Smart names for PDFs and photos** (opt-in): renames generic names like `IMG_2041` or `document (3)`; names you typed stay put.
- **Siri, Spotlight and Shortcuts**: Sort Now (per routine), Undo Last Sort (asks first), Check Review, Tidy Review.
- **Phrase → rule** uses guided generation instead of parsing model JSON.
- **Family look**: menu bar shows Binky’s pacifier (like Dinky’s and Slinky’s marks). The sidebar keeps Quick Sort and Routines, with the update card and New Routine / History / Settings pinned at the bottom like Slinky’s. Notices are glass toasts. Buttons, cards and text styles match Slinky’s helpers.

### Added — free-launch refresh

- **Quick Sort** mode: default toolbar segment for one-shot folder sweeps; segmented **Routines** mode keeps the power-user split view.
- **Routines** wording end-to-end (formerly “Automations”): settings tab, menu bar, shortcuts, site, and help; `UserDefaults` migrates `pendingAutomationTemplate` staging key to `pendingRoutineTemplate`.
- **Weekly digest share card** from session history (PNG copy/save) plus optional weekly notification; history sheet entry point.
- Main menu **View mode** commands (⌘1 / ⌘2) to jump between Quick Sort and Routines.
- Test target: renamed `AutomationsOverhaulTests` → `RoutinesOverhaulTests` for consistency.

### Planned — distribution & licensing (Binky 2.0)

- **Paid official builds (not a subscription):** one-time **Binky App License** (anchor **$10**, optional launch window at **$5**) with **one year of updates** included; **optional renewal** (~**$5/year**) extends update eligibility only — the app you have keeps working.
- **Binky + Dinky bundle:** planned one-time **$15** with one year of updates for both; **$9/year** bundle renewal draft. Internal spec: [`docs/future/BINKY_2.0_PAID_TRANSITION.md`](docs/future/BINKY_2.0_PAID_TRANSITION.md).
- **MIT source** remains; license pays for signed binaries + update channel + 2.0 feature work.
- **Site + docs:** FAQ + schema offers updated on [`site/index.html`](site/index.html); compare hub/leaves; [`README.md`](README.md), [`site/homepage.md`](site/homepage.md), [`site/llms.txt`](site/llms.txt). Help: [`Binky/Resources/Help.md`](Binky/Resources/Help.md), [`Binky/Resources/en.lproj/Help.md`](Binky/Resources/en.lproj/Help.md).

### Added — v2.0 Routines (formerly Automations)

- **Routines** replace Profiles: each routine has its own source folder, enable toggle, rules, tag defaults, DMG install destination, and tag fan-out priority list. Multiple routines can run in parallel; the watch pipeline dedupes shared sources.
- **Global inbox + protected tags**: default watched folder plus **Protected Finder tags** (e.g. DoNotMove) so tagged files are never touched.
- **Rule upgrades**: match by Finder tag; forced **output extension** and `{newExt}` rename token; actions **Extract archive then trash**, **Install app from disk image**, **Sort into subfolder by Finder tag**.
- **Templates** when adding a routine (Downloads, Desktop, DMG install, archive extract, tag fan-out, screenshot archive, notes to Markdown, blank) plus empty-state onboarding for **Calm my Desktop**.
- **Services**: `ArchiveExtractionService` (ditto/tar), `DMGInstallerService` (hdiutil + copy `.app`), tag read for predicates/skip list.
- **Tests**: `RoutinesOverhaulTests` (tag predicate, fan-out priority, rename/`{newExt}`, zip extract, shared watch root routing).

### Changed

- Settings tabs: **Routines** merges the old Watch + Profiles surface; sidebar links use routine terminology.

## 1.2.0 — 2026-05-02

### Added

- **Sort performance**: skip stability polling for obviously settled files; bounded parallel pipeline; cheaper ContentInspector cache keys; image downsample before Vision OCR; reuse duplicate digest for inspection; energy throttle fast path on small batches; watch debounce with 1.5s max burst window.
- **Routing rules**: per-rule actions (move, Trash, rename in place, zip to destination); dry-run preview matches the live sort path; optional **Re-sort watched inboxes when rules change**.
- **Watch**: **Also watch inside immediate subfolders (one level)** for sweep, preview, and `topLevelInboxFiles`.
- **Organizer**: inline sort preview under the inbox card; clearer CTAs on the glass activity pane (prominent **Tidy here…** / **Open Summary…**).

### Fixed

- **Contrast**: Review banner and activity rows no longer use washed-out bordered buttons on `.ultraThinMaterial`.

## 1.1.1 — 2026-05-01

### Fixed

- **Homebrew cask**: `homepage` URL uses a trailing slash so `brew style --cask` passes CI.
- **Xcode / Swift 6**: cleared concurrency and cast warnings in `ContentInspector`, `DownloadSortServices`, and `FileAgingService` (no lock work inside async continuations; Vision results without a useless conditional cast; aging timer avoids capturing prefs in a `@Sendable` closure).
- **SwiftUI**: aging-rule “See what would go” preview loads rows on appear instead of publishing prefs changes during view updates.

## 1.1.0 — 2026-05-01

### Added

- **Source-aware routing**: read `kMDItemWhereFroms` for download origins; rule `originDomains`; `{origin}` rename token; origin hints on Review moves in history and activity.
- **Duplicates**: `FileHashStore` (SHA-256 + perceptual image hash), duplicate skip / Duplicates folder / Trash handling in prefs and sort pipeline.
- **Smart sorting**: `ContentInspector` (Vision + PDFKit) for OCR; optional smart screenshot names; receipt / invoice heuristics with auto-route to Receipts; `{ocr}`, `{vendor}`, `{amount}` rename tokens.
- **File aging**: per-category rules in Settings, daily sweep via `FileAgingService`, **See what would go** dry-run sheet.
- **Daily digest**: rolling counters + scheduled notification via `SortDigestScheduler`.
- **Natural-language rules**: `RuleSynthesizer` (phrase heuristics; Foundation Models on macOS 26 when available); **Here’s what Binky heard** preview before applying a generated rule.
- **Finder tags on sort**: `FinderTagComposer` for category defaults, profile overrides, and rule-level tag policy.
- **Voice & clarity**: `VOICE.md` copy reference; `SortVoiceCopy` for session stats, outcome “why” lines, activity chips (already had, receipts filed, in review); **Why** column on sort preview; **Review** triage sheet (move, make a rule, trash); duplicate **memory** count and **Forget everything** in General settings.
- **Tests**: `WhereFromsTests`, `FinderTagCompositionTests`, expanded classification tests.

### Fixed

- **Xcode**: restored missing `PBXFileReference` / `PBXBuildFile` entries for `FolderWatcher.swift` and `WatchRegistry.swift` so watch-folder types compile.
- **Debug builds**: `SWIFT_COMPILATION_MODE = wholemodule` on the project Debug configuration to avoid incremental emit-module failures.
