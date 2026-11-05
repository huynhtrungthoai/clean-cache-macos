import Foundation

// ── Brand: one name, the same in every language ──
//
// The brand name is not in the string table - "DiskWise" stays DiskWise in every UI language.
// Bundle ID is CleanPilot's own (it used to reuse upstream DiskWise's `com.dreamofxm.diskcleaner`,
// sharing prefs/TCC grants with that app). `legacyBundleID` is only read once to migrate prefs
// (see `migrateLegacyDefaults`); Full Disk Access / Automation must be granted again once.

enum Product {
    /// Display name in the UI
    static let name = "CleanPilot"
    /// Artifact file name: pure ASCII, keeps GitHub Release / DMG / download paths simple
    static let fileName = "CleanPilot"
    static let bundleID = "com.huynhtrungthoai.cleanpilot"
    static let legacyBundleID = "com.dreamofxm.diskcleaner"
}

// ── Feedback channels: addresses live only here ──
//
// All public addresses (the same ones as in the README), so they're not in the string table and not localized.
// The app is offline; every channel must be initiated by the user. The page only lays out the addresses clearly and keeps them copyable.

enum Contact {
    /// GitHub owner/repo; this exact string is what the UI shows
    static let repoSlug = "huynhtrungthoai/clean-cache-macos"
    static let repo = "https://github.com/\(repoSlug)"
    static let issues = "https://github.com/\(repoSlug)/issues"
    /// Private vulnerability reports (GitHub Security Advisories), never public issues
    static let securityAdvisory = "https://github.com/\(repoSlug)/security/advisories/new"
}

// ── Distribution channel ──
//
// `CHANNEL=appstore bash build_app/build.sh` adds `-DAPPSTORE`: the Mac App Store requires the sandbox,
// and certificates and artifact formats differ from direct distribution (the two certificates are not interchangeable).
//
// `showsPricing` is separate: it only decides whether "skins grouped by availability + unlock entry" render. Both channels are currently
// false: all six skins are available, `Theme.tier` plays no part, and no unlock entry is rendered.

enum Channel {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    static let showsPricing = false
}
