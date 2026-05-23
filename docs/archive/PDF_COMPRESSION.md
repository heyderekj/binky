> **Archived (Dinky-era).** Binky does not compress PDFs; this document describes the
> sister project [Dinky](https://dinkyfiles.com)'s pipeline. Kept here for historical
> reference and because `tools/pdf_fixtures/` still ships some leftover fixtures.

# PDF compression in Dinky

## Pipelines

- **Flatten (default for new installs)** — Each page is rasterized with PDFKit and re-encoded as JPEG (ImageIO). This is the path that most often produces a smaller file on scans, photos-in-PDF, and mixed documents. Tradeoff: no selectable text or live links. With **Smart quality** on, Dinky samples pages and picks a flatten tier; it can also enable **grayscale** automatically for PDFs that look like monochrome office scans when **Auto-grayscale monochrome scans** is enabled (preset), and bias tiers one step smaller for those documents.
- **Preserve text and links** — Dinky runs bundled **qpdf** (stream recompression, object streams, image optimization) when available, then falls back to a **PDFKit** rewrite. Output is only kept when it is **strictly smaller** than the source. Many exports from modern apps are already optimized; **no size gain is normal** for this mode.

When **Smart quality** is on and **Experimental preserve pass** is **Off**, preserve mode still uses a **short heuristic chain** of qpdf attempts (e.g. stronger JPEG recompression on image-heavy PDFs; optional structure stripping when text density is low). Manual **Experimental preserve pass** replaces that chain with a single explicit pass for predictable power-user behavior.

**Skip-if-savings-below (Settings)** applies to **images and video only**, not PDFs: any strictly smaller PDF output is kept so small but real wins (common on preserve) are not discarded.

## pdfcpu evaluation (developer / release QA)

The repo includes `tools/benchmark_pdf_optimizers.sh`, which compares **qpdf** (same flags as the app) and **`pdfcpu optimize`** on a folder of local PDFs. As of 2.4.2, **pdfcpu is not bundled** in the app: run the script on representative files before considering an optional second pass; overlap with qpdf is common on already-tight exports.

## Success criteria (product / QA)

| Mode | Expectation |
|------|-------------|
| Flatten | On a **typical camera scan or image-heavy PDF**, output should be smaller than the source with default or Smart Quality. Use fixture types in `tools/pdf_fixtures/README.md` for manual checks. |
| Preserve | Smaller output is **best-effort**. Zero-gain is acceptable when the PDF has little structural slack. |

## Metrics logging

In **Console.app**, select the Dinky process and enable **Debug** logs for the app’s subsystem. Filter for `pdf_metrics`.

- `outcome` — Every successful write from `compressPDF` (includes `savedPct`, `bailout` for flatten tiers). Preserve mode may include `preserveChain` (planned qpdf step ids) and `preserveWin` (the winning step id, or `pdfkit` when qpdf did not beat the source).
- `rejected` — Zero-gain after the full attempt chain (`reason` explains which). PDFs are not logged as rejected for sub-threshold savings; that path is image/video-only.

Use this for regression checks before changing DPI/JPEG tiers or Smart Quality heuristics.

## Ship / scope decision

If flatten routinely fails to shrink a representative set of real-world PDFs (see fixtures README), treat that as a release blocker for marketing PDF as “compression.” Options then: further flatten tuning, an additional optimizer, or de-emphasizing PDF in positioning.

Apple does not provide a public, quality-preserving PDF “optimizer” API; structure-preserving wins beyond qpdf typically require specialized tools or accepting flatten.
