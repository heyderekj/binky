> **Archived (Dinky-era).** Deployment guidance for the sibling site dinkyfiles.com,
> not Binky. Retained for cross-reference if the family-site speed parity work is
> revisited.

# Dinky site parity — Binky↔Dinky tab speed

The Binky marketing site (`site/`) prefetches **`https://dinkyfiles.com/`** on every page that shows the shared **Binky family** tabs, and [`netlify.toml`](../netlify.toml) adds cache hints for HTML vs static assets.

**Apply the same shape on `dinkyfiles.com`** so hopping back feels as fast:

## 1. `<head>` link hints → Binky homepage

Immediately after loading the shared tab strip stylesheet (same position Binky uses), add:

```html
  <!-- Faster hop to sibling product site (dns + connection + idle document prefetch). -->
  <link rel="dns-prefetch" href="https://binkyfiles.com/" />
  <link rel="preconnect" href="https://binkyfiles.com/" crossorigin />
  <link rel="prefetch" href="https://binkyfiles.com/" as="document" />
```

Mirror every HTML file that exposes the cross-site tabs (homepage + hub + leaf pages).

## 2. HTTP cache parity

If Dinky hosts on Netlify, copy the header blocks added in [`netlify.toml`](../netlify.toml) (after your existing typed-file rules):

- `/` homepage: modest `Cache-Control` with **`stale-while-revalidate`**
- **`/compare/**`** (adjust path if compare lives elsewhere): HTML same pattern as Binky
- **`/*.css`**, **`/screenshots/*`**, **`/*.webp|png|svg`**: long-ish cache + **`stale-while-revalidate`**

If hosting is Cloudflare/GitHub Pages/other, translate the **same durations** into that platform’s config.

## 3. Quick check

Production headers update **after the next deploy**. Before deploy, baseline may show Netlify defaults e.g. `max-age=0,must-revalidate`.

Use DevTools Network or:

```bash
curl -sI https://binkyfiles.com/compare/ | grep -i cache-control
curl -sI https://binkyfiles.com/site-tabs.css | grep -i cache-control
curl -sI https://binkyfiles.com/screenshots/sorting.png | grep -i cache-control
curl -sI https://binkyfiles.com/ | grep -i cache-control
```

Do the analogous requests on **`dinkyfiles.com`** once merged.
