import SwiftUI
import AppKit

// ── Esc disarms ───────────────────────────────────────────────────────────────
//
// The overview's two-step confirm (first click arms, second click moves) promises three ways out: click elsewhere, switch segment,
// press Esc. The first two are mouse matters; the third needs someone to catch it. This layer is what catches it.
//
// **Why `NSEvent.addLocalMonitorForEvents` instead of `.onExitCommand`**:
// two things in the same window want Esc right now - the four cleanup-guide pages (which use `.onExitCommand`)
// and the freshly armed arc. The SwiftUI path goes through the first responder chain; who catches it first depends on which button
// focus happens to be on, and paging moves focus. The criterion can't rest on "it'll probably go to the modal layer first".
// Another hard constraint: macOS 13 has no `.onKeyPress` (that's 14+); pure SwiftUI at this layer
// can't even receive arrow keys, so pulling in AppKit for one Esc is actually cheaper.
//
// **Listen only, never swallow**: the callback always returns the event unchanged. If swallowed, the same window's
// `.onExitCommand` (closing the cleanup guide) would break too - both must be able to happen.
// So "disarm" and "close guide" aren't either/or: pressing Esc steps both back one.
//
// **Measured**: this is attached to the window background; in the same build, one overview shot each with it on/off
// (1280×852, dawn, demo data): both `01-overview.png` md5s match (`1f01a034…`) -
// a 0×0 receiver doesn't move a pixel, and the ring's md5 gate holds.
//
// **The unmeasured link**: the screenshot pipeline has no keyboard/mouse, so "does the monitor receive Esc once pressed"
// can only be trusted per AppKit's rules. The invoked action itself is already proven: `disarm()` renders exactly the 3.2 s
// auto-disarm (`01-overview-disarmed.png`), and Esc goes through the same entry point.

/// An invisible key receiver attached to the window background.
struct EscapeTap: View {
    /// Only called on the main thread (local monitor callbacks fire on the main run loop).
    let onEscape: () -> Void

    var body: some View {
        Host(onEscape: onEscape)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private struct Host: NSViewRepresentable {
        let onEscape: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView {
            context.coordinator.install(onEscape)
            return NSView(frame: .zero)
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            // On view rebuild the closure gets a new copy (it captures `scans`, which is a StateObject,
            // so it doesn't really change); swapping the pointer here is enough: the monitor is installed once, never reinstalled.
            context.coordinator.box.action = onEscape
        }

        /// The action lives in this outer layer rather than having the monitor callback capture `Coordinator`:
        /// capturing it forms a "coordinator -> token -> callback -> coordinator" cycle, `deinit` never fires,
        /// and the monitor stays in the system firing after the window is torn down.
        final class Box {
            var action: (() -> Void)?
        }

        final class Coordinator {
            let box = Box()
            private var token: Any?

            /// A local monitor fires only while the app is frontmost and the event enters our own responder chain - exactly the definition of
            /// "a person pressing Esc in this window". A global monitor needs Accessibility permission; we don't need it and shouldn't ask.
            func install(_ f: @escaping () -> Void) {
                // Pull it into a local before the closure: writing `box.action` directly in the closure captures `self` too,
                // looping back to the cycle described above.
                let box = self.box
                box.action = f
                guard token == nil else { return }
                token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
                    // 53 = esc. Read the key code, not the characters: ⌥Esc / ⇧Esc change the characters, the key code doesn't.
                    guard ev.keyCode == 53, let f = box.action else { return ev }
                    f()
                    return ev
                }
            }

            deinit { if let token { NSEvent.removeMonitor(token) } }
        }
    }
}
