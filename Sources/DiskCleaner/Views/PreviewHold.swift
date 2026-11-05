import SwiftUI
import AppKit

// ── Hold Space: preview "after emptying everything" ────────────────────────────────────────────
//
// That whole block of mockup 3 (items 6/10/11/12 on the mockup) says one thing: **hold** Space and the screen switches from
// "how much can be reclaimed now" to "how much is left after reclaiming it all"; release and it goes back. It's not another button
// but a reading mode that exists only while you hold it - so it needs a receiver that **gets keyUp**.
//
// Why `NSEvent.addLocalMonitorForEvents` instead of `.keyboardShortcut(.space)`:
// shortcuts only have keyDown, no notion of "release"; SwiftUI only gets `.onKeyPress` in macOS 14,
// and this layer must catch both press and release. Same reasoning as `EscapeTap.swift` (the Esc one).
//
// **This one swallows events, unlike `EscapeTap`**. Esc can't be swallowed because the same window has
// `.onExitCommand` waiting on that key; Space is different - left alone it would **press the currently focused
// button** (AppKit rule: Space = press the default/focused button), and the buttons on this screen are
// "Move to Trash". Previewing "after emptying everything" while actually moving things to the Trash is the one thing
// this layer must never let through. So the keyDown that hits Space returns nil.
//
// The two cases we yield on are checked before yielding:
// 1. Focus is in a text field (feedback page, path input) - Space is content, not a command;
// 2. With ⌘/⌥/⌃/⇧ - that's someone else's combo (⌥Space types a non-breaking space), not this mode.
//
// **Measured vs. not**: the preview mode's **visuals** have stills (`DISKWISE_RING=preview` goes through the real
// entry `holdPreview()`, then `previewoff` goes through `endPreview()` to shoot the clean exit,
// see `01-overview-preview.png` / `01-overview-previewback.png`); its **cost** also has paired
// measurements (`DISKWISE_PREVIEW=on` pins this mode for the whole run). Only one link is unmeasured: "does the
// monitor receive Space once pressed" - the screenshot pipeline has no keyboard/mouse, and this machine has no Accessibility grant to synthesize keys
// (same limitation noted in `EscapeTap`). So the key itself can't be proven in this environment; a human has to press it once.

/// An invisible Space receiver attached to the window background: hold = enter preview, release = revert.
struct SpaceHoldTap: View {
    let onHold: () -> Void
    let onRelease: () -> Void

    var body: some View {
        Host(onHold: onHold, onRelease: onRelease)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private struct Host: NSViewRepresentable {
        let onHold: () -> Void
        let onRelease: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView {
            context.coordinator.install(onHold: onHold, onRelease: onRelease)
            return NSView(frame: .zero)
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.box.swap(onHold: onHold, onRelease: onRelease)
        }

        /// The action lives in this outer layer, same reason as `EscapeTap`: a callback capturing `Coordinator` directly forms a cycle,
        /// `deinit` doesn't fire, and the monitor keeps firing in the system after the window is torn down.
        final class Box {
            var hold: (() -> Void)?
            var release: (() -> Void)?
            func swap(onHold: @escaping () -> Void, onRelease: @escaping () -> Void) {
                hold = onHold
                release = onRelease
            }
        }

        final class Coordinator {
            let box = Box()
            private var token: Any?

            func install(onHold: @escaping () -> Void, onRelease: @escaping () -> Void) {
                let box = self.box
                box.swap(onHold: onHold, onRelease: onRelease)
                guard token == nil else { return }
                token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { ev in
                    guard ev.keyCode == 49, Self.freeSpace(ev) else { return ev }
                    if ev.type == .keyDown {
                        // Holding it down auto-repeats: entering preview on every repeat means a full-page change every 30 ms.
                        // Treat only the first as real; swallow the rest.
                        if !ev.isARepeat, let f = box.hold { f() }
                        return nil
                    }
                    box.release?()
                    return ev
                }
            }

            /// Whether this Space belongs to this mode: no modifiers, and focus not in a text field.
            private static func freeSpace(_ ev: NSEvent) -> Bool {
                if ev.modifierFlags.intersection([.command, .option, .control, .shift]) != [] {
                    return false
                }
                // The check reads the class name rather than `r is NSTextView`: AppKit's field editor (the one that
                // actually takes keystrokes while typing) isn't always the responder-chain object called NSTextView,
                // and its host and SwiftUI `TextField`'s host both have one of these two substrings in the class name.
                // Matching names covers one more case than matching inheritance, and written here it's visible and easy to see through if wrong.
                if let r = ev.window?.firstResponder {
                    let name = NSStringFromClass(type(of: r))
                    if name.contains("TextView") || name.contains("FieldEditor") { return false }
                }
                return true
            }

            deinit { if let token { NSEvent.removeMonitor(token) } }
        }
    }
}
