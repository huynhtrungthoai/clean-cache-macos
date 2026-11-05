// Compare-page content (vs CleanMyMac / DaisyDisk / PureMac / Mole).
// Rule: the rival column only states claims from the rival's own site or docs, with a source;
// our column states architectural facts, no adjectives. Rows where we lose are marked edge:"theirs".
import type { Locale } from "@/data/content";
import { BREW_INSTALL, BREW_TAP } from "@/data/site";

export type CompareSlug = "cleanmymac" | "daisydisk" | "puremac" | "mole";

export interface CompareRow {
  dim: string;
  ours: string;
  theirs: string;
  edge: "ours" | "theirs" | "even";
}

export interface CompareContent {
  rival: string;
  /** Trademark / no-affiliation notice: nominative fair use, but it must appear on the page. */
  disclaimer: string;
  nav: { href: string; label: string }[];
  hero: { eyebrow: string; title: string; sub: string; verdict: string };
  quickAnswer: { q: string; a: string };
  table: { headers: [string, string, string]; rows: CompareRow[] };
  theirsStronger: { title: string; items: { t: string; d: string }[] };
  differences: { title: string; items: { t: string; d: string }[] };
  switchGuide: { title: string; note: string; steps: string[] };
  faq: { q: string; a: string }[];
  sources: { label: string; href: string }[];
  backHome: string;
  otherCompare: { slug: CompareSlug; label: string };
  updated: string;
}

export const COMPARE: Record<CompareSlug, Partial<Record<Locale, CompareContent>>> = {
  cleanmymac: {
    en: {
      rival: "CleanMyMac",
      disclaimer:
        "DiskWise is an independent open-source project. It is not affiliated with, authorised by, or sponsored by MacPaw, and does not speak for them. The CleanMyMac name and marks belong to their owner and are used here only to describe how the two products differ. Prices and descriptions come from their public pages and may have changed.",
      nav: [
        { href: "#diff", label: "Differences" },
        { href: "#table", label: "Side by side" },
        { href: "#switch", label: "Switching" },
        { href: "#install", label: "Install" },
        { href: "#faq", label: "FAQ" },
      ],
      hero: {
        eyebrow: "Comparison · Oct 2026",
        title: "DiskWise vs CleanMyMac",
        sub: "Both clear disk space. The real disagreement is two things: the deletion model, and whether you can audit it.",
        verdict:
          "If you want not to think about it at all, CleanMyMac has more modules, a bigger brand and support. If you want to know exactly what was removed, with every step reversible, DiskWise is the free and open-source one — and it deliberately ships no malware scan or one-click tune-up.",
      },
      quickAnswer: {
        q: "Is there a free alternative to CleanMyMac?",
        a: "Yes. DiskWise is free and open source (Apache-2.0): a native SwiftUI disk cleaner, about 8 MB, no telemetry, no subscription, and its Mac App Store build requests no network entitlement at all. Two structural differences: the only deletion path in DiskWise moves items to the Trash and stays undoable until you empty it, and CleanMyMac is closed source, so you cannot verify from outside which files a given scan touched.",
      },
      table: {
        headers: ["", "DiskWise", "CleanMyMac"],
        rows: [
          {
            dim: "Price",
            ours: "Free. Every feature unlocked, no upsell, no ads",
            theirs: "Subscription (~$40/yr), plus a pricier one-time licence",
            edge: "ours",
          },
          {
            dim: "Source",
            ours: "Apache-2.0 — you can read the deletion code itself",
            theirs: "Closed source",
            edge: "ours",
          },
          {
            dim: "Deletion model",
            ours: "The only exit is FileManager.trashItem: everything goes to the Trash, every row undoable for the whole session, emptying stays your call in Finder",
            theirs: "Doesn't publish per-item reversibility as a design constraint; closed source, so it can't be audited",
            edge: "ours",
          },
          {
            dim: "When space is actually freed",
            ours: "Only after you empty the Trash. That is the price of reversibility and we won't hide it",
            theirs: "Freed immediately on cleanup",
            edge: "theirs",
          },
          {
            dim: "Breadth",
            ours: "Disk only: ring overview, ledger detail, large & stale files, duplicates, uninstall leftovers, developer caches",
            theirs: "Cleanup + malware protection + privacy erasure + maintenance + tune-up",
            edge: "theirs",
          },
          {
            dim: "Background components",
            ours: "No updater, no analytics, no daemon; the App Store build declares no network entitlement",
            theirs: "Ships auto-update and licensing components",
            edge: "ours",
          },
          {
            dim: "Does it explain each cache",
            ours: "65 local knowledge-base entries shipped in the app: what it is, what removing it costs, how it grows back",
            theirs: "Shows categories and totals, not per-item cost",
            edge: "ours",
          },
          {
            dim: "Developer directories",
            ours: "node_modules, Xcode DerivedData, Docker usage and build artefacts are first-class",
            theirs: "Generic cache view",
            edge: "ours",
          },
        ],
      },
      theirsStronger: {
        title: "Where CleanMyMac genuinely is stronger",
        items: [
          {
            t: "Far more features",
            d: "Malware detection, privacy erasure, maintenance, tune-ups. DiskWise has none of those, deliberately: until disk cleanup is fully solved, adding modules only dilutes reliability.",
          },
          {
            t: "Space comes back instantly",
            d: "Its model frees bytes as it cleans. DiskWise waits for you to empty the Trash. If you need tens of GB back right now, that is their advantage.",
          },
          {
            t: "Brand, docs and support",
            d: "Years of reputation, real documentation, human support. DiskWise is a solo-maintained open-source project; the channels are GitHub Issues and email.",
          },
        ],
      },
      differences: {
        title: "There are really only two disagreements",
        items: [
          {
            t: "No permanent-delete code path exists",
            d: "Not \"we advise caution\" — the call simply isn't in the code. If the app misjudges a folder, your recovery is Finder, not a data-recovery service.",
          },
          {
            t: "Auditable, as a fact rather than a promise",
            d: "Public source, SHA-256 published per release, and the App Store build's entitlements visibly contain no network permission. You don't have to trust us.",
          },
          {
            t: "Per-row explanation, not one big number",
            d: "\"38.2 GB reclaimable\" tells you nothing about risk. A cache you re-download in a minute and a file with no second copy should not look the same in the list.",
          },
          {
            t: "$0",
            d: "There is no \"unlock deep cleaning\" button in DiskWise, and no tier. CleanMyMac's best features are not necessarily its priciest, but they are behind a licence.",
          },
        ],
      },
      switchGuide: {
        title: "Moving from CleanMyMac to DiskWise",
        note: "You don't have to pick one: DiskWise doesn't take over the system and won't conflict with an installed commercial cleaner.",
        steps: [
          "Don't just drag CleanMyMac to the Trash — use its own uninstall flow, or helper and login items stay behind.",
          "Install DiskWise and run uninstall-leftover detection against the bundle IDs of everything actually installed on the machine. It is built to miss orphans rather than over-delete.",
          "Open the Overview ring. If the Mac was already cleaned recently, the top segments will usually be developer caches and IM caches (WeChat, DingTalk and the like).",
          "Read each row before acting. One click arms it, the next moves it to the Trash; Undo puts it back exactly. Space returns the moment you empty the Trash.",
        ],
      },
      faq: [
        {
          q: "Can DiskWise fully replace CleanMyMac?",
          a: "No. If you want malware scanning, privacy erasure or one-click tune-ups, CleanMyMac has those modules and DiskWise does not. For \"see what is using the disk and remove it safely\", it replaces it — for free.",
        },
        {
          q: "Why route deletions through the Trash instead of just deleting?",
          a: "Because a cleaner that misjudges is an irreversible cost. Going through the Trash hands the last step back to you: until you empty it, everything can go home. The trade-off is stated plainly — no space comes back until you do.",
        },
        {
          q: "Is CleanMyMac safe?",
          a: "We won't make that call. What we can say is that it is closed source, so you cannot verify from outside which files a particular cleanup removed. That is exactly why DiskWise puts all of its logic in readable source.",
        },
        {
          q: "How does it update without network access?",
          a: "The App Store build updates through the store; Homebrew uses brew upgrade --cask; direct downloads publish a SHA-256 per release. The app itself never reaches out.",
        },
      ],
      sources: [
        { label: "CleanMyMac product page (pricing and modules)", href: "https://macpaw.com/cleanmymac" },
      ],
      backHome: "Back to the DiskWise home page",
      otherCompare: { slug: "daisydisk", label: "vs DaisyDisk" },
      updated: "October 2026",
    },
  },

  daisydisk: {
    en: {
      rival: "DaisyDisk",
      disclaimer:
        "DiskWise is an independent open-source project. It is not affiliated with, authorised by, or sponsored by the developers of DaisyDisk. The DaisyDisk name and marks belong to their owner and are used here only to describe how the two products differ; statements about how it removes files come from its own official guide (linked below). Pricing and features may have changed, and the two tools work fine side by side — this page is not a pitch to give yours up.",
      nav: [
        { href: "#diff", label: "Differences" },
        { href: "#table", label: "Side by side" },
        { href: "#switch", label: "Using both" },
        { href: "#install", label: "Install" },
        { href: "#faq", label: "FAQ" },
      ],
      hero: {
        eyebrow: "Comparison · Oct 2026",
        title: "DiskWise vs DaisyDisk",
        sub: "We lose on the map. The disagreement is deletion: by design it bypasses the Trash, and the Trash is the only path we have.",
        verdict:
          "DaisyDisk's ring is the benchmark for looking at a disk, and it's nicer for that. DiskWise is free and open source and answers the next question — \"can I delete this row, and what does it cost\" — with a deletion model that cannot permanently delete.",
      },
      quickAnswer: {
        q: "Is there a free alternative to DaisyDisk?",
        a: "DiskWise is free and open source (Apache-2.0), has its own ring overview, and adds cache semantics plus a cleanup flow on top. The decisive difference is documented by DaisyDisk itself: its guide states it does not move files to the system Trash \"because in that case, no disk space would actually be recovered\", so removals can't be undone. DiskWise's only deletion path is the Trash, undoable until you empty it — and the cost is that space returns only when you do.",
      },
      table: {
        headers: ["", "DiskWise", "DaisyDisk"],
        rows: [
          {
            dim: "Price",
            ours: "Free, every feature unlocked",
            theirs: "$9.99 one-time (not a subscription)",
            edge: "ours",
          },
          {
            dim: "Deletion model",
            ours: "The only exit is a move to the Trash; every row undoable for the session; emptying is your call",
            theirs: "Its guide: files are not moved to the system Trash, they are removed from disk, so undelete isn't possible",
            edge: "ours",
          },
          {
            dim: "Why they chose it",
            ours: "A cleaner that misjudges shouldn't be irreversible, so the last step stays with the human",
            theirs: "Their stated reason: a file parked in Trash on the same volume frees nothing",
            edge: "even",
          },
          {
            dim: "When space is actually freed",
            ours: "After you empty the Trash",
            theirs: "The instant you delete",
            edge: "theirs",
          },
          {
            dim: "Does it answer \"safe to delete?\"",
            ours: "65 shipped knowledge entries: what it is, what it costs, how it grows back",
            theirs: "Shows size and hierarchy; you judge what's safe",
            edge: "ours",
          },
          {
            dim: "Visualisation",
            ours: "Ring overview plus ledger-style in-place drill-down",
            theirs: "Years of polish; preview, grouping and filtering are smoother",
            edge: "theirs",
          },
          {
            dim: "How bytes are counted",
            ours: "Real on-disk usage (st_blocks × 512), so sparse files and APFS clones can't overstate what you'd reclaim",
            theirs: "File-size view",
            edge: "ours",
          },
          {
            dim: "Source",
            ours: "Apache-2.0, fully open; the App Store build declares no network entitlement",
            theirs: "Closed source",
            edge: "ours",
          },
        ],
      },
      theirsStronger: {
        title: "Where DaisyDisk genuinely is stronger",
        items: [
          {
            t: "The map is better",
            d: "Ring, preview, grouping and filtering have had years of polish. If all you want is to see a disk, DaisyDisk is the more comfortable tool.",
          },
          {
            t: "Deletions take effect at once",
            d: "It skips the Trash, so space comes back immediately. DiskWise routes through the Trash, so you do one more step — and genuinely get to change your mind. That's a trade, not an oversight.",
          },
          {
            t: "One-time purchase",
            d: "$9.99 for life, not a subscription. For commercial software that's fair; DiskWise is just $0.",
          },
        ],
      },
      differences: {
        title: "Where they part ways",
        items: [
          {
            t: "A cleaner that structurally can't delete",
            d: "There is no permanent-delete call in DiskWise's code. DaisyDisk's own guide says removals skip the system Trash, so a mistake leaves data recovery as the only exit.",
          },
          {
            t: "From \"see it\" to \"dare to act\"",
            d: "Knowing a folder is 28 GB and knowing whether those 28 GB are safe to remove — and how long they take to grow back — are different questions. DiskWise ships the second answer as data.",
          },
          {
            t: "The numbers reconcile",
            d: "Measured on-disk usage rather than apparent size, so APFS clones and sparse files don't report space you can't actually reclaim. Segments sum to the whole disk.",
          },
          {
            t: "Free and auditable",
            d: "Open source, SHA-256 per release, no network permission in the store build. You don't need to believe any of this.",
          },
        ],
      },
      switchGuide: {
        title: "Use both, or move over",
        note: "DaisyDisk is a one-time purchase, so there's no \"paying for a subscription I'm not using\" problem. Running both is reasonable.",
        steps: [
          "Side by side: DaisyDisk to look, DiskWise to act. Neither takes over the system.",
          "Anything already removed with DaisyDisk is gone. For the next sweep, run it through DiskWise's Trash first and empty it once you're satisfied.",
          "DiskWise's ring is segmented by bytes measured in this scan, summing to the whole disk — you can reconcile it against DaisyDisk's reading.",
          "Duplicates, uninstall leftovers, node_modules / DerivedData / Docker: the parts DaisyDisk doesn't judge for safety are the rows DiskWise carries semantics for.",
        ],
      },
      faq: [
        {
          q: "Does DaisyDisk permanently delete?",
          a: "Yes, by design. Its guide states it doesn't move files to the system Trash because that would free no space, and that removed items cannot be undeleted — its recovery advice is to stop using the Mac immediately to avoid overwriting, or hire a data-recovery service.",
        },
        {
          q: "Why doesn't DiskWise do the same?",
          a: "Because when \"free up space\" and \"don't lose a file\" conflict, we pick the second — and we print the cost: until you empty the Trash, the space isn't back.",
        },
        {
          q: "Whose ring is more accurate?",
          a: "Different measurement. DiskWise counts real on-disk usage (st_blocks × 512), so sparse files and APFS clones can't overstate the reclaimable amount; every arc is bytes measured in the current scan and the segments sum to the whole disk.",
        },
        {
          q: "Can DiskWise be a free DaisyDisk?",
          a: "For looking at a disk, yes, and it leans developer: node_modules, DerivedData, Docker usage, build artefacts and WeChat/DingTalk-style caches are all in the semantic list. Its map interaction is less polished than DaisyDisk's, and we won't pretend otherwise.",
        },
      ],
      sources: [
        { label: "DaisyDisk official guide · Deleting files", href: "https://daisydiskapp.com/guide/4/en/DeletingFiles/" },
        { label: "DaisyDisk official guide · Undeleting files", href: "https://daisydiskapp.com/guide/4/en/Undelete/" },
      ],
      backHome: "Back to the DiskWise home page",
      otherCompare: { slug: "cleanmymac", label: "vs CleanMyMac" },
      updated: "October 2026",
    },
  },
  puremac: {
    en: {
      rival: "PureMac",
      disclaimer:
        "DiskWise is an independent open-source project with no affiliation, endorsement, or sponsorship from PureMac or its author. All descriptions come from PureMac's public repository page and may have changed.",
      nav: [
        { href: "#diff", label: "Differences" },
        { href: "#table", label: "Head-to-head" },
        { href: "#switch", label: "Switching" },
        { href: "#install", label: "Install" },
        { href: "#faq", label: "FAQ" },
      ],
      hero: {
        eyebrow: "Compare · 2026-10",
        title: "DiskWise vs PureMac",
        sub: 'Both are free, open-source SwiftUI cleaners. The real disagreement is a single row: whether "never permanently deletes" is an architectural constraint.',
        verdict:
          "If you want the wider suite (10-level app uninstaller, system checks, scheduled cleaning, a CLI), PureMac ships fast — 30 releases in six months. If you want the certainty that every cleanup action lands in the Trash and stays undoable, DiskWise is the one that wrote that into the architecture. We would rather ship fewer features than introduce a permanent-delete path.",
      },
      quickAnswer: {
        q: "What is the difference between PureMac and DiskWise?",
        a: 'Both are free, open-source, native SwiftUI, signed and notarized, zero telemetry. The core difference is the deletion model: PureMac\'s own README states that app uninstalls go through the Trash, but scheduled auto-clean, category cleanup, Trash emptying, Docker/Xcode runtime cleanup, snapshot deletion and CLI cleanup "can permanently delete data". DiskWise\'s only delete path moves everything to the Trash, undoable per item for the whole session — no category of operation bypasses it. In exchange, PureMac has a wider feature set and a CLI that covers its own cleanup categories.',
      },
      table: {
        headers: ["Dimension", "DiskWise", "PureMac"],
        rows: [
          { dim: "Price", ours: "Free, Apache-2.0, no IAP, no ads", theirs: "Free, MIT, no IAP, no ads", edge: "even" },
          {
            dim: "Deletion model",
            ours: "One exit only — FileManager.trashItem: every operation lands in the Trash, per-item Undo for the whole session, emptying stays Finder's job",
            theirs: 'Per its README\'s "Our promise": app uninstalls/orphans/duplicates use the Trash; scheduled auto-clean, category cleanup, Trash emptying, Docker/Xcode runtime cleanup, snapshot deletion and CLI cleanup can permanently delete data',
            edge: "ours",
          },
          {
            dim: "Feature breadth",
            ours: "Deliberately disk-only: ring overview, cache knowledge base, duplicates, leftovers, large files",
            theirs: "A suite: Smart Care, 10-level app uninstaller, storage exploration, system checks, scheduled auto-clean, CLI",
            edge: "theirs",
          },
          {
            dim: "Per-cache explanations",
            ours: "Knowledge base states what each cache is, what deletion costs, how it comes back; WeChat/DingTalk/WeCom covered",
            theirs: "Promises honest scans and neutral presentation; per-entry explanations not listed as a feature",
            edge: "ours",
          },
          { dim: "Maturity", ours: "Released 2026-10, v2.2", theirs: "Released 2026-04, 30 releases in six months, 6,900+ stars", edge: "theirs" },
          { dim: "Languages", ours: "10 UI languages, 4-language README", theirs: "8-language README (Arabic first)", edge: "even" },
          { dim: "Signing & distribution", ours: "Developer ID signed + notarized; brew cask / DMG / App Store", theirs: "Signed + notarized; GitHub Release", edge: "even" },
        ],
      },
      theirsStronger: {
        title: "Where PureMac is stronger",
        items: [
          { t: "Wider feature set", d: "10-level matching uninstaller, system checks, storage exploration, scheduled cleaning — DiskWise deliberately stays narrower." },
          { t: "Faster iteration, more mature", d: "30 releases in six months, 6,900+ stars and 380+ forks of community validation." },
          { t: "More cleanup categories in the CLI", d: "PureMac's CLI covers its own full set of cleanup categories; DiskWise's `diskwise` command line (bundled with the direct-download build, not the App Store build) covers only the cache and developer locations the knowledge base knows and rates safe, and always goes through a plan first with per-item revalidation." },
        ],
      },
      differences: {
        title: "The real disagreement",
        items: [
          { t: "Deletion model", d: 'DiskWise makes "everything to the Trash" an architectural constraint — including unattended scenarios like scheduled cleaning: either it does not exist, or it also goes through the Trash. PureMac makes it a per-category promise, and the automated categories permanently delete.' },
          { t: "Product philosophy", d: 'PureMac builds a "Mac care suite"; DiskWise does one thing — the disk — so you never have to ask whether it is safe to let it clean unattended.' },
        ],
      },
      switchGuide: {
        title: "Switching from PureMac",
        note: "Both are free — you can install DiskWise alongside and compare, no uninstall needed.",
        steps: [
          `Run ${BREW_TAP}, then ${BREW_INSTALL} — or get DiskWise from the App Store`,
          "Open Overview to see the whole-volume ring; click any row for its subfolder ledger",
          "Delete one cache: two taps to the Trash, ⌘Z to undo; emptying stays Finder's job",
          "Compare what each reports, keep the one you trust",
        ],
      },
      faq: [
        { q: "Both are open-source cleaners — which one?", a: "Scheduled auto-clean and a wider suite: PureMac. The certainty that every action is reversible: DiskWise. Both are free, so comparing costs nothing." },
        { q: "Will DiskWise add scheduled auto-clean?", a: "Only if the cleaning action itself goes to the Trash — otherwise it conflicts with our architectural promise. No timeline." },
      ],
      sources: [
        { label: "PureMac repository (Our promise / How it compares)", href: "https://github.com/momenbasel/PureMac" },
        { label: "DiskWise repository", href: "https://github.com/DreamOfXM/diskwise" },
      ],
      backHome: "Back to DiskWise",
      otherCompare: { slug: "mole", label: "vs Mole" },
      updated: "October 2026",
    },
  },
  mole: {
    en: {
      rival: "Mole",
      disclaimer:
        "DiskWise is an independent open-source project with no affiliation, endorsement, or sponsorship from Mole or its author. All descriptions come from Mole's public pages and may have changed.",
      nav: [
        { href: "#diff", label: "Differences" },
        { href: "#table", label: "Head-to-head" },
        { href: "#switch", label: "Switching" },
        { href: "#install", label: "Install" },
        { href: "#faq", label: "FAQ" },
      ],
      hero: {
        eyebrow: "Compare · 2026-10",
        title: "DiskWise vs Mole",
        sub: "Two shapes on the same starting line: terminal efficiency versus visible certainty.",
        verdict:
          "If you live in the terminal and want one command to fix things, Mole's free, open-source CLI is the real deal with a stellar reputation. If what you want is a GUI where you see the whole disk, delete in two clicks, and undo everything — free and open source — that is the half DiskWise does, and it ships a knowledge-base-only command line alongside it.",
      },
      quickAnswer: {
        q: "Mole's free CLI or DiskWise?",
        a: 'It is about the shape of the interaction. Mole\'s strength is the terminal: one command, scriptable, remote-friendly — the CLI is free and open source; its native GUI app is a separate paid, closed-source product. DiskWise\'s primary shape is the GUI: whole-volume ring, two taps to the Trash, per-item undo, every feature free and open source (Apache-2.0). The direct-download build also ships a `diskwise` command line and MCP server (the App Store build does not), but it only touches locations the knowledge base knows and rates safe, and always goes through a plan first. On deletion, DiskWise makes "everything to the Trash" an architectural constraint; for the CLI tool\'s behavior, its official docs are the source of truth.',
      },
      table: {
        headers: ["Dimension", "DiskWise", "Mole"],
        rows: [
          { dim: "Price", ours: "Free, fully open source (Apache-2.0)", theirs: "CLI free and open source; native GUI app is paid and closed source", edge: "ours" },
          { dim: "Interaction", ours: "Native SwiftUI GUI: ring map + ledger, two clicks; the direct-download build adds a diskwise CLI and MCP server", theirs: "Terminal TUI: one command, script-friendly", edge: "even" },
          { dim: "Deletion model", ours: "One exit only — FileManager.trashItem: everything to the Trash, per-item Undo for the session", theirs: "Cleans by executing commands directly (see its docs)", edge: "ours" },
          { dim: "Best for", ours: "People who want to see before they delete; safe to install for parents and colleagues", theirs: "Developers who live in the terminal", edge: "even" },
          { dim: "Community maturity", ours: "Released 2026-09, new project", theirs: "60k+ stars, thoroughly community-validated", edge: "theirs" },
          { dim: "Knowledge base", ours: "Every cache entry explains what it is, what deletion costs, how it comes back", theirs: "Known for cleaning power; per-entry explanations not listed as a feature", edge: "ours" },
        ],
      },
      theirsStronger: {
        title: "Where Mole is stronger",
        items: [
          { t: "Terminal efficiency", d: "One command frees tens of GB — scriptable and remote-friendly. DiskWise's command line insists on a plan first and only touches knowledge-base-approved safe locations, so it is less free-form to script against." },
          { t: "Community and reputation", d: "60k+ stars and viral word of mouth, battle-tested." },
          { t: "Monitoring", d: "Beyond cleaning it analyzes and monitors — wider coverage." },
        ],
      },
      differences: {
        title: "The real disagreement",
        items: [
          { t: "Form decides the trust model", d: "A terminal tool earns trust through transparent commands; a GUI has to earn it by not lying to you. DiskWise earns it with measured-bytes ring mapping and Trash-level undoability." },
          { t: "What the GUI costs and whether it is open", d: "Mole's GUI app is paid and closed source; DiskWise's GUI is free and open source (Apache-2.0), readable end to end." },
        ],
      },
      switchGuide: {
        title: "From Mole CLI to DiskWise",
        note: "Not a replacement: terminal people can keep both — DiskWise adds the visible half.",
        steps: [
          `Run ${BREW_TAP}, then ${BREW_INSTALL}`,
          "Open Overview — the ring and ledger are the graphical counterpart of Mole's numbers",
          "Send one cache to the Trash with two clicks, then ⌘Z it back",
          "Keep using Mole when you need scripting — that's fine",
        ],
      },
      faq: [
        { q: "Mole is so good — why build DiskWise?", a: 'They cover different halves. Mole\'s strength is the terminal, and its GUI app is paid and closed source. DiskWise is for people who do not live in a terminal: see the whole disk, delete in two clicks, undo anything, with the entire chain free and open source. CleanMyMac is the third option — pricey and closed.' },
        { q: "Does DiskWise have a CLI?", a: "Yes. The direct-download build ships a diskwise command line (scan / explain / plan / trash / undo / history) that also runs as an MCP server for Claude Code, Cursor, Codex and similar clients; the App Store build does not include it. It will never introduce a delete path that bypasses the Trash." },
      ],
      sources: [
        { label: "Mole repository", href: "https://github.com/tw93/Mole" },
        { label: "DiskWise repository", href: "https://github.com/DreamOfXM/diskwise" },
      ],
      backHome: "Back to DiskWise",
      otherCompare: { slug: "puremac", label: "vs PureMac" },
      updated: "October 2026",
    },
  },
};

/** Compare pages exist in English only; ja/ko fall back to en. */
export function compareContent(slug: CompareSlug, locale: Locale): CompareContent {
  const entry = COMPARE[slug];
  return (entry[locale] ?? entry.en) as CompareContent;
}

// Compare pages are English-only and live at the root for every locale.
export function compareHref(_locale: Locale, slug: CompareSlug): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, "");
  return `${base}/vs/${slug}/`;
}

/** Rival name in the home-page market table -> compare page. Names are the same Latin string in every locale, so map by name. */
export const COMPARE_SLUG_BY_NAME: Record<string, CompareSlug> = {
  CleanMyMac: "cleanmymac",
  DaisyDisk: "daisydisk",
  PureMac: "puremac",
  "Mole CLI (tw93)": "mole",
};
