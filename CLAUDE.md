# Binky — Agent Rules

## App Size (Non-negotiable)

Binky is a single native binary with no bundled helper tools. Keep it that way. Before adding **anything** — a framework, dependency, asset, font, or feature — mentally check its bundle size impact first.

**Rules:**
- Prefer Apple frameworks always: SwiftUI, Foundation, AppKit, UserNotifications, AVFoundation, etc. They're free — already in the OS, zero bundle cost.
- Never add an SPM or CocoaPods dependency without explicit approval from Derek AND a clear size justification.
- If a feature would meaningfully grow the binary (>100 KB), find a lighter native implementation or skip it.
- No Electron, no web views, no bundled runtimes, no embedded web engines. Ever.
- Assets (images, fonts) should be SVG/SF Symbols where possible. Raster assets must be justified.

**Current footprint reference:** about 22 MB installed (one universal arm64 + x86_64 binary). The old Dinky-era encoders were removed from the repo.

## Project Context

- macOS app, SwiftUI + AppKit; deployment target **macOS 14 Sonoma**; Liquid Glass (`.glassEffect()`) on **macOS 26 Tahoe** with `.ultraThinMaterial` fallback
- Built by Derek Castelli — full-time freelance web designer (Webflow/Figma) at heyderekj.com
- **v1 product:** Named **Automations** that calm any fussy folder (watch, classify, route, optional Finder tags, Review folder, history / undo moves). Downloads remains the default global inbox; Desktop and other sources are first-class.
- Legacy compression stack still present for backward compatibility paths; **UX is organizer-led**.
- GitHub: https://github.com/heyderekj/binky · Site: https://binkyfiles.com

## Brand Voice

**Core metaphor:** A binky is a pacifier — it soothes, quiets, and calms fussy things. Binky (the app) does the same for a chaotic Downloads folder. Lean into that: the inbox is the fussy baby, Binky is the thing that makes it stop screaming.

**Tone:** Dry, warm, one-liner delivery. Short sentences. Never corporate. Never precious. Rhymes and wordplay welcome if they land — if they don't, cut them.

**Vs. Dinky:** Dinky's voice is about smallness ("Dinky makes files smaller", "tiny", size puns). Binky's voice is about calm and order — soothing, routing, tidying. Same deadpan register; different metaphor family.

**Writing patterns that work:**

- Treat the inbox like a toddler throwing a tantrum: "Fussy inbox. Meet Binky." / "Files were screaming. Binky helped."
- Short imperative or declaration: "Give it to Binky." / "Sh. Binky's handling it."
- Noun → past-tense verb form: "Sorted. Routed. Binky'd."
- Pacifier-literal crossover: "The pacifier for your Downloads." / "Downloads acting up? Pop in a Binky."
- Calm-outcome framing: "Quiets the mess right down." / "Your inbox, quietly handled."

**Avoid:**

- Exclamation points (too chipper).
- Explaining the metaphor (trust the reader).
- Long sentences — if it doesn't fit on one line in a UI label, cut it.
- Generic productivity-app language ("Streamline your workflow", "Boost productivity", etc.).

## Releasing

- `./release.sh minor` (or `patch` / `major` / `1.6.0`) from an up-to-date `main`. It bumps the version, updates the site's version lines and `site/ask.json`, builds a universal (Apple Silicon + Intel) app, makes the DMG + zip, updates `Casks/binky.rb`, then commits, tags, pushes and publishes the GitHub release. `--bump-only` stops after the version and site edits.
- The site deploys from `main` (Cloudflare Pages), so copy for an unreleased change goes live as soon as it merges. Merge site copy with or after the release.
- The Homebrew cask is read straight from `main` of this repo (`brew tap heyderekj/binky https://github.com/heyderekj/binky`), so cask fixes reach users on merge, without a release.
- New UI strings: `xcodebuild -exportLocalizations -project Binky.xcodeproj -localizationPath /tmp/loc -exportLanguage en`, then `python3 tools/fill_xcstrings_translations.py` fills only the missing locales. `release.sh` warns about untranslated strings added since the last tag.
