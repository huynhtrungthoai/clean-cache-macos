import SwiftUI

// ── Skin holder: selection / persistence / unlocking / try-on ────────────────────────────────
//
// "Can this skin be used" has a single decision point, `usable(_:unlocked:)` (compile-time switch + unlock records);
// `canUse(_:)` just feeds it the current unlocked set. To change the rule touch only these two; views stay untouched:
//   canUse(_:)  -- whether it can be used
//   unlock(_:)  -- how it gets recorded as usable

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published private(set) var current: Theme
    /// IDs of unlocked premium skins (only considered when `Channel.showsPricing` is true)
    @Published var unlockedPremiumIDs: Set<String> = []
    /// Skin ID being tried on: viewable and interactive, not written to preferences, reverts on switching away
    @Published private(set) var tryingID: String?
    /// Appearance mode: nil = follow system, otherwise forced
    @Published var forcedScheme: ColorScheme? {
        didSet {
            switch forcedScheme {
            case .some(.dark): defaults.set("dark", forKey: Keys.forcedScheme)
            case .some(.light): defaults.set("light", forKey: Keys.forcedScheme)
            default: defaults.removeObject(forKey: Keys.forcedScheme)
            }
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let selected = "diskcleaner.theme.id"
        /// Key used in v0.2 and earlier; migrated on upgrade
        static let legacySelected = "diskcleaner.skin.id"
        static let unlocked = "diskcleaner.theme.premium.unlocked"
        static let forcedScheme = "diskcleaner.theme.forcedScheme"
    }

    init() {
        let stored = defaults.string(forKey: Keys.selected)
        let saved = stored ?? defaults.string(forKey: Keys.legacySelected) ?? SkinCatalog.defaultSkin.id
        let migrated = SkinCatalog.migrateLegacyID(saved)
        let candidate = SkinCatalog.byID(migrated) ?? SkinCatalog.defaultSkin
        let unlocked = Set(defaults.stringArray(forKey: Keys.unlocked) ?? [])
        unlockedPremiumIDs = unlocked
        current = Self.usable(candidate, unlocked: unlocked) ? candidate : SkinCatalog.defaultSkin
        // Per-screen captures need dark/glass skins to check the window chrome, but preferences hold a light skin: provide an env var entry point.
        // Snapshot mode later calls `useForSnapshot(same id)` itself, so both sides resolve to the same look;
        // this branch covers the path "no DISKWISE_SHOTS, just double-click to open and inspect the chrome".
        if let forced = SnapshotMode.requestedSkinID, let skin = SkinCatalog.byID(forced) {
            current = skin
        }
        if let raw = defaults.string(forKey: Keys.forcedScheme) {
            forcedScheme = raw == "dark" ? .dark : (raw == "light" ? .light : nil)
        }
        if migrated != saved || stored == nil { defaults.set(migrated, forKey: Keys.selected) }
    }

    /// The effective skin: try-on takes precedence over the selection
    var effective: Theme {
        (tryingID.flatMap { SkinCatalog.byID($0) }) ?? current
    }

    /// The effective appearance: the app-level switch takes precedence over the skin's own
    var effectiveScheme: ColorScheme? {
        forcedScheme ?? effective.scheme
    }

    /// Whether usable: with the switch off everything passes; with it on, decided by tier + unlock records.
    static func usable(_ theme: Theme, unlocked: Set<String>) -> Bool {
        !Channel.showsPricing || theme.tier == .free || unlocked.contains(theme.id)
    }

    func canUse(_ theme: Theme) -> Bool {
        Self.usable(theme, unlocked: unlockedPremiumIDs)
    }

    @discardableResult
    func select(_ theme: Theme) -> Bool {
        guard canUse(theme) else { return false }
        tryingID = nil
        current = theme
        defaults.set(theme.id, forKey: Keys.selected)
        return true
    }

    /// Try-on: wear it first, then decide whether to keep it. Locked skins can't be selected directly, only tried on.
    func startTrying(_ theme: Theme) {
        guard theme.isPaid, !canUse(theme) else { return }
        tryingID = theme.id
    }

    func stopTrying() {
        tryingID = nil
    }

    /// Snapshot mode only: put the skin on directly without touching preferences.
    /// The skin page's "In use" badge reads `current`; injecting only the Theme into the renderer would
    /// draw Morning Mist while the badge points at the author's last pick: the badge would lie.
    func useForSnapshot(_ theme: Theme) {
        tryingID = nil
        current = theme
    }

    /// Record as unlocked: the current implementation simply allows it
    func unlock(_ theme: Theme) {
        unlockedPremiumIDs.insert(theme.id)
        defaults.set(Array(unlockedPremiumIDs), forKey: Keys.unlocked)
        tryingID = nil
        select(theme)
    }
}
