import Foundation

// ── Navigation history (what the Back step relies on) ──────────────────────────
//
// The only thing in "Back" that can go wrong is **deduplication**.
//
// When the user walks back with "Up one level" on the drill-down page, the parent is already in history. Appending
// that step as a new stop turns history into "…parent, child, parent", and Back jumps into the child again, looping forever.
// So the rule: if the destination was already recorded, return to it and drop everything after it; append only if new.
//
// This rule is UI-independent, so it lives in Core and is pinned case by case by the self-test, not left to the UI.
//
// Elements are generic: this only handles order and dedup, it doesn't know what a "page" or "directory" is; that's the UI's job.
// The stack **always holds at least one stop**, and `current` is the screen right now; without this invariant
// the stack bottom would be empty after the first hop and Back would land on no page.

public struct NavStack<Stop: Equatable> {
    public private(set) var stops: [Stop]

    public init(first stop: Stop) {
        stops = [stop]
    }

    /// Whether we can still go back. Not when only one stop remains.
    public var canGoBack: Bool { stops.count > 1 }

    /// The current stop.
    public var current: Stop { stops[stops.count - 1] }

    /// The previous stop. The Back button's caption shows its name; nil when there is none.
    public var previous: Stop? { canGoBack ? stops[stops.count - 2] : nil }

    /// Push a stop.
    ///
    /// Returns "whether the position actually moved": false if already on top. The view uses this to decide whether
    /// to re-measure that level; clicking the same place twice should not rescan.
    @discardableResult
    public mutating func arrive(_ stop: Stop) -> Bool {
        if let i = stops.lastIndex(of: stop) {
            guard i < stops.count - 1 else { return false }
            stops.removeSubrange((i + 1)...)
        } else {
            stops.append(stop)
        }
        return true
    }

    /// Step back; returns the stop we land on. Does nothing and returns nil when only one stop remains.
    @discardableResult
    public mutating func pop() -> Stop? {
        guard canGoBack else { return nil }
        stops.removeLast()
        return stops[stops.count - 1]
    }

    /// "Root" entry: collapses history to just this stop, so Back becomes unavailable.
    ///
    /// Clicking the sidebar or the first breadcrumb is **choosing a new destination**, not a step down.
    /// Recording those would make Back on the Caches page jump to the Large Files page, which nobody wants.
    public mutating func reset(to stop: Stop) {
        stops = [stop]
    }
}
