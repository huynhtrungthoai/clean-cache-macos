import SwiftUI

// ── Ring material: one set of numbers, painted on the geometry built in step 0a ──
//
// This was moved **verbatim** out of `SweepRing` (`Theme/Components.swift`): only location and
// spelling moved, not a single pixel changed. The criterion is not "looks about the same" but the ring band of all six skins being byte-identical
// (the six band md5s in `app-baseline/ringstyle-md5.txt`; the whole-image md5s used in steps 0a/b are in the same file).
//
// **Don't use whole-image md5 as the gate** -- it once gave a false red: in the round that added the crystal material, three skins' whole-image md5 changed,
// and per-pixel localization found every change outside the ring (background gradient and the afterglow ring, 51-109 pixels, each off by 1 gray level).
// Relinking the pre-material-change source at a separate scratch path produced the same new values; two shots of the same binary
// could even change aurora's whole-image md5 on their own. Whole-image md5 is unstable against environment jitter, and when it goes red
// nobody looks at the band that actually matters. So the gate pins the `r 290-428` ring (`tools/ring-gate.py`).
//
// Why a separate set: `skins.json` already reskins the whole dial (palette, typeface, elevation, motion personality),
// but the ring's material was hard-coded numbers in view code -- to sell a "crystal ring" or "frosted ring" you had to edit the view,
// then manually confirm no other skin broke. With it collected into one set of numbers, adding a material = adding one set of numbers,
// and those 300 lines of view code no longer move with it.
//
// **Rule (same line as "geometry stays out of config" in `RingGeometry.swift`):**
// These numbers only govern "how it is drawn", not "which segment owns what". Segment -> pixels and hit point -> segment are still decided solely by Core's
// `GaugeLayout`; a material may change brightness, perceived thickness and color recipe, but never radius ownership --
// the cost of breaking that is a second click moving some other folder to the Trash.
//
// The three lines of numbers in the center are **not here**: that is typesetting, following `theme.metric` and the skin's font sizes,
// and stays in the view, closer to its "why this font size" notes.
//
// ── Pattern decision record: this stays at ladder **L1 (data)**, not a GoF pattern ──────────────────────
// Axis of change: **material** varies; **geometry and accounting** do not. Decider = config file / feature list, at construction time.
// Why not wrap it in a Strategy object: after #1 the second material (crystal ring) landed, there is still only one consumer, `RingFrame.style`,
// and `RingLayers` only reads fields -> one struct is enough; wrapping it just puts a shell around data.
// The real openness needed is "how many files does adding a material touch" -- **recount after the second material (`crystal`) and the JSON wiring landed,
// don't reuse unverified claims**:
//   - Only re-tuning existing knobs (brightness, how far it bleeds, which color is the lamp) = 1 file here (one case + one set of numbers +
//     one line in `RingLook.style`), 0 places in views; to put a skin in it, edit that one data line in `skins.json`.
//   - **Adding a new drawing technique** (the cross-section radial gradient didn't exist in the old code) = this file + one gate in
//     `RingLayers` (`crossStops` / `crossSection`, plus that one statement in `visualBand`).
//     `SweepRing` (state and events), Core's geometry, and the six skins' ring bands -- all three **had 0 changes** --
//     byte-identical ring bands proven by `ring-gate.py`.
// So stopping at L1 is right, but **keep the full ledger**: what we saved is "every material change touches core logic";
// we did not save "a new technique touches the drawing layer". When to move to L3: when a **third** material needing a new technique appears --
// that's the second and third instance paying for it; upgrading now is buying an elevator for a lobby only one family ever lived in.
// Revocation condition unchanged: if a material starts needing its own **dependencies** (reading the skin palette, computing derived values, switching recipe by state),
// that is an earlier L3 signal than "new technique" -- there are none yet.
// (The `RingLook` name table looks like a dependency but isn't: it only matches its own string, doesn't read `Theme` or compute derived values.
// What actually reads the skin is the two `isDark` branches in `RingLayers`, and those were in the drawing layer before the move.)

/// A small flat color with no gradient and not from the skin palette, plus its resting opacity.
///
/// Four numbers instead of `Color`: `Color` isn't comparable or JSON-serializable, and colors like "the near-white of the hot head"
/// are exactly part of the material recipe (the polar-night value rgba(255,240,214,.34) was copied from the prototype),
/// so they must live in the same set of numbers as the other material parameters.
struct RingInk: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    /// `scale` multiplies the resting opacity. The current code's `peak.opacity(0.40)` means exactly this:
    /// `Color.opacity` **multiplies**, so both results are byte-identical.
    func color(_ scale: Double = 1) -> Color {
        Color(red: red, green: green, blue: blue).opacity(opacity * scale)
    }
}

/// One stop of the around-ring afterglow (`.bloom`).
///
/// Positions are always "some band edge +/- N band widths", never "percent of the frame" -- the previous version hard-coded the peak at
/// `location: 0.855`, and when the band got thinner the whole glow fell into the hole (see the rOut/rIn note in `SweepRing`).
///
/// **There is one more stop beyond this list**: the drawing layer appends `.clear at 1`. After the last stop `RadialGradient`
/// extends the last color outward rather than fading, so without it the whole ring glows blue outward
/// (caught by the six-skin byte comparison; the cost is noted on `RingLayers.bloomGlow`).
/// So list only the lit stops here; don't add the tail yourself in config.
struct BloomStop: Equatable {
    enum Anchor: Equatable { case inner, outer }
    var anchor: Anchor
    /// Offset from the anchor in band widths; positive is outward.
    var offset: CGFloat
    /// Brightness level. 0 becomes `.clear`, not "lamp color x 0" -- the two are not equivalent in gradient interpolation,
    /// and this is exactly the stop the six-skin comparison caught.
    var opacity: Double
}

/// One stop on the bright ramp of the resting glint (`.glint`): fraction of the circle x peak-opacity multiplier.
struct GlintStop: Equatable {
    var location: Double
    var peakScale: Double
}

/// One stop on the ramp of the two scan-time lights (wide `.beam`, read head `#moSweep`):
/// fraction of the circle x peak-opacity multiplier.
struct SweepStop: Equatable {
    var location: Double
    var scale: Double
}

/// One stop of the well-floor plate (`.bore`): fraction outward from center x shadow-color opacity.
/// Like `BloomStop`, `at` is a **shape**, not a color table -- the center stop sits high (mockup `at 50% 32%`),
/// and the conversion is done by `RingLayers.borePlate`.
struct BoreStop: Equatable {
    var at: Double
    var opacity: Double
}

/// One stop of the rim (`.wall`) reflection: fraction of the circle x brightness multiplier vs. base color x how strongly this stop paints.
///
/// `ink` was added for **glass**: a full metal rim is shaped by "dark lobes pressed to dark gray", which on glass becomes
/// a gray iron ring around the outside (measured; exactly his "the outermost layer is still blackish gray"). A glass rim has only bright lobes --
/// the backlit stops take `ink` to 0, so that span gets no color and the card shows through.
struct WallStop: Equatable {
    var at: Double
    var bri: CGFloat
    var ink: Double = 1
}

/// One stop across the band's **cross-section** -- this is the shape of the crystal/glass material, not a color table.
///
/// `at` is "position across the band width": 0 = inner edge `rIn`, 1 = outer edge `rOut`; like `BloomStop`,
/// never "percent of the frame". Same reason: band width is computed from `bandRatio`; hard-coded points can't change ring size.
/// The drawing layer converts `at` to a real radius (`RingLayers.crossSection`); that conversion carries
/// the `.padding(outer + w/2)` pitfall -- **don't try to fill in "0.5 of the frame" here**.
///
/// All four multipliers apply to **the segment's own color** (via HSB, same path as `RingMaterial.shade`/`lit`):
/// the cross-section says "at which radii this glass rod is darkened, on which two edges it is lit, where it is too thick to see through",
/// and it must follow the skin's hue, otherwise only one of six skins is glass and the other five are plastic.
struct CrossStop: Equatable {
    /// Position across the band, 0 = inner edge, 1 = outer edge.
    var at: Double
    /// Saturation multiplier. ~0.6 on the edges is "bright to white"; 1.2 in the core is "darker and purer".
    var sat: Double
    /// Brightness multiplier relative to the segment color; `>1` brightens, `<1` darkens.
    var bri: Double
    /// Hue shift, in **full turns** (+/-0.033 ~ +/-12 deg). Measured: the two edges differ by 12 deg, one cool one warm,
    /// inner edge toward cyan is negative, outer edge toward purple is positive. 0 leaves hue alone -- light skins use 0 for now, see `crossLight`.
    var hue: Double = 0
    /// **Opacity** multiplier. Default 1 = unchanged.
    ///
    /// Why material must control opacity: on light skins the "measured but not movable" segments are 9% / 16% / 2.5% ink washes
    /// (`blocked` / `unmeasured` / `freeArc` in `OverviewView`); on such arcs **HSB multipliers do nothing** --
    /// halving the brightness of 9% ink only drops a few gray levels once composited on paper, because the ceiling is paper, not ink.
    /// Measured: the same cross-section yields a range of 51 on dark-skin neutral segments but only 12 on light skins.
    /// What actually varies on paper is **how thick the rod is**: long light path at the edges -> denser ink, short at the core -> thinner ink.
    /// So `ink` is that thickness: `> 1` makes the arc more opaque, `< 1` lets paper through.
    /// Opaque arcs (the movable segments) only change when `ink < 1`; `> 1` is clamped --
    /// so the same stop does the right thing on both arc kinds: gray arcs via density, colored arcs via brightness.
    var ink: Double = 1
}

/// One **color-mix** stop across the glass rod's cross-section. `CrossStop` is multipliers; this one is a color.
///
/// Switching to mixing isn't taste: the multiplier path **does nothing** on the gray segments. The mockup builds one
/// radialGradient per segment, and the ten stops are absolute colors
/// (`diskwise-v2.6-crystal.html:1765-1775`: `cool = mix(mix(top,'#C6F2FF',.52),'#fff',.18)`,
/// `warm = mix(top,'#FFD2A2',.34)`, `bot` pushed toward the `#0A0D12` family). Folding that into "HSB multipliers of the segment color"
/// is computable but not drawable -- dividing the mockup's own table stop by stop, the `cool` stop is x1.12 on reclaim,
/// x2.11 on sys, and **x3.99** on free, while `RingMaterial.cross` clamps brightness at 1.
/// So the cool highlight on gray arcs never reaches its place: measured mockup gray segment at r150 is 103 gray levels, the device only 58,
/// core/peak ratio 0.32 (mockup 0.20) -- that's where "gray segments are flat bands, only blue ones are glass rods" came from.
///
/// Mixing isn't clamped, and the anchors are absolute colors independent of the skin, so the same stop **paints differently** on bright and gray segments:
/// on bright ones it just warms the body a bit; on gray ones it pulls a cool highlight out of near-black. That is
/// why the mockup reads as "the whole dial is one rod".
struct TubeStop: Equatable {
    /// Position in the band, 0 = inner edge, 1 = outer edge. Same coordinates as `CrossStop.at`.
    var at: Double
    /// Mix from `a` to `b`; `t = 0` is all `a`, `t = 1` all `b`. Copied from how the mockup writes its ten stops.
    var a: TubeAnchor
    var b: TubeAnchor
    var t: Double
    /// Opacity multiplier for this stop, applied to the segment color's own alpha (1 after dark-skin precompositing).
    ///
    /// Only the outer-edge stops get values other than 1; it is the switch between "liquid glass" and "a painted ring":
    /// if the rod is still solid at the last stop, the ring has a hard silhouette; letting the last 1-2 pt through
    /// shows the card, track and rim from **inside** the glass, and the edge dissolves. Light skins' `CrossStop.ink` already
    /// meant this; dark skins had no such hook before (`tubeArcsOpaque` pinned alpha to 1).
    var ink: Double = 1
}

/// Anchors a `TubeStop` can reference. Four are intermediate colors derived from the segment color; `white` is pure white (only for the cool-edge tail).
enum TubeAnchor: Equatable {
    /// The segment's body. The two movable stops are first pressed back from lamp to body by `tubeBodyScale`.
    case body
    /// Rod core: segment color, same hue, darkened (`tubeCoreBrightnessScale` / `tubeCoreSaturationScale`).
    case core
    /// The cool highlight on the inner edge.
    case cool
    /// The warm highlight on the outer edge.
    case warm
    case white
}

/// All the ring's material numbers. **Defaults are the current shipped version**, not a pixel changed.
///
/// Split into six groups in painting order (bore -> afterglow -> track -> segment body -> hover -> two lights -> numbers on the arc).
/// Each group's opening comment records **why** the numbers are what they are -- the measured readings (mockup bore center (32,27,23),
/// outside ring (21,19,20), device shot (44,39,23)) live here, not in view code. Read that note before changing a number.
struct RingStyle {

    // ── 1. Lamp: accent color -> a color that glows ──
    //
    // Polar Night's accent #C9A227 has only 39 in blue; used directly as the lamp, light spilling onto gray arcs reads mustard, not gold.
    // So go through HSB touching only saturation and brightness, never hue: each of the six skins emits its own light, each with a blue channel.
    var lampSaturationScale: Double = 0.77
    var lampBrightnessScale: Double = 1.22
    var lampBrightnessAdd: Double = 0.06
    /// Hottest lamp stop = mockup `--lamp-hot` #FFF0D6: same hue, saturation halved again, brightness maxed.
    var lampHotSaturationScale: Double = 0.45

    // ── 2. Segment body: color only on movable arcs ──
    //
    // Movable segments get the "lamp core" gradient -- bright on top, sinking below, like a lamp standing on the ring.
    var hotHeadOpacity: Double = 0.92
    /// Lower half of the lamp-core gradient: same hue sinking deeper. Can't just mix in black -- that washes out saturation too,
    /// and the accent turns to mud on dark skins (the prototype's #F2B45C->#8A5F22 goes this way).
    var shadeSaturationScale: Double = 1.22
    var shadeBrightnessScale: Double = 0.57
    var shadeOpacity: Double = 0.55
    /// Highlight stop. Dark and light backgrounds can't share an algorithm: mixing toward white is fine on light; on dark it washes out saturation
    /// -- 58% white on Graphite turned the yellow arc beige, making it the brightest thing on screen.
    /// So on dark only raise brightness and slightly reduce saturation; hue untouched.
    var litDarkSaturationScale: Double = 0.72
    var litDarkBrightnessScale: Double = 1.55
    var litDarkBrightnessAdd: Double = 0.28
    var litLightBlendFraction: Double = 0.58

    // ── 3. The warm inner edge + each segment's own glow ──
    //
    /// Edge width is 42% of the band, hugging the inner edge (prototype R0->R0+26 / band 56). The previous version was only 22%
    /// and floated mid-band, reading as three labels detached from the ring rather than "this segment is lit".
    /// **This value only governs `shipped`**: the v2.6 mockup itself rejected 0.42 in round 2 (reaching r175 =
    /// a flat slab covering the rod's inner half); crystal uses its 0.20 hugging the inner edge, reason noted in `.crystal`.
    var reclaimEdgeWidthRatio: CGFloat = 0.42
    /// `outer` is "how far the arc's outer edge is inset from the ring's outer edge", so hugging the inner edge means inset band - edge width.
    /// The previous version used 1.06 x band, the edge fell into the hole and read as a yellow pill detached from the ring.
    var reclaimEdgeOuterRatio: CGFloat = 0.58
    /// The edge is one step brighter than the body, always the segment's hue. Not the accent: Morning Fog's accent is the ring's first segment color
    /// (0x2A62D6 vs 0x0072B2); edge and segment merge and read as "an extra arc nobody owns".
    var reclaimEdgeOpacity: Double = 0.85
    /// **Changed to copy the mockup layer's shape rather than retune blur radius again (2026-10-22)**.
    ///
    /// The blob he circled asking "what is this moving halo" was this layer blurred outside the ring: it used to draw
    /// a **full band width** arc then blur 0.40 x band = 24 pt; the source alone spanned 149->210 radially,
    /// and after blur the six segments' glow merged into **one shared ring of fog**, measured reaching r~258 before returning to the floor of 13,
    /// while there are only 24 pt between the ring's right edge and the ledger's left edge -- the fog sat right on the ledger rows' left edge. The fog itself is static,
    /// but the `.glint` reflection circling every 9 s rides over it, so it looks like a moving warm-gray blob.
    ///
    /// The mockup's matching layer is a different shape: from `diskwise-v2.6-crystal.html:1828`, each segment's halo is
    /// `r=179.55`, `stroke-width=BAND*0.60`, `blur(10px)`, `screen`, `rgba(LAMP,.17)`.
    /// Radial range 161.3->197.8; **even with 10 px blur it can't reach the outer edge 209.55** -- this light was
    /// always kept inside the band; the black outside wasn't achieved by shrinking blur.
    /// So all three are copied together: width 0.60 x band, outer inset 0.193 x band (=(209.55-197.82)/60.9),
    /// blur 10/60.9 = 0.164 x band. Blur going from 0.15 to 0.164 isn't blurrier; the source got smaller.
    var reclaimGlowWidthRatio: CGFloat = 0.60
    var reclaimGlowOuterRatio: CGFloat = 0.193
    var reclaimGlowBlurRatio: CGFloat = 0.164
    /// Light skins tone it down but **not to invisible**: if the fog bleeds too faintly on paper it reads as "unlit",
    /// too strong and it's a watercolor smear. The 0.7 dark-skin version stained the whole card a brown gradient,
    /// whereas in the mockup the area next to the gold arc is **black** (measured (12,13,17) = canvas).
    var reclaimGlowDark: Double = 0.45
    var reclaimGlowLight: Double = 0.34
    /// Steps along the arc when computing its vertical bounding box (720 steps per circle -> every 0.5 deg).
    /// SVG `linearGradient` lays out per arc's own bounding box by default; SwiftUI lays out over the whole frame,
    /// so without per-arc boxes the 6 o'clock segment gets the darkest stop (measured: that 6.3 GB arc was only (87,69,15),
    /// less visible than the neighboring gray arc (71,68,62); "color only on movable arcs" fails on the spot).
    var arcGradientSampleStepsPerTurn: Int = 720

    // ── 4. Track: the dial's shape is closed by it ──
    //
    /// 0.035 is the **gray floor**: the three gray levels above are stacked from it; raise it and the "barely drawn" free segment
    /// blurs into the "measured but not movable" one.
    var trackOpacityDark: Double = 0.035
    var trackOpacityLight: Double = 0.030
    /// The 1.65 pt cool line on the track's inner edge: gives **the part of the dial not covered by arcs** the glass rod's cut face too.
    ///
    /// Why a separate one (2026-10-23, sampled per radius per angle, `/tmp/xtrav.py` + `/tmp/xband.py`):
    /// the mockup's inner cool line is **one continuous circle** -- all 24 bearings lit at r150, darkest cell 98,
    /// brightest 139 (blue-gray, e.g. the 320 deg cell (96,115,128)). On the device this cut face **follows the segments**:
    /// bearings covered by a segment have it (r151 column 60-156), the gaps between segments don't -- worst cell at 0 deg:
    /// out of the well first a (3,4,5) hole, then a 42 dark edge of (35,42,55), then the body.
    /// No cut face in the gaps reads as the ring breaking there -- exactly the "few floating arcs" earlier batches kept hitting.
    /// The mockup's dial is one rod: the cut face doesn't vanish just because no arc is drawn in that cell.
    /// (The two images' segments aren't the same ledger, so this compares "is this cell covered by a segment",
    /// not same-angle readings as the same segment -- last round's "inner edge off by 98" was manufactured that way,
    /// dissected at the end of section 7b. The device line itself sits 1-2 px outside the mockup's; that's track radius, not fixed here.)
    ///
    /// Geometry copies the mockup `tube()` line `[(RI+0.7)/RO, cool], [(RI+2.6)/RO, ...]` (:1772):
    /// centerline 1.65 pt inside the band's inner edge, 2 pt wide, covering RI+0.65->RI+2.65.
    /// It hangs on the `track` layer (`RingLayers.swift:468`, tree entry at `Components.swift:1371`),
    /// and the track is drawn **before** all arcs -- so bearings with arcs are covered by the body; this shows only through gaps and free segments.
    /// It lights no segment's ledger, only restores the rod's own cut face.
    /// 0.80 is set as "give the full near-white cool of the mockup first, then let the well-mouth ink eat it":
    /// the mockup cool line computes to 197, measured 100-127; the ~70 levels between are eaten by `.bore`'s 40 px outer ink,
    /// and since this layer is under bore, the same deduction applies to it automatically.
    ///
    /// Light skins go to 0 (`0.34 -> 0.12 -> 0`). `bite = 0.027` places this 4 px line 1.65 pt inside
    /// the inner edge; bearings with arcs should cover it -- but light-skin segment edges are translucent, so it shows through,
    /// becoming a gray line all around the ring's inner edge: at y=872 across the left band, x=640 reads 194 vs 222 / 209 on either side.
    /// Removing it brings that spot back to 209, level with the band. On paper the cut face is handled by the white well-mouth edge
    /// (`boreHairlineLight`), no longer an ink line.
    ///
    /// Default 0: leave the shipped version (`shipped`) unchanged.
    var trackBevelDark: Double = 0
    var trackBevelLight: Double = 0
    var trackBevelBiteRatio: CGFloat = 0.027
    var trackBevelWidthRatio: CGFloat = 0.033
    /// Faint underlay beneath the hatching: pure dashes on light skins are a few blue stripes around holes, reading as a missed cell
    /// -- yet these bytes **still occupy the disk**; holes say the opposite. The underlay keeps the area; the hatching only says "moved elsewhere".
    var dashedUnderlayOpacity: Double = 0.26
    /// Dash pattern (6 on, 5 off) for the arc of "these bytes still occupy the disk, just moved elsewhere".
    /// It uses a dashed stroke, so these units are independent of line width -- changing it changes how that arc reads;
    /// before shipping images, check it against the ledger row "moved to Trash this time".
    var dashPattern: [CGFloat] = [6, 5]

    // ── 5. Hover and arming ──
    //
    /// `svg.pick .seg{opacity:.26}`: on hover the other segments drop to this level. If a segment dims but its glow doesn't,
    /// "stepping back" is only half drawn, so the glow is multiplied by the same number.
    var dimmedOpacity: Double = 0.26
    /// `.seg.on path{transform:scale(1.038)}`: the pointed segment pops out 3.8%.
    /// **The hit layer ignores this scale** (it uses the resting radius), otherwise the inner edge would jitter.
    var hoverPopScale: CGFloat = 1.038
    var armStrokeWidth: CGFloat = 2
    var armGlowOpacityPeak: Double = 0.85
    var armGlowOpacityRest: Double = 0.35
    var armGlowRadiusPeak: CGFloat = 9
    var armGlowRadiusRest: CGFloat = 3

    // ── 6. The breathing glow in the bore (`.halo`) ──
    //
    /// Lit radius = inner edge + band x this value. At ring outer diameter 412: lit radius 164,
    /// i.e. **biting 14 px into the band** -- the light connects with the band rather than being a separate blob in the hole.
    /// The previous version pulled the base light out to a thin line at the ring's outer edge, leaving the center an empty black.
    var haloBiteRatio: CGFloat = 0.25
    /// 0.15 isn't an aesthetic call, it's measured: mockup `A-sweep_0idle.png` bore center reads (32,27,23),
    /// canvas (12,13,17), so this glow raises the center only **+20 gray levels**; the previous 0.30 raised it +45
    /// (device bore center 65,56,29), staining the whole card brown so gold was no longer the only saturated color on screen.
    var haloInkOpacity: Double = 0.15
    var haloBlurRatio: CGFloat = 0.42
    /// Breathing range. On device `CALoopView` oscillates between the two ends (layer animation, main thread not involved);
    /// screenshots and bursts pin to some value within the range. `haloInkOpacity` is the baseline at the glow's brightest.
    /// 静皮收到一半：它要「静」，但样稿那圈光本来就是一起一伏的，
    /// 整层关掉等于把招牌画面少画一半——上一版就是这么把「有光晕」弄没的。
    var breathActive: ClosedRange<Double> = 0.34...0.9
    var breathStill: ClosedRange<Double> = 0.50...0.78
    /// 缩放只给会呼吸的皮肤：它比亮度更「活」，静皮留着就是穿帮。
    /// 往外扩那一档只作用在内孔那团光上，它本来就在环里，扩不出去。
    var haloBreathAmplitude: CGFloat = 0.02

    // ── 7. 绕着环带的一圈余晖（`.bloom`）──
    //
    /// **1.05 → 0.34（2026-10-22）→ 0.43 → 0.36 → 0.30（2026-10-24 三趟）**，
    /// 每一头都是量出来的，别再拿中间那版当结论。下面按趟记，别只读自己写的那一段。
    ///
    /// 收到 0.34 那次立的是「光漫出环外」这一条：真机 r 216 → 60.2、r 222 → 68.7、
    /// r 228 → 66.0，环**外面**比带子上还亮，那确实是错的（`.toplight`/`.glint` 两层在样稿里
    /// 的 mask 写了 `closest-side`，光本来就被钉在环自己的框里）。但那一趟只沿环心朝右
    /// ±35° 逐半径取均值，读到的样稿地板（r 204–234 是 13.8–15.3）**没有绕圈核过**，
    /// 于是把样稿另一处环外光一起砍掉了——这趟补上：
    ///
    /// 出处是 `.hairline` 那句 `box-shadow: ... 0 0 26px rgba(118,150,222,.13)`：描在 425 px
    /// 框外侧的一圈蓝，模糊 26 CSS px ÷ 带宽 60.9 = **0.427 个带宽**。绕整圈重量的读数
    /// （量完态、`u = r ÷ 环外沿`、每格取 360° 平均）：
    ///
    ///   u=1.02 样稿 (27,32,44) R−B −17.3 ／ 我们 (21,24,30) −9.5
    ///   u=1.10 样稿 (12,15,23) R−B −11.1 ／ 我们 (14,15,19) −4.9
    ///
    /// 两边一样暗，差的是**冷暖**：样稿那圈是冷的，我们收到的是一层死灰。玻璃要读成坐在
    /// 自己那摊光里，靠的正是这一圈，所以外沿那两档抬到 0.13/0.035（**当前表里是 0.13/0.030**，
    /// 末档这趟又收了一档，见下面第三趟）。带子里侧那两档原样
    /// 留着，洞和带身不跟着发雾。
    ///
    /// **reach 停在 0.36，没有按那句 26 px 铺到 0.43**：先按 0.43 建了一版，u=1.02 正好
    /// 落在样稿那一格（我们 32.2 对它 31.9），但往外全糊——u=1.04/1.06/1.08/1.10 读到
    /// 29.8/26.5/22.8/19.0，样稿是 19.7/17.9/16.4/14.9。也就是说样稿那圈冷光**只贴到环外
    /// 约 10 px 就没了**，比 `blur 26px` 该给的宽度窄得多：真在管这圈的是弧自己那句
    /// `drop-shadow(0 0 5px rgba(96,148,246,.38))`（`diskwise-v2.6-crystal.html:1871`），
    /// 它只在**有弧的角度**上亮（样稿 u=1.02 绕圈读 L 17.9@120°…58.0@90°），而 bloom 是
    /// 一整圈，只能贴边、不能摊宽。按角度分段的 bleed 是另一种画法，没在这儿加。
    ///
    /// **0.36 → 0.30（同日第三趟）**：0.36 那一版把 u=1.02 修准了（我们 33.3 对样稿 31.9、
    /// R−B −15.0 对 −17.3），代价全在往外那几格——u=1.04/1.06/1.08/1.10 读到
    /// 30.1/25.8/21.2/17.2，样稿 19.7/17.9/16.4/14.9，最多糊出 10 格。灭灯归因（`uprof.py
    /// --diff` 对 `DISKWISE_LIGHTS=bloom`）量到**环外 u≥1.02 只有 bloom 这一层在画**：摘掉它
    /// u=1.02/1.04/1.06/1.08/1.10 各掉 10.6/8.5/6.2/4.0/2.0，而 `halo` 摘掉后这几格一格没动
    /// （我们的 halo 钉在环自己的框里，样稿那圈 `inset:-52px` 是铺到框外的——那一处差异
    /// 记在这儿，没顺手改，改它等于给环外再摊一层光，和这趟的方向相反）。所以收窄只动
    /// bloom：末尾那档从 `+0.30` 挪到 `+0.16`、reach 收到 0.30，让这一圈**贴着环外沿断掉**。
    /// 带子里侧两档按 `rIn + band×offset` 定位，与 reach 无关，这趟一个字没动。
    var bloomReachDark: CGFloat = 0.30
    var bloomReachLight: CGFloat = 0.34
    /// 0.22（13 pt）会把收窄后的那一圈又糊开一圈，等于白收。
    var bloomBlurRatio: CGFloat = 0.10
    /// 外沿那两档 **0.06/0.02 → 0.13/0.035 → 0.13/0.030（2026-10-24 同一天三趟）**，钉的是样稿 `0 0 26px
    /// rgba(118,150,222,.13)` 那圈蓝的落点：u=1.02 处样稿对画布抬 +20（(27,32,44) 对
    /// (12,13,17)），我们这一档 0.06 只抬 +10.6。上面 reach 那段记的「样稿只抬 +9」
    /// 是**带灯那趟**在右边一格读的，绕整圈重量站不住（(21,19,20) 连色温都是暖的）。
    /// 内沿起亮点从 `rIn − 0.05×band` 挪到 `+0.05×band`：样稿这层在 rIn 以内是全透明的
    /// （`.bloom` 的 transparent 52% 换算过来正好是内沿），漏进洞里就是第二团雾——
    /// 内沿两档这趟不动。
    /// 最外那一档原来留在 `+0.30`：停靠点的半径是 `rOut + band×offset`，而末尾那道
    /// `.clear at 1` 落在 `rOut + band×reach`，所以 offset 一旦 ≥ reach 就越过它、停靠点失序，
    /// 整圈光的形状就说不清了。这趟 reach 收到 0.30，那一档跟着挪到 `+0.16`（= u 1.046）。
    var bloomStopsDark: [BloomStop] = [
        .init(anchor: .inner, offset: 0.05, opacity: 0),
        .init(anchor: .inner, offset: 0.64, opacity: 0.12),
        .init(anchor: .outer, offset: 0.10, opacity: 0.13),
        .init(anchor: .outer, offset: 0.16, opacity: 0.030),
    ]
    /// 浅皮这一圈整块往外挪：它要是压在带子上，等于给「最该安静」的空闲段上色
    /// （实测过，那段会染成全环第二显眼的颜色）。光只从环**外沿**洇出去，
    /// 读起来是落在纸上的那圈反光，洞和带子都干净。
    var bloomStopsLight: [BloomStop] = [
        .init(anchor: .outer, offset: -0.30, opacity: 0),
        .init(anchor: .outer, offset: 0.12, opacity: 0.20),
        .init(anchor: .outer, offset: 0.30, opacity: 0.06),
    ]

    // ── 7b. 盘自身的三块硬结构：孔底的井 `.bore`、外沿的金属边 `.wall`、最外那道 `.hairline` ──
    //
    // 样稿 `.ring` 的 DOM 是这个顺序（`diskwise-v2.6-crystal.html:1159-1170`）：
    // `ringdrop → wall → 弧 svg → bore → fx → toplight → ticks → glint → hairline`。
    // **这三块 App 原来一块都没有**，加它们那天的差距是量出来的，不是看着像。
    // 下面第一组是当时的读数（同尺度：石墨真机 vs 样稿 `?done`，沿环心每 15° 采一点，
    // 2× 帧里的灰阶）：
    //
    //   孔底：样稿 4–8，真机 19–25。样稿那个洞是一口**沉下去的井**（自己的底板 + 顶部
    //         一道内阴影），真机那个洞是「卡片背景上糊了一盏灯的雾」——`haloGlow` 画在洞里，
    //         而样稿的 `.halo` 虽然也在，却被上面那块不透明的 `.bore` 整个盖住，
    //         它真正剩下的活只有从弧的缝隙里透出来那一点。
    //   外沿 r 206/209：**在没光的几段上**样稿是 141/144、142/159，真机只有 63/62、43/39。
    //         样稿的盘边是一条**不随段落颜色灭掉**的硬沿（整圈对称的金属色），所以六段里
    //         最暗的那几段也还连在盘上；真机的边跟着每段自己走，空闲段就在环外断了口。
    //
    // 这一笔也正是削掉那团雾之后必须补的：雾原先顺带把外沿抬了一档（r 210 处 57），
    // 雾收掉之后外沿只剩 32。少了这道沿，环会从「一根玻璃棒」退回「几条浮着的弧」。
    //
    // **这三块落地之后重量的同一组数**（2026-10-23，真机 `g11-full` vs 样稿 `?done`，
    // 全圈 36 个方位取平均，`/tmp/xrad.py`；r<149 是洞里、r>211 是环外，都没有弧，
    // 所以这组数不靠「哪段算亮弧」那种判断——那种自动分档一换材质就整体漂移）：
    //
    //   孔底  r100 / r120 / r140 / r145：样稿 8.3 / 6.9 / 4.9 / 4.0，真机 5.3 / 4.4 / 2.8 / 3.4。
    //         井比样稿还沉 1–3 档，不再是一团雾。
    //   环外  r212 / r220 / r240 / r260：样稿 49 / 20 / 15 / 14，真机 47 / 21 / 13 / 13。
    //         他圈出来问的那团会移动的雾，到这一组数才算真关掉：光在 r212 之后一模一样地衰减。
    //
    // 外沿那圈按「段上没上色」分开读（`/tmp/xwin.py`，窗口由 `/tmp/xhue.py` 的彩度图指出来，
    // 不让脚本猜），r206 样稿 上色 142 / 中性 80 / 空闲 55，真机 149 / 95 / 54：
    // 沿不随段色灭这件事已经成立，中性段还比样稿亮 15 档（过了，但不刺眼，先留着）。
    // 同一套读法内沿那一圈**先得出过一个「差 98」，据此补了一层，后来量出是假的**，
    // 那两条错法逐半径重打之后拆在那里（见下面 `innerBand` 那段）——外沿这一组数没受影响，
    // 因为样稿的 `.wall` 本来就是一整圈，跟段没关系。
    //
    // 颜色一律从皮肤拿（`palette.ink` 走 `RingMaterial` 的倍率），不写死样稿那几个十六进制——
    // 样稿自己只有深底一套，而 App 有六套皮、两档 tone。
    var boreRadiusRatio: CGFloat = 1.0
    /// 从「靠顶那一点」往外铺的三档**绝对不透明度**（见 `RingMaterial.bore` 为什么丢掉
    /// 皮肤自带的 alpha）：样稿是 `radial-gradient(circle at 50% 32%, #0A0C10, #07080B 46%,
    /// #040507)`，灰阶 11.8 → 7.9 → 5.4，中心偏上、外圈更沉。
    /// 这三档按「压在 17 灰阶的孔底上落到几」倒推，倒推那版的读数已经不作数了：
    /// 2026-10-23 全圈平均重量，这组数落在 r100/r120/r140/r145 = 5.3 / 4.4 / 2.8 / 3.4，
    /// 对着样稿同尺度 8.3 / 6.9 / 4.9 / 4.0（数与量法见上面 7b 那段）。
    /// 浅皮这一档样稿没有对照——纸上没有「近黑的井」这回事，只能给「比卡面沉一档」。
    /// 数值先按卡面 245 落到 226/218/206 定，成不成看图判，不冒充样稿读数。
    var boreStopsDark: [BoreStop] = [
        .init(at: 0, opacity: 0.45),
        .init(at: 0.46, opacity: 0.62),
        .init(at: 1, opacity: 0.78),
    ]
    var boreStopsLight: [BoreStop] = [
        .init(at: 0, opacity: 0.07),
        .init(at: 0.46, opacity: 0.11),
        .init(at: 1, opacity: 0.16),
    ]
    /// 顶部那道内阴影（样稿 `inset 0 3px 26px rgba(0,0,0,.96)`）：井口上沿被盘自己遮住，
    /// 所以洞的顶部比底部更沉。SwiftUI 没有 inset shadow，用「一圈墨描在洞里、裁在井底、
    /// 往上抬 3 px」——偏移用的就是样稿那句 3 px，判据也是照它定的：洞顶要比洞底读得出更低。
    /// 注意这跟 2026-10-23 删掉的环上那层「竖向顶光」不是一回事，别再拿它当同类：那层是拿
    /// 渐变铺整条带子、轴向还没量对；这一层是一圈等高描边靠**位移**做出上沉，样稿确有这一笔。
    ///
    /// 0.55 **不是**样稿那句 0.96，差在画法上：CSS 那道内阴影从井口往里是连续衰减的，
    /// 而这里是一圈 26 pt 的等高描边再糊开半个宽度，顶部整条都是峰值。照抄 0.96
    /// 会把洞的上半直接涂成纯黑，「一口井」变成「半个洞被盖了黑纸」。
    /// 两档都是绝对不透明度（同 `boreStops*`，不吃 `shadow` 自带的 alpha）。
    var boreInsetDark: Double = 0.55
    /// 浅皮从 0.16 收到 0.06。0.16 在纸上不是「井口沉下去一点」，是一道实打实的灰箍：
    /// 摘掉整个井口层，环内沿 r≈299 抬 49 阶，是全环最大的一处压暗；而用户看到的
    /// 「中间那两道细黑线」正是它和下面 1 px 墨沿叠出来的。0.06 只留上沿比下沿沉的那口气。
    var boreInsetLight: Double = 0.06
    /// 宽度 26 px / 带宽 60.9，糊开半径同它自己的一半。
    var boreInsetWidthRatio: CGFloat = 0.427
    var boreInsetOffsetRatio: CGFloat = 0.049      // 3 px / 60.9
    /// 井口那道 1 px 细沿（样稿 `inset 0 0 0 1px rgba(255,255,255,.035)`）：
    /// 深皮是井壁上反出来的一线光，取 `palette.ink`（近白，0.035）。
    /// **浅皮反过来**：纸上的深墨沿就是那条黑线，取 `Color.white` 当井口的玻璃反光——
    /// 同一个数在这条路径上说的是白沿的不透明度，不是墨。0.55 在浅灰井底上刚好立起来。
    var boreHairlineDark: Double = 0.035
    var boreHairlineLight: Double = 0.55
    /// 井口**外**那一圈 1 px 冷线（样稿 `.bore` 第三条 box-shadow：`0 0 0 1px
    /// rgba(152,182,238,.085)`，外发光、画在井壁上）。它把「洞的口」和「带子的内侧」
    /// 分出两道边：只有底板的话井壁是一整块糊下去的，读者看不出井口切在哪儿。
    /// 深皮 0.085 是样稿那个数（去掉色相、从 `palette.tint` 拿）；浅皮这一档样稿没有
    /// ——纸上的井口该是压深还是反亮，得看图定，先按「纸上要给一道边」给 0.14，
    /// 这个数在截图对照里判，不当样稿读数用。
    var boreRimDark: Double = 0.085
    var boreRimLight: Double = 0.14
    /// 井口**往外**压的一圈墨（样稿 `.bore` 最后那条 box-shadow：`0 0 40px rgba(0,0,0,.8)`）。
    ///
    /// 这一条是 2026-10-23 补的，之前 App 只做了井口那 1 px 冷线，四条阴影里外圈这两条
    /// 一条没画。它不是装饰：井口的墨决定了那道冷亮线读成「贴着黑的一根细边」还是
    /// 「一块糊到带心的白板」——没有它，弧的内半支是一整块饱和的亮面。
    ///
    /// **它该有多重、该铺多宽，是量出来的**（`/tmp/xline.py`：三帧中位图、按色相分档、
    /// 位置用 u = (r−内沿)/带宽，两边各自 1 pt 的尺度差不进账）。把井撤掉与不撤各拍一张，
    /// 同一条亮线两次读数之比就是这圈墨在井口吃掉的比例：
    ///
    /// | 亮线（u≈1%） | 样稿 | 真机（0.657 那一版） |
    /// |---|---|---|
    /// | 动得了段 | 196 → 134，吃掉 .32 | 204 → 174，吃掉 .15 |
    /// | 灰段 | 167 → 116，吃掉 .31 | 135 → 123，吃掉 .09 |
    /// | 空轨（没弧那圈） | 157 → 111，吃掉 .29 | 117 → 106，吃掉 .09 |
    ///
    /// 三档一致地说：样稿在井口压掉三成，真机只压掉一成。而且样稿那道坡到 u≈25% 已经花完，
    /// 真机到那里还剩 −6——**同一份墨摊到了两倍宽**，所以峰值只到人家一半。
    ///
    /// 宽度与深度都是**照样稿成品图拟出来的**，不是照 CSS 那句折算的（`/tmp/xink2.py`：
    /// 拿样稿 `done.png` 与把 `.bore` 藏掉的 `nobore.png` 逐半径算 α(x) = 1 − 有井/无井）。
    /// 蓝段那一列可信（底下 42–191 灰阶，采样噪声进不了账），它给的坡是
    /// .30 / .29 / .24 / .21 / .18 / .13 / .11 / .074 / .036 / .024 @ x = 0/2/4/6/8/10/12/16/20/22：
    /// 单支高斯拟下来 **σ ≈ 14 pt**，比那句 `blur 40px` 折算的两倍口径窄。
    /// 取 **0.23**（= 14 / 60.5 带宽）。为什么不是 0.33：σ=20 那一版复测（g20）井口只压到
    /// .18 而 x=22 还留着 .05，是「两头都不对」——坡太宽、峰太平，跟样稿那条正好相反。
    ///
    /// 墨的 α 仍是样稿那句 `.80`，但**必须走 `RingMaterial.bore` 当绝对不透明度用**：
    /// `palette.shadow` 自己带着皮肤的透明度（graphite .5、inkwash 0），拿 `.opacity()` 乘
    /// 上去就只剩一半，这就是 g17–g20 三版井口压不动的真正原因。
    ///
    /// 浅皮这一档样稿没有对照（纸上没有近黑的井）。0.10 实拍下来是井口外一道灰箍，
    /// 和井里的内阴影一起构成「黑线」；收到 0.05，只留井口压下去的那点深度。
    ///
    /// 默认两档都给 0：这层是新画的，不该顺手改到线上那一版（`shipped`）头上。
    /// 数写在 `crystal` 里，别的皮要接走同一套读法，由皮肤 JSON 自己点名。
    var boreOuterGlowDark: Double = 0
    var boreOuterGlowLight: Double = 0
    var boreOuterGlowRatio: CGFloat = 0.23
    /// 井口往外的第三圈：**蓝**发光（样稿 `.bore` 第四条 box-shadow
    /// `0 0 20px rgba(112,152,232,.17)`，2026-10-23 补）。
    ///
    /// 它和上面那圈黑墨不是一件事：黑墨把井口压沉，这一线把「洞的口」在暗背景上描出来。
    /// 落在亮线那一带只有 +4 上下（那里本来就亮，source-over 的着色没多少余地——样稿那条
    /// 也是普通投影合成，不是 screen），落在轨道外的暗底上才是看得见的 +20 一圈。
    /// 所以这一条按「补齐图层」搬，不冒充大缺口。
    /// σ 折算同 `boreOuterGlowRatio`：CSS 那句 20 px 是两倍 σ → 10 / 60.9 = 0.164。
    /// 颜色借皮肤主色的**色相**（同 `boreRim` 那两档的走法），样稿那支是 `112,152,232`。
    var boreMouthGlowDark: Double = 0
    var boreMouthGlowLight: Double = 0
    var boreMouthGlowRatio: CGFloat = 0.164

    // **试过、量出来是假缺口，已经删掉**（2026-10-23）。留着这段是为了别再踩一次。
    //
    // 当时按「内沿那三档对照」（上了色的段 125/130、中性灰的段 106/49、空闲那段 109/11，
    // 样稿/真机）补了一根「每段都画」的结构亮带（`innerBand*`，几何照 EDGE_R/EDGE_W）。
    // 删它的理由有两条，都是量出来的：
    //
    // 1. **样稿没有这一层。** `edge`、`halo`、`core` 三块整个圈在 `diskwise-v2.6-crystal.html:1802`
    //    那句 `if (s.reclaim > 0)` 里面，`edge` 的弧长还是 `eLen = D*reclaim/value`（:1805）。
    //    也就是说 `edge` 就是真机 `reclaimEdge` 那层——同一根心线（EDGE_R=155.2、宽 0.20band
    //    = 真机 `reclaimEdgeOuterRatio` 0.80 / `…WidthRatio` 0.20），同一条「铺多长才是账」。
    //    缺的不是层，是表读错了。
    // 2. **那 98 档是采样错位。** 逐半径打点（`/tmp/xband.py`，24 个方位 × r150/152/155/158/161）
    //    显示样稿那条内沿亮线在 **r150**，整圈 106–139；真机同一条线落在 **r152**，
    //    而 r150 那一格在洞的边上（读到 3–5）。两列各取一个半径，中间差 2 px 就凭空造出
    //    「差 98」。同一条线自己比：样稿 r150 ≈ 113、真机 r152 ≈ 96，差的是一档 alpha，不是缺层。
    //    另一半错在拿两张图**同角度的段**对比：样稿 60°/105° 那两段 `reclaim>0`（亮带 126–151），
    //    真机同角度是没有沿的段身（39–60）。拿真机带沿的那几段（135–165°）比样稿带沿的段，
    //    是 148–156 对 92–151——真机本来就在样稿之上。
    //
    // 留着这层的代价当场看见：加完之后整圈 152–161 从「暗金属带身」（样稿 56–83）
    // 抬成 101–162，就是样稿 :1806-1810 自己否过的那个形状——「拿一块不透明浅蓝平板
    // 盖住玻璃棒的内半支，段身渐变再准也读作刷了漆的板」。

    // ── 7c. 扫描期那圈刻度（样稿 `.ticks`）──
    //
    // 样稿 `diskwise-v2.6-crystal.html:2103-2112` 造 180 根刻度，每 2° 一根：外端在
    // `r=207.5`（环外沿 210 往里 2.5），往里到 203.5；每逢 15° 那一根长到 199、
    // 线宽 1 而非 0.7、亮一档（`.32` 而非 `.13`）。`:2887` 在「正在量」那一刻
    // `classList.add('on')`，`:2919` 量完当场撤——它只活在那几秒。
    //
    // App 原来扫描期只有 `mo-wire` 那圈一次性描边（第 3 批 #8）。那笔说的是「轮廓先来、
    // 实体后到」，并**没有**说「这是一台仪器正在把量程走一遍」；读者在扫描那几秒看到的是
    // 一张没画完的图。这圈刻度才是那个「正在量」的身份，而且它和 `Sound.tick` 那声咔哒
    // 同时到、同时走。
    //
    // 换算都按样稿自己的带宽 60.9：外端内缩 2.5，短针长 4.0，长针长 8.5。
    /// 深皮照抄那两档绝对不透明度；纸上没有「浅墨在亮底上」这回事，
    /// 所以浅皮换成压暗的 `ink`、由 0.20/0.44 给「比卡面沉一档」，**不冒充样稿读数**。
    var tickOuterRatio: CGFloat = 0.041
    var tickLengthRatio: CGFloat = 0.0657
    var tickMajorLengthRatio: CGFloat = 0.1396
    var tickWidth: CGFloat = 0.7
    var tickMajorWidth: CGFloat = 1
    var tickOpacityDark: Double = 0
    var tickOpacityLight: Double = 0
    var tickMajorOpacityDark: Double = 0
    var tickMajorOpacityLight: Double = 0

    /// 金属沿的宽：样稿 `.wall` 是 424 的框只留最外 6 px（`mask: transparent calc(100%−6px)`），
    /// 法向占 r 206→212，**跨过**外沿。6 / 60.9。
    var wallWidthRatio: CGFloat = 0.0985
    /// 浅皮上这道沿只留一半宽。样稿的 6 px 金属沿立在暗底上，是「外圈被灯照到」的一道光；
    /// 纸上同一宽度铺出来是一条 13 px 的灰带：实测环外 413–419（2×）整段 198，
    /// 底 224、纸 235——不是收边，是环里横着的一根深灰线。收到 0.042 个带宽 ≈ 1.8 pt。
    var wallWidthRatioLight: CGFloat = 0.042
    /// 弧的**外沿**相对环外沿的位置，负数=探出环外。样稿的外沿在 212，App 的 `rOut` 是 210，
    /// 所以是 −2 pt = −0.0328 个带宽。心线落在 209，正是样稿那根沿的中间。
    var wallOuterRatio: CGFloat = -0.0328
    /// 整圈不对称是**这层的意思**，不是瑕疵：样稿那条 conic 六档一明一暗，
    /// 读者靠它判断这口盘是圆的、光从哪来。比例取自那六个十六进制的灰阶
    /// （65/101/42/82/36/76，除以最亮那档 101）。
    ///
    /// 起点是 115°，**不是样稿那句 `from 205deg`**：两边的零点不在一起。CSS 的 conic 从
    /// 12 点顺时针数（φ），SwiftUI 的 `AngularGradient` 从 3 点顺时针数（屏幕角 θ，y 轴朝下），
    /// 换算 θ = φ − 90。205 − 90 = 115。按 205 写就是把整条明暗带转走四分之一圈：
    /// 实测那版把最亮的瓣甩到空闲缺口上（210° 抬 +78，样稿同处只有 +30），
    /// 「暗的那几段」反而被这道沿点亮。
    var wallFromDegrees: Double = 115
    var wallStops: [WallStop] = [
        .init(at: 0.00, bri: 0.64),
        .init(at: 0.11, bri: 1.00),
        .init(at: 0.29, bri: 0.42),
        .init(at: 0.50, bri: 0.81),
        .init(at: 0.68, bri: 0.36),
        .init(at: 0.87, bri: 0.75),
        .init(at: 1.00, bri: 0.64),
    ]
    /// 样稿这一层写的就是 `opacity:.72`。样稿的前提是**沿比底亮**（暗底上一道金属亮边）；
    /// 纸上反过来，只能是一道影子般的倒角。浅皮 0.55 → 0.18 → 0.10 都还留着一条沿：
    /// 灭灯对照（`DISKWISE_LIGHTS=wall`）y=872 横切左带外沿，开着是 518:217 / 522:206，
    /// 关掉抬到 231 / 214，跟带身齐平——用户圈出来的左右两条「黑线」就是它，0.10 也一样画。
    /// 纸上这道沿没有存在的余地：玻璃的轮廓由 `crossLight` 外沿提亮 + 透光化进纸里来收。
    var wallOpacityDark: Double = 0.72
    var wallOpacityLight: Double = 0
    /// 基色压暗倍率：`palette.ink` 在深皮上是字色（近白，HSB 明度 ~0.93），直接铺等于环上
    /// 套了一圈白。这条沿的**绝对**明档得钉在样稿那个最亮的瓣上：`#5A6572` 灰阶 101
    /// ≈ HSB 明度 0.40，除以 ink 的 0.93 就是 0.43。
    /// 上一版借的是 `shadeBrightnessScale` 那档 0.57，出来最亮瓣 134——同尺度实测
    /// 空闲缺口 r209 抬到 101（样稿同处 44），暗段被点亮成比亮段还显眼，正是要避免的那件事。
    /// 换算按近中性色走（ink 饱和度低，HSB 明度≈灰阶/255），带颜色的皮上会有几档偏差。
    var wallBaseScaleDark: CGFloat = 0.43
    /// 浅皮不能照抄 0.40 这个绝对明档。上面那档成立的前提是**沿比它的底亮**——暗底上
    /// `#5A6572` 是一道金属亮边；纸上 ink 本来就近黑，乘 1.0 出来是外圈一圈炭黑描边，
    /// 环看着像被墨笔勾过。这里反个方向：把明档抬到 0.61（`0.102 × 6.0`），叠在浅带上
    /// 是一道略深的银灰，不是黑线。不过 `wallOpacityLight` 最终收到 0——纸上这层沿
    /// 不管多淡都会被读成描边，所以这个明档眼下不参与浅皮的画面，只留给
    /// 「某个浅皮想重新点亮墙沿」那一档做底。
    var wallBaseScaleLight: CGFloat = 6.0
    /// 盘沿的**柔度**（单位：个带宽）。0 = 线上那一版：硬描边，不摊。
    /// 水晶棒开到 0.09，两趟的数与理由都写在 `RingStyle.crystal` 那两段上。
    var wallSoftnessDark: CGFloat = 0
    var wallSoftnessLight: CGFloat = 0

    /// 盘沿与最外那道发丝的**绝对饱和度**。
    ///
    /// 样稿给这两处写的都是带蓝的绝对色，不是「纸上那支墨」：`.wall` 那六档
    /// `#39424E / #5A6572 / #242A33 / #48525F / #1F252C / #424B57` 转 HSB 全是色相 212°、
    /// 饱和 .21 上下；`.hairline` 写的是 `rgba(200,220,248,.185)`，同一支蓝（色相 215°、
    /// 饱和 .19）。这两层原来都借 `palette.ink` 的饱和——石墨的 ink 是 `#F2F4F7`，
    /// 饱和只有 .02，于是这道沿**在结构上调不出蓝**。实测（量完态、绕整圈平均、
    /// u = r ÷ 环外沿）：u=1.00 我们 (77,74,71) R−B **+6.5**，样稿 (78,87,109) R−B **−30.6**
    /// ——亮度只差 12，冷暖差 37 格。灭灯对照反合成（关掉 `wall`，同一格掉到 (45,45,45)，
    /// 按那层 .72 的不透明度回推）盘沿自己是 (90,83,78) 的暖灰。用户那句「最外层还是
    /// 黑灰色」量的就是这一档，不是亮度不够。
    ///
    /// 所以这里钉样稿那个**绝对饱和**，色相仍跟着 ink 走（石墨 ink 的色相 216°，
    /// 与样稿那 212° 是同一支蓝），换皮不会把串色带进来；浅皮不吃这一档
    /// （`wallOpacityLight`/`hairlineOpacityLight` 都是 0，那道沿在纸上由光收边）。
    var edgeSaturationDark: Double = 0.21

    /// 最外那道发丝（样稿 `.hairline`：`inset:-2.5px` 的框上一道 0.8 px 的近白线）。
    /// 它是**盖在弧上面**的（DOM 里排最后），所以亮段暗段都连成同一圈——这一笔管的就是
    /// 「整块盘的轮廓是不是正圆」。
    ///
    /// 那道线在样稿里占 211.7→212.5：框半径 420/2+2.5 = 212.5，`inset 0 0 0 .8px` 描在框
    /// **内侧**，所以外沿正好压在 212.5。换算要用自己的分母：App 的带子外沿是 `rOut` = 210
    /// （样稿那圈弧的外沿在 209.55，差 0.45 pt，是两边各自画出的同一件事，不是两套几何），
    /// 所以外沿偏移 = 212.5 − 210 = **+2.5 pt** = 0.0410 个带宽，负号表示探出环外。
    /// 早先这里写的 `212 − 209.55 = 2.45` 拿样稿的沿去减样稿的弧，得出的 0.0165 会把这道线
    /// 画回带子里面（211.0），正圆收边就白加了。
    ///
    /// 它那 `0 0 26px rgba(118,150,222,.13)` 的外发光不在这儿：那是 `bloomGlow` 在管的活。
    var hairlineWidthRatio: CGFloat = 0.0131     // 0.8 px / 60.9
    var hairlineOuterRatio: CGFloat = -0.0410
    var hairlineOpacityDark: Double = 0.185
    /// 浅皮这一档从 0.34 收到 0。0.34 的 ink 在纸上就是环外那道最清楚的黑线：
    /// 单独摘掉这一层，r≈427 抬 46 阶，比其它任何一层都明显。玻璃的轮廓该由光收，
    /// 外沿已经在 `crossLight` 末尾提亮 + 透光化进纸里；这层再描一圈墨，等于给玻璃套铁丝。
    var hairlineOpacityLight: Double = 0

    // ── 8. 扫完之后常驻的那道反光（`.glint`）──
    //
    /// 样稿 `.glint` 的 `filter: blur(3.4px)` 落在 420 px 的盘上：3.4 ÷ 带宽 61 = 0.056。
    /// 上一版是 0.07（≈4.2 px），亮头本来就暗，再糊一成，9 秒一圈只剩一团雾。
    var glintBlurRatio: CGFloat = 0.056
    /// 亮部从一圈的哪儿开始。0.822 = 样稿 conic 的 296°/360°。**峰在头、尾拖 64°**：
    /// 上一版写成 0.90 起步、0.962 一个居中三角峰，光斑两侧都在亮，读成一根会转的白条；
    /// 样稿是「亮头领着一条长尾」，运动方向才看得出来。
    var glintLead: Double = 0.822
    /// 各停靠点的比例取自样稿 `#glint` 那段 conic（α ÷ 峰值 .75）：
    /// 0.861 .011 / 0.906 .029 / 0.939 .069 / 0.958 .133 / 0.971 .427 /
    /// 0.978 .693 / 0.984 1.000 / 0.992 .747 / 0.997 .160，1.0 断在透明。
    var glintRamp: [GlintStop] = [
        .init(location: 0.861, peakScale: 0.011),
        .init(location: 0.906, peakScale: 0.029),
        .init(location: 0.939, peakScale: 0.069),
        .init(location: 0.958, peakScale: 0.133),
        .init(location: 0.971, peakScale: 0.427),
        .init(location: 0.978, peakScale: 0.693),
        .init(location: 0.984, peakScale: 1.000),
        .init(location: 0.992, peakScale: 0.747),
        .init(location: 0.997, peakScale: 0.160),
    ]
    /// 峰值 0.75 取自样稿 `.glint` 的最后一段：354.4° 的 `rgba(255,251,243,.75)`。
    /// 顶色也是那个值。上一版写的 0.34 和 `rgba(255,240,214,.34)` 都不是原文——
    /// 原文没有 .34 这一档；深皮上 screen 叠 .34 只有稿子一半的亮度，
    /// 亮头退成一片灰，读起来是「环上有一团雾在挪」，不是一道反光。
    /// **近白，不用主色**：主色压在六色环带上必然跟某一段撞色，撞了就又读成「多了一条弧」。
    var glintPeakDark = RingInk(red: 1, green: 0.984, blue: 0.953, opacity: 0.75)
    /// 浅皮这道反光**用白不用主色**：主色是蓝，而空闲那一段本来就几乎不画，
    /// 蓝色坡道铺上去等于给「最该安静的那格」上了色（实测过，那段整块发蓝）。
    /// 白的只会把灰提亮，不带色相；纸上够亮才给到 0.62，因为浅皮没有 screen 可用。
    var glintPeakLight = RingInk(red: 0.965, green: 0.976, blue: 1, opacity: 0.62)

    /// 反光只许落在**带面**上。内侧从 `rIn` 再让 2% 带宽：样稿的遮罩从盘半径 70.85%
    /// 起才是黑的，而 70.85% ≈ 井口半径（`rIn / rOut` = 0.71）——它只遮井口，不碰带面。
    /// 外侧在深皮上一路放到金属沿的外沿（见 `glintMask`）；浅皮仍收在沿的内沿。
    var glintMaskInnerBite: CGFloat = 0.02
    /// 裁边自己的羽化，1.2% 带宽（≈0.7 pt）；硬切会在带心留下一道直角。
    var glintMaskFeather: CGFloat = 0.012

    // ── 9. 扫描期间那道光（`.beam` 宽光 + `#moSweep` 读数头）──
    //
    // 稿子是**两笔**叠在同一根带上，不是一笔：
    //   `.beam`    三层 46°/30°/16° 的嵌套弧（.32/.15/.07），越往里越亮——探照灯铺在
    //              边界**往前**的那一段；
    //   `#moSweep` 一根近白的读数头：峰值钉在边界上（360° .68），身后 26° 拖尾
    //              （334° .040 → 350° .115 → 357.6° .40），前方 28° 只留一点预照
    //              （0° .050 → 12° .012 → 28° 全透）。
    // 早先这边只画了前一笔的简化版，还把亮头放在前头、在边界上又压了一道 2.4° 的墨沿
    // ——读出来就是「光晕跑到读数线前面去了」。浅皮截图上最扎眼的就是那道墨沿。
    var beamHeadDark: Double = 0.42
    var beamHeadLight: Double = 0.20
    /// 宽光那三档的归一比例（实际不透明度 = `beamHead*` × scale）。
    var beamStops: [SweepStop] = [
        .init(location: 16.0 / 360, scale: 1.00),
        .init(location: 30.0 / 360, scale: 0.47),
        .init(location: 46.0 / 360, scale: 0.15),
    ]
    /// 读数头是**镜面高光**，不是主色光：稿子 `rgba(238,246,255,.68)` 就是这族近白。
    var sweepHeadInk = RingInk(red: 0.933, green: 0.965, blue: 1, opacity: 1)
    var sweepHeadOpacityDark: Double = 0.68
    /// 浅皮也得用这族近白：试过主色（跟同为蓝的弧糊成一片）和 `shade(lamp)`
    /// （纸上是一条压深的脏痕，不像光）。纸上能做的只有「提亮到刺眼」：
    /// 峰值 0.85 把 233 的带子推到 252，才读得出一道掠过纸面的白光。
    var sweepHeadOpacityLight: Double = 0.85
    /// 稿子 `#moSweep` 带 `filter: blur(1.1px)`。不给这一档，读数头就是一条硬边——
    /// 截在 117.25° 的 1 px 亮线上（lum 235），读起来像弧的切边，不像光。
    /// 1.1 是稿子的 CSS px，按 420 视图缩到本 App 的环径约 0.9–1.0 pt。
    var sweepHeadBlur: CGFloat = 1.0
    /// 读数头的坡道，比例照抄 `#moSweep` 的 conic（除以 360）。
    var sweepHeadStops: [SweepStop] = [
        .init(location: 0, scale: 0.074),
        .init(location: 12.0 / 360, scale: 0.018),
        .init(location: 28.0 / 360, scale: 0),
        .init(location: 316.0 / 360, scale: 0),
        .init(location: 334.0 / 360, scale: 0.059),
        .init(location: 350.0 / 360, scale: 0.169),
        .init(location: 357.6 / 360, scale: 0.588),
        .init(location: 1, scale: 1),
    ]

    // ── 10. 弧上直接标的数 ──
    //
    /// 落在带的正中偏外一点：内侧那道暖沿是「点我」，数字压上去就等于把这一屏唯一一处
    /// 可点的东西盖住；太靠外又会戳出环的外沿。0.42 是两头都让开的位置。
    var labelBiteRatio: CGFloat = 0.42
    /// 短于 5% 的弧不标数；环小于一整屏那一档（下钻时收成 132 pt）整排都不标——
    /// 带厚只剩 19 pt、那段弧的弧长也只剩十几 px，六枚 11 pt 的数会叠成一片字糊在环上。
    var labelMinSpan: CGFloat = 0.05
    var labelMinDiameter: CGFloat = 260
    var labelFontSize: CGFloat = 11
    /// 去底之后唯一要补的是对比：动得了的那段是饱和色，数得用亮字压上去。
    var labelInkHotDark = RingInk(red: 1, green: 0.886, blue: 0.686, opacity: 0.90)
    var labelInkHotLight = RingInk(red: 1, green: 1, blue: 1, opacity: 0.95)
    /// 「本次移入废纸篓」那条虚线弧：数用主色写，纸上给满、深皮收到 0.9
    /// （深色上主色本身就亮，顶格会跟旁边那道近白的亮字抢）。
    var labelMovedDark: Double = 0.9
    var labelMovedLight: Double = 1.0
    var labelInkNeutralDark: Double = 0.46
    var labelInkNeutralLight: Double = 0.60

    /// 「今天线上这一版」。以后出第二款材质是**加一个静态成员**，不是改这几行。
    static let shipped = RingStyle()

    // ── 11. 横截面：第二款材质（水晶棒）的数 ──
    //
    /// 总开关。`false` 时绘制层**根本不进**截面那条路——所以 `shipped` 的六皮逐字节对照
    /// 不需要为这一档重新登记，它是被一个布尔量挡在门外的，不是被"数值恰好相等"糊过去的。
    var crossOn: Bool = false
    /// 深色皮上的截面。空表 = 没定义，绘制层会退回 `arcPaint`（不许拿默认表硬画）。
    var crossDark: [CrossStop] = []
    /// 浅色皮上的截面。**不能跟深色共用一条配方**：纸上「亮边」是看不见的——
    /// 原型那边有 `mix-blend-mode: screen` 帮忙，浅皮没有（同一句教训记在
    /// `Components.swift` 的 `lit` 那档上）。
    ///
    /// 第一版在这里照抄了深色那套「压暗芯 + 推饱和」，六皮看图直接废：dawn 的芯部彩度
    /// 从 71 冲到 121，蓝段读作**一块糖**而不是玻璃棒（原型第 7 节悬着的那条「琥珀段像不像糖」
    /// 就是同一个失败形状）。
    ///
    /// 第二版改成「整条带子微微压暗 + 内外沿各抬一点」，实测更废：`ring-unroll.py` 把带子
    /// 展开成「一行=角度、一列=半径」之后看得很清楚——**每一档倍率都落在芯部，于是它只是一个
    /// 全局变暗**（dawn 中性段均值 210→199），而沿半径的调制只有 10 个灰阶（截面比 1.05）。
    /// 读作「抛光的塑料」，不是玻璃。同一个工具还抓到第二条：`reclaimEdge` 那道沿铺在带子
    /// 内侧 42% 上、不透明度 0.85，**盖在截面上**，所以热弧内侧那半条根本没被材质碰过。
    ///
    /// 于是第三版换的是**形状**，不是数值大小。纸上玻璃的横截面和暗底上是反的：
    /// 芯部要**保住段自己的颜色**（`bri 1.00`，不再压暗——那是账，不是材质该管的），
    /// 亮度全部让给两条**窄**线：内沿一道折射亮线（降饱和 + 提亮 = 纸透过来），
    /// 外沿一道聚色暗线（提饱和 + 压暗 = 边缘聚色），紧挨着它内侧再补一道会聚亮线。
    /// 窄是关键：两条边各占带宽 5–8%（8–10 px），极差从 10 抬到 40 上下，而均值几乎不动——
    /// 「局部对比高、整体不发暗」才是透光，把带子涂深只会得到一块深色橡胶。
    /// 代价记着：外沿那道墨一旦铺宽或压过头，就读成给带子描边（第三版第一稿就是这样，
    /// 看图时蓝段外圈那圈深-navy 边明显重了，于是把 `bri 0.80 / sat 1.40` 收到 `0.90 / 1.22`）。
    ///
    /// 但真正让**中性那几段**立起来的是 `ink`：浅皮的灰弧是 9% 的墨洗，HSB 那一套对它空转
    /// （同一档截面在深皮中性段做出极差 51、在浅皮只有 12）。整条配方因此按「棒子的厚度」重排：
    /// 两道沿厚（`ink ≈ 1.7`）、亮线薄（`ink ≈ 0.42`）、芯部就是段色自己。
    var crossLight: [CrossStop] = []

    /// 深皮上的**混色**截面。空表 = 不走这条路，沿用上面 `crossDark` 那套倍率
    /// （浅皮和 `shipped` 都留在倍率上：纸上没有 screen，绝对色的亮线在纸上是另一回事，
    /// 那套配方按「棒有多厚」重排过，见 `crossLight` 那段）。
    ///
    /// 前七档的位置与混法照 `diskwise-v2.6-crystal.html:1772-1775` 那五行数组搬过来
    /// （`RI = R − BAND/2`、`RO = R + BAND/2`，换算成带内比例见 `at`）；**末尾那四档是 2026-10-24
    /// 照「玻璃的剪影」重写的**，不再对样稿那三档的暖收尾负责，理由写在使用处那张表上面。
    /// 只有最内那档对不上：样稿给的是 `r = RI−5`，按带宽折算是 `at = −0.082`，
    /// 落在带子**外面**（洞那边）。SwiftUI 的 `RadialGradient` 停靠点会被夹进 0…1，
    /// 所以表里写的是 0.0000——那一档在真机这边管的是带子最内一条像素的底色，
    /// 不是样稿那句「洞那边的底色」。这句改过，别再照旧注释以为负数档还在。
    var tubeStops: [TubeStop] = []
    /// 棒芯 = **同支色相压暗**，不是往中性黑里沉。
    ///
    /// 之前这里是错的：拿一个绝对锚 `#0A0D12` 混 0.86，注释写着「样稿五档 `BODY_BOT` 折算
    /// 成灰阶都在 4 格以内」。灰阶那笔账没算错，错在**只对了灰阶**——样稿的 bot 是
    /// `#152241`（蓝）、`#1E1708`（金），两支都带着自己的色相，而 `#0A0D12` 是近中性。
    /// 2026-10-23 用 `/tmp/xbody.py`（按色相分档、u = (r−内沿)/带宽 定位，两边尺度差 1 pt
    /// 不混进账）量带芯 u=45% 那一档：样稿动得了段 亮度 44 / B−R +43，真机 亮度 37 / B−R +19。
    /// **亮度差 7、彩度差一倍还多**——图上读到的「灰蓝 vs 玻璃蓝」就是这一条，不是亮度不够。
    ///
    /// 两个数照样稿 top→bot 四档的比值定：明度 ×0.246…0.419（取 0.36），饱和 ×1.194…1.246。
    /// 样稿一档一个 bot 是因为它把身子写成五张死色表；真机的段色来自皮肤
    /// （六套皮各一支主色），所以这里只能给**关系**，不能给绝对色。
    ///
    /// **饱和那一档 2026-10-23 从 1.18 抬到 1.65，是改成按绝对读数钉的**，原因量出来的：
    /// 同一条 u=45% 采样点两边各转 HSV（`/tmp/xcore.py`）——
    /// 真机 色相 .616 / 饱和 .471 / 明度 .278，样稿 色相 .618 / 饱和 .661 / 明度 .275。
    /// **色相和明度已经对上，整条差就是饱和一档**，而 1.18 是 top→bot 的关系数：它只能把
    /// 真机推到「比自己的身子饱和 18%」，推不到样稿那根**死色 bot**（`#152241` 的 S 就是 .677）。
    /// 两支起点不同（皮肤主色 S ≈ .40，样稿 body S ≈ .55），同一个倍率落点自然不同——
    /// 这一档改的是「落点」，代价是**它不再是从样稿比值推出来的数**，而是照着样稿成品钉的：
    /// 0.471 ÷ 1.18 × 目标 .661 ≈ 1.65（u45% 落在 0.4015 与 0.6314 两档之间，按 `tubeStops`
    /// 插值算约掺 5.6% 身子，所以 composite 读数与芯本身差不到 1 个点）。
    /// 别的皮肤穿上这一档会跟着自己的主色走，落点到位不到位由该皮自己复测，别替六套皮签一次名。
    ///
    /// **顺带量到的一条，还没修**：样稿连「灰」的那几档芯都带蓝——同处色相 .611、饱和 .471
    /// （`BODY_BOT.sys #121722` 本来就是暗板岩），真机这几段芯是色相 .593、饱和 .184 的近中性。
    /// 抬倍率会一起抬，但皮肤的灰就是灰，乘不出样稿那支板岩蓝；要不要给灰段芯也钉一支蓝，
    /// 是**皮肤层**的决定（写进 `skins.json` 的段色才对），不在这里偷偷调色。
    var tubeCoreBrightnessScale: Double = 0.36
    var tubeCoreSaturationScale: Double = 1.65
    /// 冷沿锚：样稿 `hexMix(hexMix(top,'#C6F2FF',.52), '#ffffff', .18)` 那两个常数。
    var tubeCoolInk = RingInk(red: 0xC6 / 255, green: 0xF2 / 255, blue: 1, opacity: 1)
    var tubeCoolMix: Double = 0.52
    var tubeCoolWhite: Double = 0.18
    /// 暖沿锚：样稿 `hexMix(top,'#FFD2A2',.34)`。
    var tubeWarmInk = RingInk(red: 1, green: 0xD2 / 255, blue: 0xA2 / 255, opacity: 1)
    var tubeWarmMix: Double = 0.34
    /// 段色是**灯**，身子得比灯暗一档。样稿这两件事是分开的两张表：
    /// `BODY_TOP.reclaim #5E86D6`（灰 131）是身子，`LAMP_RGB 168,196,255`（灰 194）是灯，
    /// 比值 0.675。真机动得了那段实测段色灰 165（`DISKWISE_LIGHTS` 全关、`standard` 材质、
    /// 带中 r180 平色量到），拿它直接当身子，外沿那档混完暖到 201，而样稿同处 151。
    /// 0.79 = 131/165 就是这么来的：先落到样稿那根身子的亮度，再让混色去管形状。
    ///
    /// **只压 `.hot` 与 `.cost`**——那两档的段色是灯派生的。灰的那几档（没量到、空闲、
    /// 系统可清除）段色本来就是身子，再压一道就把它们抹成轨道了。
    var tubeBodyScale: Double = 0.79
    /// 棒子按**不透明**画：先把段色在它自己的 alpha 上预合成到卡面，再拿这个实色去混
    /// 芯/冷/暖三个锚，整条截面以 alpha 1 上场。
    ///
    /// 开这一档的理由是同尺度实测（样稿全层 vs 真机全层，`/tmp/xsec4.py`）：动得了那段
    /// 内沿冷亮线样稿 120、真机 175，灰的那几段反过来——样稿 103、真机 84。
    /// 一高一低不是混色算错，是**两套编码打架**：样稿的弧全是实色描边，「这块按不动」
    /// 只靠颜色说（`BODY_TOP.sys #38455A` 是个不透明的暗板岩）；真机除了颜色还叠了一层
    /// alpha（`OverviewView.swift:4454` 给「系统可清除」写的 `.opacity(0.26)`），
    /// 而 alpha 是给**平均亮度**设的天花板：冷沿那一档算出来 199，乘 0.26 盖在 17 的卡面上
    /// 只落到 65。所以灰段的冷线画不出来，不是不亮，是**亮不上去**。
    ///
    /// 关掉它等于退回上一版：灰段那条内冷边永远停在 60 上下。
    /// 代价也要写清楚：弧一旦实色，它就盖住身下的轨道与孔里透出来的光——
    /// 样稿本来就是这个 z 序（`wall → 弧 → bore`，弧在 `.halo` 之上），所以这一条跟着样稿走。
    var tubeArcsOpaque: Bool = false

    // ── 12. 环上两根光：扫描期的线框、量完之后的能量流 ──
    //
    // 样稿那三条 stroke（`.mo-wire` / `.mo-flow` / `.mo-tail`）全都靠
    // `mix-blend-mode: screen` 才在暗底上成立。图层没有 screen，所以**深浅两皮各一组数**：
    // 深皮给灯芯（近白）；浅皮用样稿 `.mo-wire` 的冷白 `rgba(206,232,255,.92)`
    // （见 `RingLayers.swift` 的 `recipe`）。这股光只跑在「现在收得走」的蓝弧上，
    // 蓝底托着冷白是一道反光；早先给浅皮压暗的主色，实拍是蓝带里一根深蓝短划，
    // 读起来像划痕——纸上不该用墨画光。
    //
    // 长度一律写成「占样稿那圈 420 px 的比例」：环会从 232 长到 348，写死 1.35 px
    // 在大环上是一根发丝、在小环上就是一坨。换算与为什么走 Core Animation，
    // 都记在 `RingEdgeLights.swift` 顶上那段。
    var edgeLightsOn: Bool = true
    /// 亮丝半径 = `rIn + band × 这一档`。样稿是 `EDGE_R = R − BAND*0.40`，
    /// 换成这个式子就是 0.10——**照搬过来看不见**（看图：头压在带子内侧那条亮沿上，
    /// 近白压近白）。样稿那根带子是水晶棒、内沿是一道折射亮线，我们这条带子内侧
    /// 本来就是整条带上最亮的一处，同一档落点因此归了零。挪到外侧半幅。
    var flowEdgeBiteRatio: CGFloat = 0.60
    var flowHeadWidthRatio: CGFloat = 0.0032     // 1.35 / 420
    var flowTailWidthRatio: CGFloat = 0.0081     // 3.4 / 420
    var flowHeadLenRatio: CGFloat = 0.0179       // HEAD 7.5 / 420
    var flowTailLenRatio: CGFloat = 0.52         // TAIL = min(L*0.52, 62)
    var flowTailLenMaxRatio: CGFloat = 0.148     // 62 / 420
    var flowGapRatio: CGFloat = 0.0095           // 4 / 420
    var flowTailBlurRatio: CGFloat = 0.0040      // blur(1.7) / 420
    var flowHeadOpacityDark: Double = 0.92
    /// 浅皮的冷白靠 0.74 这一档压在蓝弧上：更淡会读成带子本身的渐变，
    /// 更浓就成一块白斑。0.30 的尾巴是同一条丝拖出来的余温。
    var flowHeadOpacityLight: Double = 0.74
    var flowTailOpacityDark: Double = 0.30
    var flowTailOpacityLight: Double = 0.30
    /// 一圈几秒 = `base + turn × 这段占整圈的比`。样稿 `2600 + span°×55` ms。
    var flowBaseSeconds: Double = 2.6
    var flowTurnSeconds: Double = 19.8
    var flowStaggerSeconds: Double = 0.9
    var flowLeadSeconds: Double = 0.35
    var flowHoverSpeedScale: Double = 0.62

    /// 线框：半径用弧的心线（样稿用 `R`），一笔 430 ms。
    var wireWidthRatio: CGFloat = 0.0027         // 1.15 / 420
    var wireGlowRatio: CGFloat = 0.0167          // drop-shadow 7 / 420
    var wireSeconds: Double = 0.43
    var wireIdleOpacityDark: Double = 0.85
    /// 浅皮这一档是 **0**：走完一圈那一笔（`traceOnce`）照画，但扫描期那圈常驻线框不画。
    /// 样稿的 `.mo-wire` 本来就是一条 430 ms 的一次性描边，没有常驻档；深皮上留着它像一道
    /// 蚀刻的扫描线，浅皮上则是环带正中间一道深灰的细线——`shade(lamp)` 叠 0.62 之后
    /// 再带一圈同色投影，纸上读出来就是「圆环怎么中间一道黑线」。消融实测：
    /// `DISKWISE_EDGE=off` 后 r≈284 那道暗谷（lum 189，两侧 229）整条消失。
    var wireIdleOpacityLight: Double = 0

    // ── 13. 预演（按住空格：这一圈全清空之后长出来的那截光弧）──
    //
    // 样稿那三笔（`gainMist` / `gainArc` / `gainDot`）是一族近白的薄荷绿。**这里不新造一档
    // 颜色**，直接用皮肤的 `safeFG`：它本来就是「零代价、现在动得了」那一档的字色（代价读法
    // 第一段、账本行「还剩多少能搬走」），预演说的是同一件事——「这一截我现在就能还给你」。
    // 石墨皮那一档实测 `#6EE7A7`，与样稿的 `rgba(126,236,193)` 同族，暗底环上分不出来；
    // 晨雾皮是 `#1B6B3A`，纸上反而只有深色才读得出（样稿那族近白在浅皮上等于没画，
    // 同 `flowHeadOpacityLight` 那条教训）。
    //
    // 宽度一律写成「占带宽的比例」：样稿 `BAND = 60.9`，那几个像素数就是从这里除回来的。
    /// 光弧半径 = `rOut − band × 这一档`。样稿写的是 `R − BAND*0.13`，而它的 `R` 是带心线
    /// （= 我们的 `rOut − band/2`），折到外沿上就是 0.63。
    var gainBiteRatio: CGFloat = 0.63
    var gainMistWidthRatio: CGFloat = 0.56      // 34.1 / 60.9
    var gainArcWidthRatio: CGFloat = 0.19       // 11.6 / 60.9
    var gainDotRatio: CGFloat = 0.11            // 6.7 / 60.9
    var gainMistBlurRatio: CGFloat = 0.115      // blur(7) / 60.9
    // 样稿另外还给弧和点各挂了一道 `drop-shadow`（9 与 12 / 60.9）。2026-10-22 摘掉了：
    // 挂几何在变的笔画 `.shadow` = 渲染服务器每帧现算一张位图，实测数记在
    // `RingLayers.gainArc` 上面那段。发光整段交给上面那层雾，所以这里不再留系数。
    var gainMistOpacityDark: Double = 0.30
    var gainMistOpacityLight: Double = 0.34
    var gainArcOpacityDark: Double = 0.95
    var gainArcOpacityLight: Double = 0.95
    /// 光弧长到头的时长（样稿 `stroke-dasharray 1.05s`）。
    var gainGrowSeconds: Double = 1.05

    /// 预演时「退到后面」的那几段乘的透明度。样稿写的是 `filter: brightness(.80) saturate(.90)`
    /// ——CSS 的 brightness 是**乘**，所以 `.80` 换算到「压暗两成」这一档；这里取的乘子
    /// 跟它同量级，但**实现不是滤镜**：一层滤镜都要渲染服务器为那条弧现算一张离屏位图，
    /// 而真正的代价在「切换时换了树形」，三种写法的同场配对实测（`DISKWISE_PERF_PREVIEW=1.6`，
    /// 30 s，尾段 22.7 s，数 >100 ms 的格数）：滤镜 11 格、压一道黑 10 与 13 格、
    /// 摘掉这一层 1–3 格、**乘在本来就在链上的 opacity 上**才是这一档的修法。
    /// 细节在 `RingLayers.previewDim(_:)`。彩度那 0.90 不单独做——压下去本身就压彩度。
    /// 浅皮收到一半：淡档色本来就只剩 9%~16% 不透明度，再压就连「哪一档」都读不出来。
    var previewDimOpacityDark: Double = 0.80
    var previewDimOpacityLight: Double = 0.90
    /// 预演那几秒能量流的流速倍率（样稿 `speedScale`：预演期 0.72）。
    var previewFlowSpeedScale: Double = 0.72

    /// 第二款材质：水晶棒。**数是量出来的、是从样稿源码换算来的，不是手调的** ——
    /// 横截面十条停靠点照 `tube()` 那十个 stop 换算（换算过程与基准就记在下面那张表上），
    /// 三个锚点与样稿 :1759-1761 自己的读数一致（内沿 #85A3C7 / 带心 #1D2D52 / 外沿 #929FC5，
    /// 明暗截面 .65/.22/.67，两条边色相差 12°，`redesign-v4/MATERIAL.md` 第 1 节同一份）。
    /// 倍率是相对**段色自己**的 HSB，不是相对那几个十六进制——段色随皮肤变，截面要跟着变，
    /// 否则六套皮只有一套是玻璃。代价（灰段内沿比样稿暗一档）记在下面。
    static let crystal: RingStyle = {
        var s = RingStyle()
        s.crossOn = true
        /* 这十条停靠点是**换算出来的**，不是看图调的。两步：
           ① 样稿 `diskwise-v2.6-crystal.html:1772-1775` 的 `tube()` 十个 stop，配 :1673-1674
              的 BODY_TOP / BODY_BOT 与 :1765-1766 的 cool/warm 混色，算出十档**绝对色**
              （灰阶 33/197/107/63/33/59/131/147/160/107，半径按 `at = (r − 149.1) / 60.9`）；
           ② 拿真机 hot 段**实际渲染出来的底色**（`/tmp/shots/g7-arconly` 关掉全部光层、
              r203 处 = #97AFF5，HSB 0.624/0.384/0.961）当分母，逐档除出倍率。
           反算校验过：这组倍率打回 #97AFF5 上，十档灰阶与样稿逐一对齐（量具就印在
           `/tmp/tube2cross.py` 旁边那条 heredoc 里）。
           为什么分母不是段色本身：真机 hot 段拿的是 `SweepRing.lamp(tint)`（=样稿那盏灯
           #A8C4FF 那一档），而样稿的**棒子身**是 #5E86D6——样稿把「灯」和「料」分成两个色，
           我们只有一个，于是棒子身比样稿亮 44 个灰阶。这一条是**上游的色**，不是截面能调出来的：
           截面把料压回样稿那一档，同时保留 `seg.color` 给灯用（余晖、暖沿、弧上的数都还吃 lamp，
           样稿那几层也正是用 LAMP 而不是 BODY）。代价记着：倍率的分母是蓝段，
           灰段（sat 0.15）被 ×1.46–1.76 推上去之后偏蓝一档，样稿 `sys` #38455A 自己就是蓝灰，
           所以这一推方向对；**彩皮（aurora / inkwash）上会不会过艳，看图判，别当已验证**。
           样稿 :1759-1761 自己给的读数（内沿 .65 / 带心 .22 / 外沿 .67、两边色相差 12°）
           与这次实测的剖面（芯在 r174、归一 0.22）对得上。 */
        s.crossDark = [
            .init(at: 0.0000, sat: 1.76, bri: 0.27, hue: -0.007),   // 洞那边的底色（样稿 r<149.1）
            .init(at: 0.0115, sat: 0.78, bri: 0.97, hue: -0.038),   // 内沿冷亮线（RI+0.7 = r149.8）
            .init(at: 0.0427, sat: 1.03, bri: 0.58, hue: -0.025),   // 冷边收口（RI+2.6 = r151.7，宽 1.9px）
            .init(at: 0.1478, sat: 1.59, bri: 0.45, hue: -0.010),   // 往芯里走（RI+9 = r158.1）
            .init(at: 0.4015, sat: 1.76, bri: 0.27, hue: -0.007),   // 暗芯（R−6 = r173.6）
            .init(at: 0.6314, sat: 1.60, bri: 0.42, hue: -0.010),   // 芯外侧回升（R+8 = r187.6）
            .init(at: 0.8851, sat: 1.46, bri: 0.87, hue: -0.013),   // 段身＝样稿 #5E86D6（RO−7 = r203）
            .init(at: 0.9606, sat: 1.02, bri: 0.83, hue: -0.008),   // 外沿开始转暖（RO−2.4 = r207.6）
            .init(at: 0.9869, sat: 0.63, bri: 0.80, hue: 0.004),    // 暖亮峰（RO−0.8 = r209.2）
            .init(at: 1.0000, sat: 0.85, bri: 0.58, hue: 0.000),    // 外沿断口（RO = r210）
        ]
        /* 浅皮的两条沿**不许用墨收边**。上一版在 0 / 0.93 两档压了 ink 1.75 / 1.70，
           理由写的是「墨厚一道」——ink 是乘在段色 alpha 上的倍率，超过 1 会被夹成 1，
           于是那里的弧变成完全不透明的一圈深色：真机上就是环内、外两道细黑线
           （全灰的那一屏最明显，因为段色本来就淡，深色边成了整条带子上唯一有对比的地方）。
           玻璃的两条沿是光打出来的：**提亮、透光**，不是压墨。所以这里 ink 全部 ≤ 1、
           靠 bri 把沿上的颜色推向白，0.930 / 1.000 两档再让 alpha 透出去，
           纸从带子边上透过来，环沿才是玻璃切口而不是描边。深皮不受影响：它走 `tubeStops`。 */
        s.crossLight = [
            .init(at: 0.000, sat: 0.86, bri: 1.10, ink: 0.55),  // 内沿：亮而透，不提墨
            .init(at: 0.055, sat: 0.58, bri: 1.15, ink: 0.30),  // 折射亮线：薄 + 提亮 = 纸透过来
            .init(at: 0.170, sat: 0.95, bri: 1.02, ink: 0.80),
            .init(at: 0.500, sat: 1.00, bri: 1.00, ink: 1.00),  // 芯 = 段色本身，账不动
            .init(at: 0.800, sat: 1.03, bri: 1.02, ink: 0.84),
            .init(at: 0.930, sat: 0.82, bri: 1.12, ink: 0.55),  // 外沿：提亮、透光，不压暗
            .init(at: 1.000, sat: 0.88, bri: 1.05, ink: 0.34),  // 最外一档化进纸里
        ]
        /* 深皮改走混色。前七档照抄样稿 `:1772-1775` 那个数组，一行一档、`at` 由它的半径换算：
           样稿的 offset 是**相对整圈 r=RO** 的（`RI = R − BAND/2 = 149.1`、`RO = 210`、
           `BAND = 60.9`），换算式 `at = (offset × 210 − 149.1) / 60.9`。
           第一档样稿画在 `RI−5 = 144.1`，也就是**洞里面**——它存在的意义是让那道冷亮线的
           起点够陡（0.7 px 之内从近黑冲到冷白）。SwiftUI 的 `Gradient.Stop` 把 location 夹在
           0…1，负的那档会平推到 0，所以这里把它写到 0：亮线的陡度由第二档 0.0115 自己撑，
           而带内那一格因此是芯色，不是「洞那边」的颜色。
           这条路径下没有 `sat`/`bri`/`hue` 可写——形状与颜色都在这一张表里，段色只提供身子。*/
        /* 外肩这四档是**材质改的**，不是颜色改的。2026-10-24 之前这儿照样稿收尾：身子→暖峰→
           暖断口，三档全是实色。量具上每一项都对得上，眼睛上看就是「环外套了一圈灰黑的硬边」
           ——玻璃的剪影不是靠一道深色收出来的，它靠的是**转过去的那一面还发亮、再往外化掉**：
           一根高光线（又冷又亮、只有 1–2 pt 宽）＋ 它外侧透明度一路走到近 0，让卡面、轨道和
           盘沿从玻璃里面露出来。所以这张表末尾多了 `ink` 这一列，值写在 `TubeStop.ink` 上。
           样稿的换算（`at = (offset × 210 − 149.1) / 60.9`）只还管前七档。*/
        s.tubeStops = [
            .init(at: 0.0000, a: .core, b: .core, t: 0),      // 样稿 r144.1，被夹到带子内沿（见上面那段）
            .init(at: 0.0115, a: .cool, b: .cool, t: 0),      // r149.8 内沿冷亮线
            .init(at: 0.0427, a: .cool, b: .core, t: 0.55),   // r151.7 冷边收口
            .init(at: 0.1478, a: .core, b: .body, t: 0.30),   // r158.1 往芯里走
            .init(at: 0.4015, a: .core, b: .core, t: 0),      // r173.6 暗芯
            .init(at: 0.6314, a: .core, b: .body, t: 0.26),   // r187.6 芯外侧回升
            .init(at: 0.8851, a: .body, b: .body, t: 0),      // r203.0 段身
            .init(at: 0.9400, a: .body, b: .warm, t: 0.45),   // 外肩底：棒转到这儿聚的一层暖，还在带子里
            .init(at: 0.9550, a: .cool, b: .white, t: 0.30),  // ★镜面高光起头：冷、近白
            .init(at: 0.9850, a: .cool, b: .cool, t: 0, ink: 0.62),   // 高光铺到这儿散开（0.955→0.985 = 1.4 pt）
            .init(at: 1.0000, a: .cool, b: .core, t: 0.5, ink: 0.14), // 断口：透到只剩一层皮
        ]
        s.tubeArcsOpaque = true
        /* 盘沿这层从「金属」改成「湿光」。他那句「最外层还是黑灰色」量的就是这儿：
           金属沿靠亮瓣压暗瓣塑形，可暗瓣落到卡面上是一道**比底只亮 7 格的灰环**——
           `bri 0.36` 那档算出来 HSB 明度 0.15，按 `.72` 盖在 `#16181D` 上是 (31,33,38)，
           而它内侧那半截（206→210）原先被实色弧压着，上面那张表一改成透的，它就整截露出来。
           玻璃的沿只有亮瓣：背光两瓣直接不上色（`ink` 0.05/0.09），亮瓣抬到 0.58
           （0.43 是对着样稿 `#5A6572` 钉的绝对档，这一趟不再对那笔像素账负责）。
           瓣的角度分布一个字没动——那是「光从哪来」的账，`wallFromDegrees` 上面记着。 */
        s.wallStops = [
            .init(at: 0.00, bri: 0.70, ink: 0.34),
            .init(at: 0.11, bri: 1.00, ink: 1.00),   // 主高光瓣
            .init(at: 0.29, bri: 0.55, ink: 0.09),   // 背光：不上色
            .init(at: 0.50, bri: 0.86, ink: 0.66),
            .init(at: 0.68, bri: 0.50, ink: 0.05),   // 背光：不上色
            .init(at: 0.87, bri: 0.80, ink: 0.52),
            .init(at: 1.00, bri: 0.70, ink: 0.34),
        ]
        s.wallBaseScaleDark = 0.58
        s.wallSoftnessDark = 0.09
        /* 第二趟（同一天的下一小时）：把这道沿从「一条亮线」摊成「环外那圈湿光」。
           看图抓到的失败形状是——高光线上下都是暗的：带子最外 1.5 pt 已经透了（露卡面），
           沿又只探出 2 pt、还大半不上色，于是环外紧挨着一圈黑，读起来像亮线**浮**在盘外。
           玻璃不是这个形状：它把光带出轮廓外面一点。所以这层宽 0.0985 → 0.135、
           外探 −0.0328 → −0.075（沿心从 r209 挪到 r210.5，铺 205→216）、柔度 0.05 → 0.09，
           不透明度补回 0.80 顶住摊宽掉的那点峰值。
           这三档全是**几何与柔度**，色表一个字没动：亮瓣还是那几瓣，只是糊到外面去了。
           没去动 `bloomStops`——那层是灯色（石墨的灯是金的），往外再摊一层就是他骂过的
           「环外完全另一个颜色」。 */
        s.wallWidthRatio = 0.135
        s.wallOuterRatio = -0.075
        s.wallOpacityDark = 0.80
        // 弧的外沿一改透，整圈剪影就只剩这道发丝还在收口。0.185 那档是照着样稿那句
        // `rgba(200,220,248,.185)` 钉的；这趟的对错不看它，看眼睛——0.26 是「湿」的最低档，
        // 再低那条边就化进卡面里，环读起来没有轮廓。
        s.hairlineOpacityDark = 0.26
        s.boreOuterGlowDark = 0.80
        s.boreOuterGlowLight = 0.05
        s.boreMouthGlowDark = 0.17
        s.boreMouthGlowLight = 0
        s.trackBevelDark = 0.80
        s.trackBevelLight = 0
        s.tickOpacityDark = 0.13
        s.tickMajorOpacityDark = 0.32
        s.tickOpacityLight = 0.20
        s.tickMajorOpacityLight = 0.44
        /* 那道「点我」的暖沿**照抄样稿的几何**：`EDGE_R = R − BAND*0.40`、`EDGE_W = BAND*0.20`
           （`diskwise-v2.6-crystal.html:1695`）→ 贴住内沿的一条 12 px 细边，r 149.1–161.3。
           默认那档 0.42 宽（铺到 r 175）不是「我们这条带子该宽一点」，而是样稿**自己退回过一次**
           的形状——:1806-1810 那段注释写着「等于拿一块不透明浅蓝平板盖住玻璃棒的内半支，
           段身渐变再准也读作刷了漆的板」，然后第 2 轮把它收成 0.20。
           我们这边抄的是第 1 轮，所以 2026-10-23 实测的剖面是「内半条一路平亮、芯只到 0.36」，
           而样稿是「细边 + 芯 0.22」。
           别把宽度当账：这条沿表示「这段收得走多少」靠的是**弧长**（`RingLayers` 里那道
           `span = reclaim / value`），径向多宽纯粹是材质，样稿第 2 轮动的也只有宽度。
           沿比样稿的 .90 略收：样稿有 `mix-blend-mode: screen` 帮它只加光不盖色，图层没有。 */
        s.reclaimEdgeWidthRatio = 0.20
        s.reclaimEdgeOuterRatio = 0.80
        s.reclaimEdgeOpacity = 0.78
        return s
    }()

    /// 此刻这一屏用哪一份材质。
    ///
    /// **正式的那条路是皮肤 JSON**：`skins.json` 的 `ring` 字段 → `SkinCatalog` 解析 →
    /// `Theme.ring`（也就是传进来的这个 `look`）。视图只读这一处，换材质一行代码不动。
    ///
    /// `DISKWISE_RING_STYLE` 仍然赢，但它现在是**取证链路的覆盖**，不是选材质的入口：
    /// 批量拍图要靠它把同一套皮肤的两个材质各拍一张做逐字节对照（`tools/ring-gate.py`
    /// 那两组建基线的会话就是靠它跑的），认不出的名字回落到皮肤自己给的那档，
    /// 而不是像以前那样一律回 `shipped`——否则一个拼错的 env 值会悄悄把水晶拍成标准，
    /// 而图上看不出来。
    /// 覆盖表只在进程启动时读**一次**。环境变量在进程活着的时候改不了，而
    /// `ProcessInfo.environment` 每读一次都要把整张 environ 重建一遍（`sample` 里
    /// 那一串 `_NativeDictionary._copyOrMoveAndResize` 就是它）——2026-10-22 悬停
    /// 那 8 s 的主线程有 278 个样本停在 `RingStyle.selected`，只为了在每次重绘里
    /// 重新回答「今天用哪份材质」。缓存之后这条路径只剩一次 switch。
    private static let envLook: RingLook? = {
        let raw = ProcessInfo.processInfo.environment["DISKWISE_RING_STYLE"]?
            .trimmingCharacters(in: .whitespaces).lowercased()
        return raw.flatMap(RingLook.init(rawValue:))
    }()

    static func selected(for look: RingLook) -> RingStyle {
        (envLook ?? look).style
    }
}

/// 皮肤 JSON 里 `ring` 字段能填的那几个名字。
///
/// 这是一个**名字表**，不是协议、不是策略对象：它做的映射是「一个字符串 → 本文件里已经
/// 写好的那一堆数」，跟 `faces` / `elevations` / `motions` 那几张表一模一样（`SkinCatalog`
/// 的 `pick` 就是为它们造的）。账记在本文件顶部那条 L1 决策记录上。
///
/// `rawValue` 就是 JSON 里写的那串，所以认不出来的值（TYPO、或者旧版本 App 读到未来某款
/// 材质）由 `pick` 兜回 `.standard`，不会让整套皮肤消失——同那条「TYPO 不该让整套皮肤消失」。
enum RingLook: String, Hashable, CaseIterable {
    /// 今天线上这一版（`RingStyle.shipped`）。也是所有没写 `ring` 的字段的默认。
    case standard
    /// 水晶棒（`RingStyle.crystal`）。
    case crystal
}

extension RingLook {
    /// 这个名字对应哪一份数。新增材质 = 上面加一个 case、这里加一行、`RingStyle` 加一份数。
    var style: RingStyle {
        switch self {
        case .standard: return .shipped
        case .crystal:  return .crystal
        }
    }
}

// ── 颜色配方：把上面那档档数作用到一条具体色相上 ──
//
// 都是纯函数，进来一个 `Color` 出去一个 `Color`，不读视图状态。抽出来是因为
// 「灯」「提亮」「压暗」这三配方既给环用，也给主按钮那颗胶囊、账目行、飞废纸篓那几处用
// （`SweepRing.lamp` / `lampHot` 现在有 15 处外部引用）——配方和数得待在一起，
// 否则改了环上的饱和档，按钮还留在旧值上，一屏两处「同一个光源」。

enum RingMaterial {

    /// 这一屏的光：皮肤主色抬到样稿那盏灯的档位（饱和 .62、明度 .95、蓝道 92 那一档）。
    static func lamp(_ tint: Color, _ s: RingStyle = .shipped) -> Color {
        let ns = NSColor(tint)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return tint }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(sat * s.lampSaturationScale),
                     brightness: Double(min(1, b * s.lampBrightnessScale + s.lampBrightnessAdd)))
    }

    /// 灯芯最亮那一档：同色相、饱和再收一半、明度顶格。
    /// 整屏只有两处用到（主按钮顶、`.row.lit` 的数）。
    static func lampHot(_ tint: Color, _ s: RingStyle = .shipped) -> Color {
        let ns = NSColor(lamp(tint, s))
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return Color.white }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(sat * s.lampHotSaturationScale),
                     brightness: 1)
    }

    /// 灯芯渐变的下半截。走 HSB，不混黑（见上面 `shadeSaturationScale` 那句）。
    static func shade(_ color: Color, _ s: RingStyle = .shipped) -> Color {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return color.opacity(s.shadeOpacity) }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return Color(hue: Double(h),
                     saturation: Double(min(1, sat * s.shadeSaturationScale)),
                     brightness: Double(b * s.shadeBrightnessScale),
                     opacity: s.shadeOpacity)
    }

    /// 盘沿（`.wall`）那圈金属色：`palette.ink` 的**色相与明度** + `edgeSaturationDark`
    /// 那档绝对饱和，再按这一档的明度倍率走。
    ///
    /// 不跟着段色主色走：这道沿描述的是「这根玻璃边转到这儿被照到多少」，
    /// 要是跟着主色走，它就成了环外第七段弧（那正是「多了一条没人认领的弧」那个失败读法）。
    /// 饱和之所以不能再跟 ink 走，数字写在 `edgeSaturationDark` 上。
    static func wall(_ ink: Color, _ stop: WallStop, _ s: RingStyle, dark: Bool) -> Color {
        let ns = NSColor(ink)
        let base = dark ? s.wallBaseScaleDark : s.wallBaseScaleLight
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return ink }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: dark ? s.edgeSaturationDark : Double(sat),
                     brightness: Double(min(1, b * base * stop.bri)),
                     opacity: dark ? min(1, max(0, stop.ink)) : 1)
    }

    /// 最外那道发丝（`.hairline`）的颜色：和盘沿同一支蓝（见 `edgeSaturationDark`），
    /// 亮度跟 ink。样稿那档写的是 `rgba(200,220,248,.185)`——近白但明显偏蓝。
    static func edge(_ ink: Color, _ s: RingStyle, dark: Bool) -> Color {
        guard let rgb = NSColor(ink).usingColorSpace(.deviceRGB) else { return ink }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: dark ? s.edgeSaturationDark : Double(sat),
                     brightness: Double(b))
    }

    /// 借皮肤那枚颜色的**色相**，不借它自带的 alpha：井底、内壁亮带、扫描刻度三处都用它，
    /// 因为这三处在样稿里写的都是绝对不透明度。
    ///
    /// 为什么必须丢掉 alpha：`shadow` 在六套皮里的透明度差着量级——graphite 0.5、
    /// midnight 0.6、aurora 0.16、dawn 0.08、inkwash **0**。井是「洞比面低」这一件事，
    /// 拿它当投影色照乘，纸上和宣纸上等于没画井（0.24×0.08=0.019，孔底读数不动一档）。
    /// 所以这一条把停靠点当**绝对不透明度**用：深度由材质说了算，色相仍跟着皮肤走。
    static func bore(_ color: Color, _ opacity: Double) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else {
            return color.opacity(opacity)
        }
        return Color(.sRGB, red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                     blue: Double(rgb.blueComponent), opacity: opacity)
    }

    /// 横截面上的一档：把**该段自己的颜色**按 HSB 拉到位。
    ///
    /// 走 HSB 倍率而不是混白/混黑，是为了让同一条配方给六套皮都能用：段色随皮肤调色板变，
    /// 截面描述的是「这根棒在哪几个半径上被压暗、在哪两道边上被点亮」，那是**相对量**。
    /// 混黑会把暗芯洗成灰（原型那边暗芯 `#1D2D52` 是靠饱和 1.28 / 明度 0.46 立起来的，
    /// 不是靠加黑），混白则亮边一过顶就整条弧发灰。
    ///
    /// 色相那个加法要**折回 0…1**：`Color(hue:)` 接受的是「一整圈」的比例，蓝色偏青减出负数、
    /// 红色偏紫加过 1，不折回来的话这两档会各画出一个谁也没想到的颜色。
    ///
    /// `ink` 乘在原不透明度上并夹回 0…1。浅皮那几段墨洗弧（9%／16%）只吃这一档，
    /// 不吃 HSB——理由整段记在 `CrossStop.ink` 上。
    static func cross(_ color: Color, _ stop: CrossStop) -> Color {
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return color }
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        var hh = h + CGFloat(stop.hue)
        hh = hh - floor(hh)
        return Color(hue: Double(hh),
                     saturation: Double(min(1, max(0, sat * stop.sat))),
                     brightness: Double(min(1, max(0, b * stop.bri))),
                     opacity: Double(min(1, max(0, a * stop.ink))))
    }

    /// 段色 → 这一整根棒（每档一个**绝对颜色**，连同它的带内位置）。
    ///
    /// 与 `cross` 的分工：`cross` 答「这根棒在哪个半径被压暗、在哪道边被点亮」，那是相对量，
    /// 一条配方给六套皮共用；`tube` 答「棒身和棒芯各是什么颜色」，那是绝对量，跟样稿同一套。
    /// 为什么非绝对不可，整段记在 `TubeStop` 上（一句话：灰弧那道冷亮线要 ×3.99，倍率路被夹在 1）。
    ///
    /// `dimBody`：这一段穿的是**灯**还是**身子**。只有 `.hot`/`.cost` 的段色由灯派生，
    /// 要先按 `tubeBodyScale` 压回身子；灰的那几档再压一道就把它们抹成轨道了。
    ///
    /// `over` + `tubeArcsOpaque`：把段色先预合成到 backing 上，再以实色画这根棒。
    /// 样稿的弧全是实色描边，「这块按不动」只靠颜色说；真机在颜色之外还叠了一层 alpha
    /// （「系统可清除」那句 `.opacity(0.26)`），而 alpha 是给**平均亮度**设天花板：
    /// 冷沿算出来 199，乘 0.26 盖在 17 的卡面上只落到 65——灰段那条内冷边不是画不亮，
    /// 是亮不上去。预合成把「淡」留在身子这一档，棒形的三档（芯/冷/暖）改吃实色。
    /// 代价：弧从半透明变实色之后会盖住身下的轨道与孔里透出来的光，这一条跟样稿的 z 序
    /// （`wall → 弧 → bore`，弧本来就在 `.halo` 之上）走。`over` 给 nil 时整段不生效，
    /// 浅皮与 `shipped` 因此一个字没变。
    static func tube(_ color: Color, _ s: RingStyle, dimBody: Bool, over: Color?) -> [(at: Double, color: Color)] {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB), !s.tubeStops.isEmpty else {
            return []
        }
        var a = Double(rgb.alphaComponent)
        func mix(_ ca: [Double], _ cb: [Double], _ t: Double) -> [Double] {
            (0..<3).map { ca[$0] * (1 - t) + cb[$0] * t }
        }
        let top0 = [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
        let base: [Double]
        if s.tubeArcsOpaque, let back = over,
           let bg = NSColor(back).usingColorSpace(.deviceRGB) {
            base = mix([Double(bg.redComponent), Double(bg.greenComponent), Double(bg.blueComponent)],
                       top0, a)
            a = 1
        } else {
            base = top0
        }
        let top = dimBody ? base.map { min(1, $0 * s.tubeBodyScale) } : base
        // 棒芯走**同色相压暗**，不混中性墨：样稿那五档 bot 各带自己的色相（蓝段 `#152241`、
        // 金段 `#1E1708`），拿一个 `#0A0D12` 去复算只能对上灰阶、对不上彩度。
        // 数与实测账都在 `tubeCoreBrightnessScale` 上。
        let core: [Double] = {
            let ns = NSColor(Color(.sRGB, red: top[0], green: top[1], blue: top[2], opacity: 1))
            guard let src = ns.usingColorSpace(.deviceRGB) else { return top }
            var h: CGFloat = 0, sa: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
            src.getHue(&h, saturation: &sa, brightness: &b, alpha: &al)
            let out = NSColor(hue: h,
                              saturation: min(1, sa * CGFloat(s.tubeCoreSaturationScale)),
                              brightness: min(1, b * CGFloat(s.tubeCoreBrightnessScale)),
                              alpha: 1)
            guard let rgb = out.usingColorSpace(.deviceRGB) else { return top }
            return [Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent)]
        }()
        let cool = mix(mix(top, [s.tubeCoolInk.red, s.tubeCoolInk.green, s.tubeCoolInk.blue], s.tubeCoolMix),
                       [1, 1, 1], s.tubeCoolWhite)
        let warm = mix(top, [s.tubeWarmInk.red, s.tubeWarmInk.green, s.tubeWarmInk.blue], s.tubeWarmMix)
        func anchor(_ t: TubeAnchor) -> [Double] {
            switch t {
            case .body: return top
            case .core: return core
            case .cool: return cool
            case .warm: return warm
            case .white: return [1, 1, 1]
            }
        }
        return s.tubeStops.map {
            let c = mix(anchor($0.a), anchor($0.b), $0.t)
            return ($0.at, Color(.sRGB, red: c[0], green: c[1], blue: c[2],
                                 opacity: min(1, max(0, a * $0.ink))))
        }
    }

    /// 把一格的颜色提亮一档。深浅两种底走两条路，理由记在 `litDarkSaturationScale` 上。
    static func lit(_ color: Color, dark: Bool, _ s: RingStyle = .shipped) -> Color {
        let ns = NSColor(color)
        if dark {
            guard let rgb = ns.usingColorSpace(.deviceRGB) else { return color }
            var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
            return Color(hue: Double(h),
                         saturation: Double(sat * s.litDarkSaturationScale),
                         brightness: Double(min(1, b * s.litDarkBrightnessScale + s.litDarkBrightnessAdd)),
                         opacity: Double(a))
        }
        guard let mixed = ns.blended(withFraction: s.litLightBlendFraction, of: .white) else { return color }
        return Color(nsColor: mixed)
    }
}
