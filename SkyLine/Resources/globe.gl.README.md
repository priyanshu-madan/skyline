# Vendored: globe.gl

`globe.gl.js` in this directory is a **byte-for-byte copy of an upstream
release**. Do not edit it, reformat it, or prepend anything to it — the whole
point of keeping it pristine is that the checksum below can be re-verified
against upstream at any time.

| | |
|---|---|
| Package | [`globe.gl`](https://github.com/vasturiano/globe.gl) |
| Version | **2.46.2** (pinned, not a floating tag) |
| Retrieved | 2026-08-31 |
| Source URL | `https://cdn.jsdelivr.net/npm/globe.gl@2.46.2/dist/globe.gl.min.js` |
| Bytes | 1,885,160 |
| SHA-256 | `2c3e445c04d121215910a89688b96091c8a72071c122a4f830081a39b636c94c` |
| Format | Minified UMD; **three.js r185 is bundled inside it** |
| Licence | MIT (globe.gl), MIT (three.js) |

Verify a copy with:

```sh
shasum -a 256 SkyLine/Resources/globe.gl.js
# 2c3e445c04d121215910a89688b96091c8a72071c122a4f830081a39b636c94c
```

## Why it is vendored

It used to be fetched at runtime from `https://cdn.jsdelivr.net/npm/globe.gl` —
an **unversioned** URL, injected into the globe `WKWebView` as a `<script src>`.
That was wrong twice over:

1. Unversioned. jsdelivr serves whatever is latest, so an upstream release could
   break every already-installed copy of the app with no build on our side.
2. The globe is the whole product. With no network on first launch — airplane
   mode, which is literally this app's use case — the user reached a black
   screen. App Review exercises offline behaviour (Guideline 2.1).

The globe now has **no network dependency at all**: the library, the country
outlines (`countries.geojson`), the starfield and the globe texture are all
bundled or generated in-process.

## How it is loaded

See `GlobeLibrary` in `SkyLine/Views/WebViewGlobeView.swift`. Short version: the
source is read from the bundle once per process into a `static let` and inlined
into a `<script>` in the page's `<head>`, ahead of the page's own bootstrap.

It is deliberately **not** a `WKUserScript` at `.atDocumentStart`. That was
measured, not assumed: at document start `document.head` is `null`, and the very
first statement of this file appends a `<style>` to
`document.head || document.getElementsByTagName('head')[0]`. Both are empty, so
the statement throws and the entire library fails to define `Globe` — silently.
The workaround (synthesising a `<head>` before injection) leaves the document
with two `<head>` elements. A `<script>` in document order has neither problem.

## Upgrading

1. Download the new pinned version, e.g.
   `curl -fsSL -o globe.gl.js https://cdn.jsdelivr.net/npm/globe.gl@X.Y.Z/dist/globe.gl.min.js`
2. Replace the file, and update the version, date, byte count and SHA-256 above.
3. Update `GlobeLibrary.version` in `WebViewGlobeView.swift` — it is logged at
   boot so a running build can be identified from the console.
4. Re-check the two assumptions this integration makes about the file:
   - it defines a global `Globe` factory (UMD), and
   - it contains no literal `</script` sequence. There is a guard in
     `GlobeLibrary.source` that escapes one if it ever appears, but confirm:
     `grep -c '</script' SkyLine/Resources/globe.gl.js` must print `0`.
5. Run the globe offline (`xcrun simctl status_bar <sim> override
   --dataNetwork none --wifiMode failed`) and confirm it still draws.
