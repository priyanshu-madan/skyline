# SkyLine — design brief

Design the iOS app **SkyLine**. Everything below is extracted from the shipping
codebase, so treat token values, component names and screen states as facts
about a real app rather than suggestions.

---

## 1. What the product is

A log of **places you have been**, each carrying one of three verdicts:
**Worth it**, **Fine**, **Skip**.

The thesis is that Skip is not failure — *"you skipped four things in Kyoto so
nobody else has to"* is the most valuable line the app can produce. Three
verdicts beat a 0–10 score because a number cannot say "don't bother".

It is a **personal record that happens to be shareable**. Not a social network,
not a game, not a leaderboard. One person judging their own experience, so no
competitive or achievement framing anywhere — no streaks, badges, trophies, or
"you're in the top 10%".

Places are found automatically by clustering the user's **photo library** by GPS
and time, so the app can show someone a trip they took four years ago and ask
what they thought of it. The core loop is a **card deck**: one place per card,
one tap to judge, next card.

---

## 2. Non-negotiables

These are architectural facts. Design around them; do not design them away.

1. **A live 3D globe is the app's ground.** It is a WebGL globe in a web view,
   full-bleed, always behind everything. All UI rides in a **persistent bottom
   sheet** over it with detents at 80pt, 20%, 30%, 60% and full. The globe is
   always a dark object — like a photograph — and does **not** flip with the
   theme. Chrome placed directly on it must be **opaque**, never translucent:
   glass samples a different backdrop every frame and smears.

2. **The typeface is monospaced throughout** (SF Mono). Every label, number and
   paragraph. This is the app's identity — do not introduce a serif or a rounded
   display face. Consequence you must design for: monospace runs ~0.6em per
   character and **cannot reflow inside a word**, so long place names truncate.
   Check your longest string at 375pt width.

3. **Liquid Glass (iOS 26)** is the material for floating chrome. Three roles
   already exist: `chrome` (floating over the globe), `card` (content surfaces),
   `capsule` (pills and controls). There is an opaque fallback for Reduce
   Transparency.

4. **Both themes are first-class** and fully hand-specified — no system dynamic
   colours anywhere. Design every screen in light *and* dark.

5. **Verdict encoding always pairs colour with a distinct silhouette.** Never
   colour alone: that fails greyscale and colour-vision deficiency.

---

## 3. Design tokens — use these exact values

### Light

| Token | Hex | Role |
|---|---|---|
| background | `#F7F8FC` | page ground — warm paper, deliberately not pure white |
| surface | `#FFFFFF` | card fill |
| text | `#0E1626` | primary ink |
| textSecondary | `#5A6480` | meta lines (5.6:1) |
| border | `#DCE2EF` | hairlines, unrated rail |
| primary | `#0B63C5` | primary action, tint (5.9:1) |
| secondary | `#6D4AC7` | violet accent |
| accent | `#C2701A` | burnt orange |
| success / warning / error | `#17794A` / `#8A6410` / `#B3323C` | |
| onAccent | `#FFFFFF` | ink **on** a filled primary surface |
| noteSurface | `#FDF6E8` | ground for the user's own writing |
| glassFallback | `#F1F4FA` | Reduce Transparency stand-in |
| scrim | black @ 18% | veil between globe and chrome |

### Dark

| Token | Hex | Role |
|---|---|---|
| background | `#0A0F1C` | deep navy, matches the globe's night sky |
| surface | `#151D30` | card fill that genuinely lifts |
| text | `#E9EDF7` | primary ink |
| textSecondary | `#99A3BC` | meta lines (6.4:1) |
| border | `#27324B` | hairlines |
| primary | `#4DA3FF` | primary action (7.3:1) |
| secondary | `#A78BFA` | violet accent |
| accent | `#FFB454` | amber |
| success / warning / error | `#3DDC91` / `#F2B33D` / `#FF6B6B` | |
| onAccent | `#08101F` | ink on filled primary — **deliberately not white** |
| noteSurface | `#241D10` | warm dark |
| glassFallback | `#1B2438` | Reduce Transparency stand-in |
| scrim | black @ 35% | |

### Verdict colours — the most important triad in the app

| Verdict | Light ink | Dark ink | Light fill | Dark fill | Symbol |
|---|---|---|---|---|---|
| Worth it | `#00727F` teal | `#2FD1C4` | `#DCF0F2` | `#123B3C` | distinct silhouette |
| Fine | `#9A6400` bronze | `#F2B33D` | `#F6E9D2` | `#3D3018` | distinct silhouette |
| Skip | `#8E1B2E` crimson | `#FF7A6B` coral | `#F7DFE4` | `#431F1C` | distinct silhouette |

Unrated on the globe: `#8E8E93`, theme-independent.

`onAccent` exists because white on dark `primary` measured **2.62:1**. Never
assume white reads on an accent — use the token.

### Type scale

All monospaced, all sized against Dynamic Type text styles rather than fixed pt.

| Token | Style / weight | Lines | Use |
|---|---|---|---|
| titleLarge | largeTitle / bold | 2 | screen titles |
| title | title / bold | 2 | section titles, big numbers |
| headline | title3 / medium | 2 | empty-state titles |
| body | callout / regular | free | body copy |
| bodyBold | callout / medium | 1 | row names, primary buttons |
| bodySmall | subheadline / regular | free | secondary copy |
| caption / captionBold | caption | 1 | small labels |
| footnote | caption2 | 1 | smallest labels |
| placeName | title3 / semibold | 2 | poster card name |
| placeMeta | caption | 1 | date · locality · photo count |
| verdictLabel | caption / semibold | 1 | verdict labels |
| **claim** | title2 / semibold | **4** | one sentence at display size stating a result |

`claim` is special: every other display token carries a *name* and caps at 2
lines; this one carries a *sentence*. It is what makes a summary screenshot-worthy.

### Spacing & radius

Spacing `4 / 8 / 16 / 24 / 32 / 48`, plus `glassInset 12` so concentric corners
line up. Radius `4 / 6 / 8 / 12 / 16`, `card 22`, `sheet 40`, bottom bar `28`.
Hairlines are 0.5pt; selection rings 1.5pt.

---

## 4. Component vocabulary — reuse, do not reinvent

- **VerdictRail** — a 3pt capsule of verdict ink running the full height of a
  list row, with zero gap between rows, so a column of rows forms one continuous
  ribbon of colour. No reference app does this; it is scannable at arm's length
  before a word is read. **Protect it.**
- **VerdictPip** — 28pt disc in the verdict's opaque fill, trailing a row.
- **VerdictChip** — the tappable verdict, in three shapes: pill, tile (with a
  count, doubling as a filter tally), and **stamp** (64pt circle, thumb height,
  the deck's primary control).
- **VerdictDistributionBar** — the whole log as one 10pt capsule of butted
  segments. Doubles as the colour legend for every rail on screen.
- **PlaceCard** — one grammar, three shapes: `poster` (220pt photo, name over
  it), `row` (glass card), `listRow` (text-only, flush, rail + name + pip).
- **SkyLineGlassBar** — the floating bottom tab bar, 28pt radius, over the globe.
- **PhotoOverlay** — a deliberately **theme-independent** ink/scrim pair for text
  laid over arbitrary user photographs, because a photo's luminance is unknowable.

---

## 5. Screens to design

38 screens exist. Design them in these tiers.

### Tier 1 — the product (design these first, they are what SkyLine *is*)

1. **Globe shell** — full-bleed globe, bottom sheet at resting detent. At rest
   the user currently sees ~90% globe carrying zero information about their log;
   solve that.
2. **Place log** — the home. Summary card (place / country / year counts + the
   distribution bar), verdict filter, search, sectioned list with pinned country
   headers. Nine states including a "waiting on you" resume card for places a
   photo scan found but nobody has judged.
3. **Verdict deck** — the core loop. Three stacked cards, a photo, the place
   name, and three 64pt verdict stamps at thumb height. Swipe or tap. Card edge
   lights in the verdict's ink past a 28pt drag. One tap commits; nothing gates it.
4. **Deck summary** — must open with a *claim* at display scale, not a count.
   "You skipped 4 things in Kyoto so nobody else has to." Counts go below.
5. **Place detail** — hero photo, or a desaturated map when there is no photo
   (a place always has a location, so it always has a cover), visits list,
   notes, repeat-visit trajectory.
6. **Empty log** — canonical empty state, hand-rolled so it keeps the monospace.

### Tier 2 — first run

7. **Sign in** — Apple and Google, 120pt hero glyph, three feature rows, privacy
   footer. 5 states including a provider-unavailable variant.
8. **Onboarding** — 3 pages: premise, one practice verdict tap on a live card,
   then hand off to the photo scan. **The current copy tested badly — the user
   said "I didn't get what this app is doing for me." Rewrite it.**
9. **Photo permission primer** — before the system prompt; must earn the grant.
10. **Library scan progress** — "Looking through 12,431 photos", live tally of
    trips and places found, a way to stop and keep what's found.
11. **Scan outcome** — six distinct endings: places found, no photos, no
    locations, no trips, no places in trips, access denied. Each needs its own
    copy and its own way forward.
12. **iCloud warning** — sign-in worked but the device has no iCloud, so nothing
    will sync.

### Tier 3 — trips & flights

Trips list (Active / Upcoming / Past), trip detail with map and day timeline,
add trip, add/edit timeline entry, expanded map, region picker, trip place
detection, per-trip places section.

Flights list with upcoming/past filter, **boarding pass detail** (currently
skeuomorphic — perforations, notches, barcode), boarding-pass OCR confirmation,
add flight to trip, flights empty state.

### Tier 4 — account

Profile with lifetime totals, settings (theme + sign out), edit profile,
circular avatar cropper.

---

## 6. Deliver

For each screen: **light and dark**, at 393×852 (iPhone 15 Pro). Include the
empty, loading and error states listed — they are most of the app's surface area
and where it currently looks worst.

Annotate which tokens and components each screen uses, so the result maps onto
the existing system rather than requiring a rewrite.

---

## 7. Do not

- Do not add a serif or rounded display face. Monospace is the identity.
- Do not use a 0–10 score or a score ring. The three verdicts are the thesis.
- Do not add streaks, badges, trophies, levels or any competitive framing.
- Do not put glass chrome directly on the globe — opaque only.
- Do not encode a verdict by colour alone.
- Do not flatten the VerdictRail or the tile-shape-as-tally; both already beat
  the reference apps.
- Do not set text over a user photo without an opaque plinth behind it. A
  photograph's luminance is unknowable, so text over one is a bet — take the
  gradient to full opacity where the caption begins.
- Do not use a light Liquid Glass treatment. It works in Apple Maps because the
  map is pale and the ink dark; here the ground is a dark globe.
