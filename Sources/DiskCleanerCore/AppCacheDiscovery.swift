import Foundation

// ── C9: per-app caches in ~/Library/Caches (owner request 2026-11-06: "more like CleanMyMac") ──
//
// The knowledge base names a few dozen locations; CleanMyMac's "user cache files" are every app's
// folder in ~/Library/Caches. We add those, but only where the owner app is known, so the
// running-app check (quit or skip) can protect them:
//   - folders named by bundle ID (`com.vendor.App`), and
//   - a short alias table for browsers that use a plain name (`Google/Chrome`, `Firefox`, …).
// Never added: Apple's own caches (`com.apple.*`, system services), folders the knowledge base
// already describes (dev caches stay on their own page), and apps known to keep user content in
// Caches. Deletion still goes through the unchanged deletion gate and bulk-select rule.

/// One discovered per-app cache folder.
public struct DiscoveredAppCache: Equatable, Sendable {
    public let url: URL
    public let bundleID: String
}

/// Plain-named cache folders whose owner is known (relative to ~/Library/Caches).
public let appCacheAliases: [(rel: String, bundleID: String)] = [
    ("Google/Chrome", "com.google.Chrome"),
    ("Google/Chrome Beta", "com.google.Chrome.beta"),
    ("Firefox", "org.mozilla.firefox"),
    ("Microsoft Edge", "com.microsoft.edgemac"),
    ("BraveSoftware/Brave-Browser", "com.brave.Browser"),
]

/// Bundle IDs (lowercased) never swept: their "cache" holds content the user would have to
/// download again (offline music, synced media) or belongs to us.
public let appCacheDenylist: Set<String> = [
    "com.spotify.client",
    "com.huynhtrungthoai.cleanpilot",
]

/// Reverse-DNS shaped: at least two dots-separated labels, no spaces, no extension-like tail.
public func isBundleIDShaped(_ name: String) -> Bool {
    guard !name.hasPrefix("."), !name.contains(" "), !name.contains("/") else { return false }
    let labels = name.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
    let tail = labels.last!.lowercased()
    return !["plist", "db", "sqlite", "log", "json", "cache", "tmp"].contains(tail)
}

/// Per-app cache folders under `cachesDir` (default `~/Library/Caches`), sorted by path.
/// `knownPaths` are the knowledge base's resolved paths: any folder equal to, inside, or
/// containing one of them is left to that entry.
public func discoverAppCaches(cachesDir: URL = homeDir().appendingPathComponent("Library/Caches"),
                              knownPaths: [String]) -> [DiscoveredAppCache] {
    let fm = FileManager.default
    let base = cachesDir.standardizedFileURL
    let known = knownPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    func related(_ p: String) -> Bool {
        known.contains { $0 == p || $0.hasPrefix(p + "/") || p.hasPrefix($0 + "/") }
    }
    func isRealDir(_ u: URL) -> Bool {
        guard let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return v.isDirectory == true && v.isSymbolicLink != true
    }
    var out: [DiscoveredAppCache] = []
    let names = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
    for name in names where isBundleIDShaped(name) {
        let id = name.lowercased()
        if id.hasPrefix("com.apple.") || appCacheDenylist.contains(id) { continue }
        let u = base.appendingPathComponent(name)
        guard isRealDir(u), !related(u.path) else { continue }
        out.append(DiscoveredAppCache(url: u, bundleID: name))
    }
    for alias in appCacheAliases {
        let u = base.appendingPathComponent(alias.rel)
        guard isRealDir(u), !related(u.path) else { continue }
        out.append(DiscoveredAppCache(url: u, bundleID: alias.bundleID))
    }
    return out.sorted { $0.url.path < $1.url.path }
}

/// Tag carried by synthesized entries, so the UI and the size floor can tell them apart.
public let discoveredCacheTag = "discovered_app_cache"

/// Discovered rows smaller than this are not listed: a hundred 40 KB rows bury the real ones.
public let discoveredCacheFloor: Int64 = 1_000_000

/// A knowledge-base-shaped entry for a discovered folder. `name` is the app's display name
/// (the caller resolves it; the bundle ID when the app is gone). Copy keys are localized.
public func discoveredCacheEntry(_ d: DiscoveredAppCache, name: String) -> SafetyEntry {
    SafetyEntry(name: name,
                what: "Cache files this app keeps to load faster",
                whatif: "The app rebuilds them when needed; it may be a little slower the first time",
                rec: "No action needed; the app recreates them automatically",
                path: d.url.path, level: "safe", cost: nil, grp: "general", docs: nil,
                app: d.bundleID, tags: [discoveredCacheTag], icon: nil)
}
