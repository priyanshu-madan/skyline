# Splash screen — design brief

Design the launch screen for **Skyline Travel Log**, an iOS app. Two images:
one light, one dark.

---

## What the app is

You scan a boarding pass or a booking confirmation. The flight is stored, and
its route is drawn as an arc on a 3D globe. The globe is the whole product —
it fills the screen, and everything else rides in a sheet over it.

---

## Where this image appears

**Not the very first frame.** iOS draws its own launch storyboard first; this
is the screen immediately after, held for roughly one second while the app
resolves sign-in and the globe boots. It is shown **twice** in a cold launch —
once during auth, once as an overlay until the globe is ready — so it must
read instantly and bear being seen twice in five seconds.

It renders full-bleed with `aspectRatio(contentMode: .fill)` and ignores safe
areas, which means **it will be cropped on most devices**. Keep everything that
matters inside the middle 70% vertically and 80% horizontally. Nothing critical
near an edge.

---

## What is wrong with the current one

A pale blue sky gradient, cartoon clouds, a white airliner, four sparkles, and
the wordmark "SkyLine" set in a rounded sans.

Three specific problems, so you don't reproduce them:

1. **It is the wrong typeface.** The app is monospaced top to bottom — Geist
   Mono, everywhere, no exceptions. A rounded sans on the launch screen is the
   first thing a user sees and it belongs to a different app.
2. **It is a themed illustration.** Sky-blue gradients and clouds were just
   removed from the app's light mode for exactly this reason: the product is
   paper-white and near-black, not a daytime sky.
3. **It is 762×1524, single resolution.** Soft on every modern iPhone.

---

## The visual language to draw from

The app already has a strong look. Use it rather than inventing one.

- **The globe.** A sphere whose landmasses are rendered as fields of small
  dots — a halftone dot-matrix, not solid shapes. Dark navy sphere in dark
  mode, near-white in light mode. A faint atmospheric halo at the limb.
- **Flight arcs.** Near-solid curved lines lifting off the sphere between two
  points, in the app's blue. They are the content — the one saturated thing on
  screen.
- **Airport labels.** Three-letter codes in monospace, set small and tight —
  `PHL`, `DEN`, `JFK`.
- **A starfield** behind the globe: three layers, many faint and few bright,
  drawn as small round points. White on the dark ground; grey on the light one.
- **Liquid Glass** chrome — translucent capsules — though the splash probably
  wants none of it.

---

## Tokens — use these exact values

### Dark

| Role | Hex |
|---|---|
| ground | `#0A0F1C` |
| surface | `#151D30` |
| ink | `#E9EDF7` |
| secondary ink | `#99A3BC` |
| accent / arcs | `#4DA3FF` |
| globe canvas | `#000011` |
| atmosphere | `#4DA3FF` at 40% |

### Light

| Role | Hex |
|---|---|
| ground | `#F7F8FC` |
| surface | `#FFFFFF` |
| ink | `#0E1626` |
| secondary ink | `#5A6480` |
| accent / arcs | `#0B63C5` |
| globe canvas | `#EEF2FA` |
| atmosphere | `#DCE2EF` |

The light ground is deliberately warm paper, not pure white. The dark ground is
deep navy matching the globe's night sky. **No sky blue. No gradients into
cyan.**

### Type

**Geist Mono**, and nothing else. Available at
[vercel.com/font](https://vercel.com/font), SIL OFL. If the wordmark is set in
type, it is set in this. Do not pair it with a display face.

---

## The brief

Make a launch screen that says *your flights, on a globe* in about one second,
without a paragraph.

Some directions worth exploring — you are not limited to these:

- **The globe, cropped.** A sphere entering from one edge, dot-matrix
  landmasses, a single blue arc lifting off it. Wordmark small and low. Closest
  to what the user is about to see, which makes the transition feel like the
  app opening rather than a slide changing.
- **One arc.** Just the curve between two points on a dark field, with two
  IATA codes. Abstract, quiet, and it is the app's actual output.
- **Type-led.** The wordmark large in Geist Mono, one arc or one dotted
  meridian as the only ornament.

## Rules

- **Two images**, light and dark. Design both properly — the dark one is not an
  inversion of the light one; check contrast in each.
- **1290 × 2796** each (iPhone 16 Pro Max native), full-bleed, no transparency,
  no rounded corners, no device frame.
- **No cartoon clouds, no sparkles, no lens flare, no stock aeroplane.**
- **No tagline, no "loading", no spinner, no version number.**
- The wordmark, if you use one, reads **SkyLine** — that is what appears under
  the icon. "Skyline Travel Log" is the App Store listing name and is too long
  for this screen.
- It will be seen twice in five seconds. Nothing that begs to be studied.
