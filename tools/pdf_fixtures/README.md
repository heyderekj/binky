# PDF regression fixtures (manual)

> **Archived workflow (Dinky-era).** Binky does not ship PDF compression; these
> fixtures and the companion `benchmark_pdf_optimizers.sh` are inherited from
> the sister project [Dinky](https://dinkyfiles.com). Retained because future
> Binky-era work on PDF handoff to Dinky may want them.

Dinky has no bundled XCTest target; use these **document types** with a **Debug** build and Console.app (`pdf_metrics` filter) to verify shrink.

## What to collect

Keep 3–5 local PDFs (do not commit copyrighted files to the repo):

1. **Scan / photo PDF** — Phone camera scan or exported pages with large embedded images. **Expect:** Flatten yields **smaller** file (`savedPct` > 0 in logs). Preserve may or may not shrink.
2. **Text-heavy export** — Pages from a word processor or Google Docs with little imagery. **Expect:** Flatten usually still shrinks somewhat; preserve often **flat or no gain**.
3. **Pre-optimized web PDF** — Small download from a site that already compressed. **Expect:** Either mode may show **no gain**; not necessarily a bug.
4. **Large slide deck export** — Many full-bleed images. **Expect:** Flatten should usually win; check `bailout=lastResort` or `ultra` in logs if normal tiers fail.

## How to run

1. Build Dinky (Debug).
2. Open **Console.app** → select process → enable **Debug** for Dinky’s subsystem.
3. Filter: `pdf_metrics`.
4. Compress each PDF with **default sidebar settings** (flatten + Smart Quality on).
5. Note `savedPct` on `outcome` lines. For failures, read `rejected` with `reason=zero_gain_no_smaller_output`.
6. For **preserve** mode regressions, `outcome` lines may include `preserveChain` and `preserveWin` (which qpdf step won, or `pdfkit` if only PDFKit beat the source).

## Comparing qpdf vs pdfcpu (optional)

To compare bundled **qpdf** behavior with **pdfcpu** on your own files (nothing is uploaded), install Homebrew’s `qpdf` and `pdfcpu` and run:

```bash
./tools/benchmark_pdf_optimizers.sh /path/to/your/pdfs
```

See `docs/archive/PDF_COMPRESSION.md` for how this relates to shipping features.

## Baseline interpretation

- **Flatten** with `savedPct` ≤ 0 on type (1) or (4) → investigate tiers / Smart Quality (see `docs/archive/PDF_COMPRESSION.md`).
- **Preserve** with no gain on types (2) or (3) → expected; confirm UI explains best-effort behavior.
