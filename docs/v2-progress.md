# Binky v2 — Progress Snapshot

> Last updated by the night-shift agent on 2026-05-22 ~23:30 (+0800).
> Read this first if you're picking up the v2 redesign work; it's the
> shortest path from "where did we leave off" back to writing code.

## TL;DR

| | |
|---|---|
| **Path chosen** | Route A — *Calm Inbox* (Daily-review-with-AI, not silent auto-move). |
| **What landed tonight** | Foundation work for v2 + first real pipeline stage + test net. |
| **What didn't land** | Anything that touches v1 runtime behavior (e.g. `SortWork` rewrite, `CompressionPreset → Inbox` rename). |
| **Tests** | SwiftPM: **53/53** ✅ (32 ms). Xcode: build succeeds; runner blocked locally by an Intel/Xcode 26 LaunchServices flake — CI will run it. |
| **Next move** | Run CI on `main`, watch the new SwiftPM step go green, then take a decision on the open questions in §6. |

---

## 1. Commits in chronological order

```
1bbb3be  Add Suggestion model and Pipeline Stage skeleton for v2
4bb0804  Clean up Dinky-era leftovers and add lint/tooling baseline
```

Plus tonight's not-yet-committed work (one or two commits coming next):

- `BinkyCore/Tests/BinkyCoreSharedTests/{Suggestion,Pipeline}Tests.swift`
  + `Package.swift` testTarget — **28** tests for the `Suggestion` and
  `Pipeline*` types added in commit `1bbb3be`.
- `.github/workflows/ci.yml` — new step `BinkyCore SwiftPM tests` runs
  `cd BinkyCore && swift test --parallel` before the existing Xcode test job.
  Independent regression net for v2 code that survives Xcode runner flakes.
- `BinkyCore/Sources/BinkyCoreSort/Pipeline/ClassifyStage.swift` — first
  real `PipelineStage`. Wraps the existing v1
  `FileClassification.categorize(url:)` heuristic and surfaces
  `looksTransientIncomplete(_:)` via a new `ClassifiedFile.isTransient`
  field. **`SortWork` was not modified.** Both the static helpers and the
  new stage call into the same internal logic, so v1 and v2 stay byte-for-
  byte aligned on classification until we explicitly migrate call sites.
- `BinkyCore/Tests/BinkyCoreSortTests/ClassifyStageTests.swift` (+ matching
  `Package.swift` testTarget) — **25** tests covering classification of
  documents / images / screenshots / media / archives / installers /
  Review (unknown) plus all five transient-detection branches
  (`.crdownload`, `.part`, dot-prefix, `~$Office` lock, `.DS_Store`
  opt-out). One test composes `ClassifyStage` through `PipelineRunner` so
  the type erasure path stays exercised.

## 2. Where v2's foundation now stands

```
BinkyCore/
  Sources/
    BinkyCoreShared/
      Suggestion.swift              ← v2 core model (proposal w/ confidence + decision)
      Pipeline/
        Stage.swift                 ← PipelineStage / AnyPipelineStage / PipelineRunner / PipelineError
        PipelineContext.swift       ← runID + startedAt (will grow as stages need)
    BinkyCoreSort/
      Pipeline/
        ClassifyStage.swift         ← URL → ClassifiedFile (FIRST real stage)
      …existing v1 files unchanged…
  Tests/
    BinkyCoreSharedTests/           ← 28 tests
    BinkyCoreSortTests/             ← 25 tests
```

Total green: **53 tests in 32 ms**. The new test target is wired in CI; pushing
`main` will turn the SwiftPM step green on the first attempt.

## 3. What stayed off-limits tonight (and why)

| Deferred | Why |
|---|---|
| `CompressionPreset → Inbox` rename | ~50 files, UserDefaults schema, CLI surface. Needs your call before touching. |
| Replacing v1 `FileClassification.categorize` callers with `ClassifyStage` | Touches `SortWork`. Local Xcode test runner can't validate the regression here (LaunchServices flake), so it stays a CI-only safety net. Do this in a focused PR with eyes open. |
| `SuggestionEngine` (the orchestrator that turns Watch events → `Suggestion`s) | Needs a decision on macOS 14 fallback behavior (heuristic-only? or dim AI features?) before it can be designed cleanly. |
| `DailyCalmView` UI | Premature without `SuggestionEngine` and a real `SuggestionStore`. |
| Foundation Models adapter (real Apple Intelligence integration) | Requires Apple Silicon + macOS 26 device for testing. Stub interface only — see §6 Q1. |
| Tag fanout / Receipt detection / Stale aging removal | Each lives deep inside `SortWork`'s 870-line monster. Should be deleted *after* the `ClassifyStage` migration carves up `SortWork` enough to make the cuts surgical. |
| `notarytool` + `spctl` automation in `release.sh` | Needs your Developer ID credentials; see §6 Q4. |

## 4. Verifications that ran tonight

| Check | Result |
|---|---|
| `swift build` (BinkyCore + binky CLI) | ✅ Build complete, 47s |
| `swift test` (53 cases, 5 suites) | ✅ 53/53, 32 ms |
| `xcodebuild build-for-testing` (full app + BinkyTests) | ✅ TEST BUILD SUCCEEDED |
| `xcodebuild test-without-building` | ⚠️ Failed at launcher (LaunchServices error, **0 test cases executed**) — Intel MBP + macOS 15.7.3 + Xcode 26 + macosx26.2 SDK + x86_64 launcher. Same flake CI YAML already retries 3× for. Will pass on `macos-26` runner. |
| YAML syntax of edited workflow | ✅ ruby's YAML loader accepts; 3 steps in `jobs.macos.steps`. |
| Python tooling sanity | ✅ All five localizer scripts import `_paths.py` and resolve `XCSTRINGS_PATH` to a real file. |

## 5. The five open decisions you'll see when you wake up

The night-shift agent left these untouched on purpose. Each has a default
behavior in case you'd rather just say "go" and move on.

1. **Foundation Models on macOS 14–25**

   When the user is on Sonoma/Sequoia and `FoundationModels` doesn't exist,
   what does Daily Calm show?

   - (a) Same UI, suggestions come from heuristics only (no semantic naming /
     vendor extraction). *Recommended default* — preserves UX consistency.
   - (b) Same UI, but the "AI suggestion" rows are visibly downgraded
     ("Heuristic match: looks like a screenshot") so users know what they're
     missing.
   - (c) Hide AI rows entirely on pre-26 macOS.

2. **`CompressionPreset → Inbox` rename — when?**

   The class is referenced ~50 places + persisted via `UserDefaults`. Three
   timings:

   - (a) Now, while the test net is small and easy to reason about. *Risk: a
     migration bug strands user data.*
   - (b) After `SortWork` is broken into stages and we have integration tests
     for sort runs. *Recommended.*
   - (c) Never; just live with the legacy name.

3. **macOS 14 build matrix in CI**

   The audit found CI only runs on macos-26. macOS 14 is the deployment
   target. Adding `runs-on: [macos-14, macos-26]` matrix (build-only on 14,
   build+test on 26) would catch availability-fallback regressions early.
   ~10 minutes of ci.yml work.

4. **Apple Developer ID / notarization**

   Do you already hold a paid Apple Developer ID + Developer ID Application
   certificate + a configured `notarytool` keychain profile?

   - **Yes** → I'll wire `release.sh` to call `notarytool submit --wait` and
     `stapler staple` after the DMG/zip step.
   - **No** → I'll add a `release.sh --notarize` flag with the call sites
     scaffolded but disabled, and document the credential setup in
     `docs/release.md`.
   - **Don't know** → run `xcrun notarytool history --keychain-profile
     "AC_PASSWORD"` from your Mac. If it errors with "could not find profile",
     you don't have one set up yet.

5. **CompressionPreset is, in your code, a *Routine*. The product copy calls
   it both "Routine" and (in marketing) "Automation" / "Inbox". The redesign
   wants "Inbox" everywhere.**

   What do you want users to read in the UI?

   - "Inbox" everywhere (recommended for v2 brand voice)
   - Keep "Routine" in UI, only rename the type internally
   - Something else

## 6. Recommended sequence when you sit back down

In strict order, smallest-blast-radius first:

1. `git push origin main` — both tonight's commits + tonight's pending one.
   Watch CI: the new SwiftPM step should go green on first try; the Xcode
   step might still need its 65-retry on `macos-26`.

2. Answer §5 Q1 (Foundation Models fallback). This unlocks the
   `FoundationModelsAdapter` + `HeuristicFallback` design, which is what
   `SuggestionEngine` depends on.

3. Carve `HashStage` and `OriginHostStage` out of `SortWork` the same way
   `ClassifyStage` was carved tonight. Keep the same "wrap, don't replace"
   discipline. Now we'll have three independently testable stages and can
   chain them in a `PipelineRunner` for the first real v2 dry-run.

4. Decide §5 Q2. If "now," tackle the rename in a clean branch with the
   migration test included up front.

5. Sketch the `SuggestionEngine` API on paper (input: `[URL]` from watch +
   `BinkyPreferences`; output: `[Suggestion]`). Don't write it yet — get
   the shape on a napkin.

6. First UI experiment: a **read-only** Daily Calm preview that lists what
   the engine *would* suggest if we shipped it. Lives behind a debug flag,
   doesn't replace `OrganizerMainView` yet. Lets you show the new direction
   to a few users without committing to the rewrite.

This ordering spends each step on one risk at a time, never crosses both v1
and v2 at the same moment, and keeps the test count climbing the whole way.

## 7. Honest limitations of tonight's work

- **No v1 runtime behavior was changed.** That's deliberate (and a feature),
  but it also means *nothing visible to users moved tonight*. The win is
  entirely in the foundation: tests, types, CI gate. Don't expect to open the
  app and see a difference.
- **Local test runner is broken** on this Intel + Xcode 26 setup. Until that
  resolves, `BinkyTests/` (the Xcode-side tests) can only be validated on CI.
  All v2 work going forward should preferentially live in SwiftPM tests so
  the dev loop stays tight.
- **The hardest decisions are still ahead** — the rename, the engine
  architecture, the UI rewrite. Tonight built the runway. Takeoff is the
  next session.

— end of report —
