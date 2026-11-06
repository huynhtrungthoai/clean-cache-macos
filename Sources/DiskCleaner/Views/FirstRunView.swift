import SwiftUI
import DiskCleanerCore

// ── First-run screen ──────────────────────────────────────────────────────────
//
// **Why it covers the window instead of being a sidebar page**: this screen must finish saying "one full ring = the whole disk"
// before any number appears. In the sidebar it would be bypassed: a first-time user clicks "Overview" and sees a ring still
// being measured plus a column of "Counting...", exactly the first impression this screen exists to avoid.
//
// **Why not a sheet**: the screenshot pipeline only captures its own window (`SnapshotMode.pngData(window…)`),
// and a sheet is a separate child window (see `shootSheet`: it's absent from the parent's composite). With a sheet,
// `DISKWISE_FIRST_RUN=1` captures nothing, so this screen would never have evidence shots.
//
// **Why the scan is already running while it's covering**: the underlying screen's `onAppear` fires as usual, so the scan starts behind this one.
// That makes it double as the "wait for the first pass" page: pressing through lands on real numbers, no waiting for the sweep.
//
// **Why the ring shows sample numbers**: the sandboxed build can't measure anything before authorization, and any made-up number must say so on the spot
// (the line under the ring: "Sample ring, not your disk's numbers"). This is the app's first self-introduction; it may not lie.
// The five sample segments must still add up (`docs/DESIGN.md` section 6, item 7): 42.4 + 33.8 + 27.5 + 240.0
// + 168.3 = 512.0; the center lines "Whole disk 512.0 GB · Used 343.7 GB" and "Available after cleaning everything
// 272.0 GB" are computed from these five numbers, not invented separately.
//
// **The ring is real**: the actual `SweepRing`, its material set by the active skin (`skins.json` `ring` field ->
// `Theme.ring` -> `RingStyle`). So tapping a skin below redraws the ring in that skin's style.
// To be precise about what changes: all six built-in skins **use `crystal`**, so tapping changes ink, lighting,
// fonts and ring thickness, not the material; currently only a dropped-in `skins.json` can supply a second material.
// Hence this screen says "the whole face follows this row", not "try two materials here"; that false claim used to live here
// and was removed on 2026-10-21 when the screenshots didn't match. Sample-segment greys use `SweepRing.blockedInk` / `freeInk`,
// the same recipe as the Overview page, not a re-copied approximation.

/// First-run screen. `ContentView` overlays it on the window; after viewing or skipping, `Prefs.finishFirstRun()` dismisses it.
struct FirstRunView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var systemScheme
    @ObservedObject private var grant = HomeGrant.shared
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chrome
                    // The `Spacer` above isn't padding: it **centers the "title + ring" block vertically in the window**.
                    // Without it, on a tall window (852 pt measured in screenshots) content sticks to the top with buttons alone at
                    // the bottom and a screenful of empty space between, making the screen look unfinished. With it, the default 700-high window
                    // and an 850-high window share one composition, just with a bit more breathing room.
                    Spacer(minLength: 8)
                    HStack(alignment: .top, spacing: 34) {
                        story.frame(width: storyWidth(in: geo.size))
                        hero(diameter: ringDiameter(in: geo.size))
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    Spacer(minLength: 16)
                    actions
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                // Fill the full height even when content is shorter than a screen: the `Spacer` above relies on this to stretch,
                // keeping the buttons on the window's bottom edge instead of floating mid-air.
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            // Pin the container size to the window (same as `ContentView.detail`): on macOS 13 ScrollView
            // reports the content's full height as its ideal size; unpinned, it keeps growing the window.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(ThemedBackdrop().ignoresSafeArea())
    }

    // MARK: Clearance and language

    /// The top strip holds only a language switch. The traffic lights' 52pt isn't handled here: this screen is a `ContentView`
    /// overlay inside the system safe area (same tier as `detail`), so the system already yields that band;
    /// yielding `Chrome.trafficLightInset` again produces what the `Chrome.topClearance` comment
    /// complains about: "a stacked 58pt gap".
    /// Language sits at the top-right: it must be switchable **before the text is understood**; putting it in the footer would make
    /// non-Chinese readers read a whole screen of Chinese before finding the switch.
    private var chrome: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            LanguagePicker()
        }
        .padding(.top, 6)
    }

    // MARK: Left column: explaining the disk

    private var story: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("One ring, one disk"))
                    .font(theme.display(.largeTitle))
                    .tracking(theme.titleTracking)
                    .foregroundStyle(theme.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Every arc is real bytes on the disk — its length is exactly how much they take up."))
                    .font(theme.prose(size: 15))
                    .foregroundStyle(theme.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 9) {
                promise(symbol: "wifi.slash", text: L("No network, no uploads"))
                promise(symbol: "trash", text: L("Deletes go to the Trash first, and you can undo them"))
                promise(symbol: "checkmark.shield", text: L("System files stay off-limits"))
            }

            skins
        }
    }

    /// Three promises. Font size 12, `inkSecondary` only: they should be scanned on first view,
    /// but not outshine the line "one full ring is this disk".
    private func promise(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.palette.inkTertiary)
                .frame(width: 14, alignment: .center)
            Text(text)
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Skin row

    /// Six skins in 2 columns x 3 rows. Why not 3x2: this column is fixed at 420 (`storyWidth` already hits 420
    /// on a 1000-wide window), so three columns leave only ~100 pt per label;
    /// the Russian "Стекло северного сияния" doesn't fit in two lines and truncates to "северного си…".
    /// Two columns give ~170 pt, and the longest two names (Russian, German) fit in exactly two lines.
    private var skins: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: L("Skins"), detail: cnt(SkinCatalog.all.count, "skins"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                      alignment: .leading, spacing: 8) {
                ForEach(SkinCatalog.all) { skin in
                    skinChip(skin)
                }
            }
            Text(L("This row changes the whole face — colors, type, even how the ring is drawn. Swap it any time; Settings › Skins has a thumbnail of each one."))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(theme.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func skinChip(_ skin: Theme) -> some View {
        let chosen = themeManager.effective.id == skin.id
        let usable = themeManager.canUse(skin)
        return Button {
            // Same path as the skin page's button: `select` decides availability itself; if unavailable nothing happens
            // (this screen must not show a paywall; talking money on the first screen is the worst opening).
            themeManager.select(skin)
        } label: {
            HStack(spacing: 6) {
                swatch(skin)
                Text(L(skin.name))
                    .font(theme.bodyFont(.caption))
                    // Two lines, not one truncated line: the name is the control itself here; users need to see which skin they pick.
                    // The skin page card may truncate (it has a thumbnail, tagline and scrolls, so only the tail is lost);
                    // here truncation leaves just "Тушь и рисовая б…" (Russian screenshot 2026-10-21: two of six names truncated).
                    // Chinese and English fit in one line; the second line only appears for long-name languages.
                    // Two lines is the cap: widening further for three-line names would turn six capsules into six cards,
                    // degrading this column from "a row of faces to pick" into "a column of copy to read". With fewer columns two lines suffice
                    // (see `skins`).
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !usable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .semibold))
                } else if chosen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(chosen ? theme.palette.onTint : theme.palette.inkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.controlShape()
                .fill(chosen ? theme.palette.tint : theme.palette.surface))
            .overlay(theme.controlShape().stroke(theme.palette.separator,
                                                 lineWidth: theme.metric.stroke))
            .contentShape(theme.controlShape())
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .accessibilityLabel(LF("%1$@, %2$@", L(skin.name), chosen ? L("In use") : L("Use")))
    }

    /// A small swatch: paper color as background, accent as dot. Thumbnails (real mini UI) stay on the skin page;
    /// this screen needs "tap to switch" density, and 132pt-tall cards don't fit in a 560-high window.
    private func swatch(_ skin: Theme) -> some View {
        ZStack {
            Circle().fill(skin.palette.paper)
            Circle().strokeBorder(skin.palette.separator, lineWidth: 1)
            Circle().fill(skin.palette.tint).frame(width: 6, height: 6)
        }
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }

    // MARK: Right column: the ring

    private func hero(diameter: CGFloat) -> some View {
        VStack(spacing: 14) {
            SweepRing(segments: sampleSegments,
                      centerTop: L("Available"),
                      centerValue: uiHuman(sampleFree),
                      // The two center lines reuse the Overview page's keys, no new strings: if "Whole disk /
                      // Used / Available after cleaning everything" were worded differently in two places on one screen, people would read two ledgers.
                      centerCap: LF("Disk %1$@ · %2$@ used", uiHuman(sampleTotal), uiHuman(sampleUsed))
                          + "\n" + LF("%1$@ free once it's all cleared", uiHuman(sampleAfterClear)),
                      diameter: diameter)
                .frame(width: diameter, height: diameter)

            Text(L("A sample ring — these aren't your disk's numbers"))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(theme.palette.inkTertiary)

            legend
        }
    }

    /// Two color rules. Placed under the ring, not in the left column: they explain this ring,
    /// and next to the three promises readers would have to match the word "grey" to the chart themselves.
    ///
    /// A third rule, "dashed = moved to Trash", used to be here; removed after 2026-10-21 screenshots: showing that tier in a sample is a lie
    /// (a first-time user hasn't cleaned anything, so the Trash tier can't have data), and it didn't even look dashed:
    /// at 6% width the dashed stroke split into stacked concentric slivers, reading as "rendering broken" rather than "moved away".
    /// That tier is left for when it really appears: after a cleanup round, it shows up on the Overview page by itself.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            legendRow(tone: .hot, text: L("Color = reclaimable"))
            legendRow(tone: .grey, text: L("Gray = nothing we can move"))
        }
        .padding(.top, 2)
    }

    private enum LegendTone { case hot, grey }

    private func legendRow(tone: LegendTone, text: String) -> some View {
        HStack(spacing: 8) {
            swatchBar(tone)
            Text(text)
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The small legend strip: uses the ring's recipe, so "grey" is the same grey here and on the chart.
    private func swatchBar(_ tone: LegendTone) -> some View {
        let ink: Color = {
            switch tone {
            case .hot: return SweepRing.lamp(theme.palette.tint)
            case .grey: return SweepRing.blockedInk(theme: theme, dark: isDark)
            }
        }()
        return Capsule()
            .fill(ink)
            .frame(width: 20, height: 8)
            .accessibilityHidden(true)
    }

    private var isDark: Bool { (theme.scheme ?? systemScheme) == .dark }

    // MARK: The five sample segments

    /// Whole disk: an SSD of a common capacity.
    private var sampleTotal: Int64 { 512 * GB }
    /// Free tier = system-reported available (the sample has no "system purgeable" segment, so available equals free).
    private var sampleFree: Int64 { 168_300_000_000 }
    /// Used = whole disk minus free. The center lines and the five ring segments must be one ledger, so this number must be computed,
    /// not picked to "look reasonable"; picking would produce a chart whose segments don't sum to the label.
    private var sampleUsed: Int64 { sampleTotal - sampleFree }
    /// After this step: free + the three reclaimable segments. The sample has no Trash segment (see `sampleSegments` below),
    /// so "available after cleaning everything" is 168.3 + 42.4 + 33.8 + 27.5 = 272.0.
    private var sampleAfterClear: Int64 { sampleFree + 42_400_000_000 + 33_800_000_000 + 27_500_000_000 }

    /// Five sample segments. Names are all ones the product really shows (`App caches`/`Dev caches`/`Large files`/
    /// `Other counted`/`Free`), so the names this screen teaches need no relearning on the Overview page.
    ///
    /// `reclaim` is always 0: these segments reclaim nothing; giving a reclaimable amount would draw the "click me"
    /// inner warm edge and turn the cursor into a hand (see `SweepRing.ringHitLayer`); a sample ring inviting clicks would be deceptive.
    /// Coloring still uses `.hot`: the color says "this kind of thing is movable on a real disk", not "click here".
    ///
    /// No "moved to Trash this time" segment: a first-time user hasn't cleaned anything, so on a real disk this tier is necessarily 0;
    /// showing it in the sample invents an impossible state. It appears on the Overview page by itself after the first cleanup.
    private var sampleSegments: [GaugeSegment] {
        let lamp = SweepRing.lamp(theme.palette.tint)
        return [
            GaugeSegment(label: L("App Caches"), value: 42_400_000_000, color: lamp, tone: .hot),
            GaugeSegment(label: L("Dev Caches"), value: 33_800_000_000, color: lamp, tone: .hot),
            GaugeSegment(label: L("Large Files"), value: 27_500_000_000, color: lamp, tone: .hot),
            GaugeSegment(label: L("Other counted"), value: 240_000_000_000,
                         color: SweepRing.blockedInk(theme: theme, dark: isDark),
                         tone: .neutral),
            GaugeSegment(label: L("Free"), value: sampleFree,
                         color: SweepRing.freeInk(theme: theme, dark: isDark),
                         tone: .neutral),
        ]
    }

    // MARK: Sizes

    /// Left column gets 420, yielding proportionally on narrower windows. On narrow windows the ring shrinks too, no scrollbars.
    private func storyWidth(in size: CGSize) -> CGFloat {
        min(420, max(280, size.width * 0.42))
    }

    /// Ring diameter. The 260 floor isn't arbitrary: it's the gate for printing numbers on the arcs (`RingStyle.labelMinDiameter`);
    /// below it this screen degrades into "a small pie with no numbers", exactly what the previous version's minimum-window shot showed.
    /// The 320 ceiling: larger pushes the right column to the window edge while left-column text starts wrapping to a third line.
    private func ringDiameter(in size: CGSize) -> CGFloat {
        let room = size.height - 200
        let roomW = size.width - storyWidth(in: size) - 120
        return min(320, max(260, min(room, roomW)))
    }

    // MARK: Bottom actions

    /// Two exits: start (in the sandboxed build before authorization, that button is "Authorize home folder"), or later.
    /// Order follows macOS: default action on the far right, triggered by Return.
    private var actions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ThemeButton(kind: .ghost, title: L("Not now")) { prefs.finishFirstRun() }
            ThemeButton(kind: .primary,
                        symbol: grant.needsGrant ? "folder.badge.gearshape" : "magnifyingglass",
                        title: grant.needsGrant ? L("Grant home folder") : L("Look at this disk"),
                        shortcut: KeyboardShortcut(.return, modifiers: []),
                        action: start)
        }
    }

    /// Start using this disk.
    ///
    /// In the sandboxed build before authorization, this goes straight to authorization (same `NSOpenPanel`, sharing one `HomeGrant`
    /// with the screen drawn when Overview is blocked). **Don't dismiss this screen unless authorization succeeds**: the guide disappearing while
    /// the UI still shows no numbers would mean both screens vanish.
    private func start() {
        if grant.needsGrant {
            grant.request()
            guard !grant.needsGrant else { return }
        }
        prefs.finishFirstRun()
    }
}
