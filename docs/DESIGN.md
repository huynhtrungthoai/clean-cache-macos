# Design rules

> Token definitions live in `Sources/DiskCleaner/Theme/`; this page records only **why** they are what they are.
> Read it before changing anything visual — every rule here cost a round of rework.
>
> The two that never bend: body text is never colored (only `palette.ink` / `inkSecondary` — color
> belongs to icon tiles, the ring chart, buttons and badges), and page headers never sit on a fully
> saturated block. The advanced tier is defined by *structural* differences (typeface, radius,
> elevation, motion), never by a different color scheme.

---

## 1. Two cross-skin rules

1. **Body text is never tinted.** Primary text uses only `palette.ink`, secondary text only `palette.inkSecondary` (each skin defines its own).
   Color appears only on icon tiles, the ring chart, badges, buttons and data highlights.
   Why: this is the standard discipline of tools like DaisyDisk / CleanMyMac — once body text starts changing color, the UI drops from "tool" to "poster".
2. **Page headers / banners never get a solid saturated fill.** Use a card plus stroke; keep color in small elements.
   A saturated header block pins the visual weight to the top edge, and nobody looks at the data below.

## 2. Skin lineup: 3 basic + 3 advanced

| Skin | Group | Structural identity (not a color identity) |
|---|---|---|
| Morning Fog `dawn` | Basic, default | System font + soft shadow + squircle, neutral paper + restrained blue, dark mode first-class |
| Graphite `graphite` | Basic | Same skeleton, dark |
| Mint `mint` | Basic | Rounded font + large radius + circular icon tiles, green |
| Midnight Gold `midnight` | Advanced | **Serif + square corners (radius 2–4) + no shadow + no motion** → restrained luxury |
| Aurora Glass `aurora` | Advanced | **Rounded font + radius 22 + real `.thinMaterial` + springy animation + glow backdrop** → extroverted flash |
| Ink Wash `inkwash` | Advanced | **Serif + paper fiber + square seal + still** → cultured and slow |

In the default build `tier` decides nothing — all six skins are available; it only becomes a grouping key when `Channel.showsPricing` is true.

## 3. Three skin design rules

1. **Differences live in the skeleton, not the palette.** A recolor-only skin has no reason to exist — so the three advanced skins
   differ from each other **and from the three basic ones** in typeface, radius, shadow/material and motion signature.
   Before adding a skin, ask: where is its skeleton different? No answer, no skin.
2. **The advanced group is set apart by character, not features.** Skins are a presentation layer; all six are functionally identical — the difference never lands on capability.
3. **Skin cards must render a real thumbnail.** Early cards were three color swatches and you couldn't tell skins apart; now each card renders
   a mini sidebar + ring chart + list rows + buttons in that skin. The Skins page is `AppearanceView`, with a try-on (`tryingID`):
   wear it first, one-tap revert from the top banner.

## 4. Architecture constraints

- `Theme` = pure data; `ThemeManager` singleton + three UserDefaults keys (selected skin / unlocked array / light-dark toggle);
  views get it via `@Environment(\.theme)`, injected with `.themed()`.
- **Don't** add `.id(skin.id)` to `ContentView` again to force a subtree rebuild — that reruns the full disk scan on every skin change.
- Views may reference only `theme.*` tokens: no hand-written color values, no assuming light mode.
  The ring was the one place this was never enforced; now it is: ring material numbers all live in `Theme/RingStyle.swift`
  (`RingStyle.shipped` = the version shipping today), drawing all lives in `Theme/RingLayers.swift`,
  and `SweepRing` keeps only state, events and accessibility. **A second material = one more set of numbers in `RingStyle` plus one case in `RingLook`**;
  the view side doesn't change a line. Which skin wears which material is set by the `"ring"` line in `skins.json`; user-supplied JSON uses the same field.
  Today all six built-in skins say `"crystal"`, so `shipped` is reachable only through the `DISKWISE_RING_STYLE=standard` switch.
  Why each number is what it is is recorded in its own field comment.
- The ring's three uncolored grays (measured but can't touch / never measured / free) take their color from the **skin** and are shared by both materials,
  so they live in the "ring ink" section of `Components.swift` (`SweepRing.blockedInk` etc.), not in `RingStyle`.
  The reason to move them was the **second user of the ring**: the sample ring on the first-run screen reads the same recipe instead of copying approximate colors.
- But **geometry stays out of materials and out of config**: which segment is drawn where and who owns which point is computed only by Core's `GaugeLayout`
  (`DiskCleanerCore/RingGeometry.swift`). User-supplied JSON may pick a shape by id and change the material,
  but may not define ranges — one range off by one, and the second click deletes the wrong folder.
- Light/dark: a skin carries its own `scheme` (nil = follow system); the app-level `forcedScheme` takes precedence over the skin.
- Skin availability has a single switch: `Channel.showsPricing` (compile-time `-DAPPSTORE`, see `CHANNEL=appstore` in `build.sh`).
  Off by default → all six skins available, no section headers and no `PaywallSheet`; when true the decision lives only in `ThemeManager.canUse`
  and `unlock`, **with zero view changes**.
- Each page has exactly **one** scroll container; list rows are self-drawn cards in a `LazyVStack`. macOS 13's `ScrollView` reports the content's full
  height as its ideal size; nesting two inflates the detail column to over a thousand points and pushes the whole UI out of the window.

## 5. Icon tiles and chart colors

- Sidebar/list icon tiles are **no longer the same across skins**: shape follows `tileShape` (squircle / circle / rounded), color follows
  `tileStrategy` — the three basic skins use `.spectrum` (`Theme.spectrumLight` / `spectrumDark`, two 10-color brand spectrums
  mapped one-to-one to sidebar entries, so you navigate by color), and the two restrained serif skins (Midnight Gold / Ink Wash) use `.duotone`
  (`palette.tint` alternating with `palette.ink`, so you navigate by shape and position).
  Why: **a screenful of rainbow destroys the calm** — Ink Wash is a light paper surface, not a dark skin, and still shouldn't get a rainbow,
  so the strategy follows character, not light/dark. Icon foreground: dark + spectrum uses `palette.paper`, everything else pure white.
- `chart[]` has positional meaning; **don't treat it as a random palette**:
  - `chart[0..3]`: the ring chart's top 4 segments and primary data highlights (saturated);
  - `chart[4]`: always the **yielding color** — the "other used" segment, secondary bars, any data that shouldn't draw attention.
    It is usually the largest segment of the ring gauge, so a loud color would muddy the whole chart; every skin's `chart[4]` is deliberately a low-saturation gray tone.
    Keep this convention when adding skins;
  - `chart[5]`: reserved for node_modules / Docker progress bars.

## 6. List row anatomy and arithmetic

Once the Overview screen was built, none of the other data pages looked like the same app: not a color problem but **two row anatomies coexisting** —
each page drew its own stroked white box, a single-tier number and a page-colored proportion bar, while Overview used one container + a divider line +
two-tier numbers + color only for what "can be acted on". So these eight rules were copied from Overview, and all ten pages follow them.
The first seven are typography and arithmetic; the eighth is interaction.

1. **One display-size number per block.** The largest type in a row is reserved for "what this row is worth".
   The Duplicates page used to put the group name, "2.4 GB each" and "14.1 GB reclaimable" at the same size, leaving the eye to find the main number.
2. **Number and unit on two tiers.** Number `numeric(size: 21, weight: .light)` (actionable) or 17 (view only),
   unit on its own tier: 11pt + `inkTertiary`. The reason is practical: the unit is secondary, and at 21pt next to the number it widens
   the column and "GB" steals the number's thunder. Implementation splits the `human()` string at its last space;
   the UI never reformats it.
3. **Rows aren't boxed; use a 1px divider.** `separator.opacity(0.7)`, 1pt tall, inset 8pt each side,
   drawn only on non-first rows. With a stroked white box per row, 27 rows are 27 cards and look like 27 unrelated things;
   a divider says "these rows are one table".
4. **Color only for what can be acted on.** Rows that can go to the Trash: `SweepRing.lamp` color + lamp-colored proportion bar + checkbox;
   rows that can't: `inkSecondary` number + gray bar, checkbox slot kept but invisible.
   Bars used to follow the page color (pink on Duplicates, orange on Docker), so color said "which page you're on" instead of "can this row be deleted" —
   the latter is the only axis this screen needs to separate at a glance; page identity belongs to badges and the header.
5. **Two-way hover highlighting doesn't go down to list pages.** Overview's 6 rows can do "hover a row lights the ring, hover the ring lights the row";
   on the Caches page's 27 items or the Big Files page's 61 files that would flicker. List pages keep only a row's own highlight.
6. **Size is compared by each row's fixed 232-wide proportion bar, not by a ledger strip that fills 100%.** Overview once drew a
   seven-segment color strip at the bottom as a ruler; it was removed on 2026-09-27: the strip had no labels, you couldn't tell which segment was which, and the same ledger
   was spelled out more clearly row by row in the six rows on the right. The ruler now lives on the row it describes (`RingLedgerRow`'s `fraction`),
   at the same width as on list pages — switching pages doesn't require relearning "how much one cell is worth".
7. **Printed numbers must add up.** A column of numbers uses `addableHumanColumn` (force the whole column into the total's unit +
   largest-remainder rounding); the header total uses `sumShown` (adds the strings on screen, not the bytes).
   A screenshot once showed "12.0 + 6.3 + 4.2 = 22.5" with 22.4 in the ring center: the byte addition was right; each item had been rounded on its own.
   That is the first thing users check, and two ledgers on one screen is the tool's fault. Tiny rows that would collapse to `0.0` in a unified column
   print as `< 0.1` — they do take space, just below the column's smallest tick; printing 0.0 tells the user the row doesn't exist.
8. **Two-step action stays on the hero card only.** "Tap once to arm, tap again to sweep" on the ring is choreography for the signature screen;
   list pages are multi-select already, and checkbox + system confirmation dialog is correct — don't add another layer.

Two arithmetic fixes follow from this rule; they are about "numbers don't match", not "doesn't look nice":

- **Nested entries must not be added twice.** Knowledge-base entries nest (`~/Library/Caches` and its child
  `Caches/Homebrew` are the same bytes), so select-all totals must `dropNested` first and sum the union, and the footer states how the total is counted.
- **Detail rows don't count toward the header total.** The summary section (the four `docker df` rows) is already a total, and the specific images under it are listed below;
  adding both reports the same bytes twice. The header sums only the summary; details are listed, not added.
- **Borrowed numbers must be converted to this page's ruler, and keep their own subject.** Docker's `13.04GB (54%)` is base-1024
  with the unit glued to the number; printed as-is it is a different convention from the decimal two-tier numbers on the same screen. `scanDocker` parses it to bytes first,
  and the UI prints it with `human(_:inRulerOf:)` as `14.0 GB`. Wording matters more: "reclaimable" in this tool means specifically
  "what we can move for you", and this page can't touch a single item, so the line reads "Docker Desktop can still free 14.0 GB (54%)" —
  otherwise the header says "this page has no delete button" while a row says "13 GB reclaimable", and the screen contradicts itself.

## 7. Copy tone

UI copy is part of the product, not a placeholder. Write in plain human language ("Where did the space go", "Which caches are safe to delete"); translations are rewritten
for each language rather than translated sentence by sentence (e.g. "Gone, but still here"). Two constraints:

- English uses American spelling throughout (recognize / color / summarize), no British mix.
- Counts go through `cnt()`, which looks up each language's singular/plural table. **Don't write the unit again in the template**,
  or you get "27 items items listed".
