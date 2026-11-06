import AppKit
import DiskCleanerCore

// ── Menu bar capacity readout (mockup 3) ──────────────────────────────────────────
//
// Data comes the same way as the window title bar's `VolumeChip`: one `volumeUsage()` call,
// then every 5 seconds; no separate source. The mockup's criterion is "menu bar and window read the same in the same second" -
// two data paths drift apart sooner or later, and a tool like this sells trustworthy numbers.
//
// Not persistent: the status item lives with the process; if the app isn't open, it isn't there. The second toggle on mockup 1's screen
// (launch at login) is the only way to carry it past a reboot.
// When usage can't be measured, show only the icon, no number: writing 0 falsely claims "this disk is empty", and writing "unknown" spends a slot
// on something that hasn't happened - same policy as the sidebar's capacity column.

@MainActor
final class MenuBar: NSObject {
    static let readout = MenuBar()

    private var item: NSStatusItem?
    private var timer: Timer?

    override init() {}

    func apply(shows: Bool) {
        shows ? install() : remove()
    }

    private func install() {
        guard item == nil else { refresh(); return }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "internaldrive",
                                   accessibilityDescription: L("Available"))
            button.imagePosition = .imageLeading
            button.font = NSFont.menuFont(ofSize: 0)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        status.menu = menu
        item = status
        refresh()
        let t = Timer(timeInterval: 5, repeats: true) { _ in
            Task { @MainActor in MenuBar.readout.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func remove() {
        timer?.invalidate()
        timer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        self.item = nil
    }

    private func refresh() {
        guard let item, let menu = item.menu else { return }
        let usage = volumeUsage()
        item.button?.title = usage.map { " " + human($0.available) } ?? ""
        menu.removeAllItems()
        if let u = usage {
            menu.addItem(Self.info(LF("Disk %1$@ · %2$@ used", human(u.total), human(u.used))))
            menu.addItem(Self.info(LF("%@ free", human(u.available))))
        }
        menu.addItem(.separator())
        let system = ProcessInfo.processInfo
        menu.addItem(Self.info(LF("Installed RAM: %@", human(Int64(system.physicalMemory)))))
        menu.addItem(Self.info(LF("Processor: %d logical cores", system.processorCount)))
        let version = system.operatingSystemVersion
        menu.addItem(Self.info("macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"))
        menu.addItem(Self.info(LF("Thermal state: %@", thermalStateText)))
        menu.addItem(.separator())
        let open = NSMenuItem(title: Product.name, action: #selector(focusMain), keyEquivalent: "")
        open.target = self
        open.isEnabled = true
        menu.addItem(open)
        let quit = NSMenuItem(title: LF("Quit %@", Product.name), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        menu.addItem(quit)
    }

    // macOS thermal pressure is qualitative, not a temperature sensor reading.
    private var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return L("Nominal")
        case .fair: return L("Elevated")
        case .serious: return L("Serious")
        case .critical: return L("Critical")
        @unknown default: return L("Unknown")
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private static func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// If a window exists, bring it to the front; if none exists, just activate the app
    /// and let the system fill in on Dock-icon click - we don't build a window here or call private selectors.
    @objc private func focusMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
