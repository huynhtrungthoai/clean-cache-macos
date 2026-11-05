import SwiftUI
import AppKit
import DiskCleanerCore

// ── Sandbox authorization ───────────────────────────────────────────────────────────────
//
// The sandboxed build can't "read ~/Library directly": Foundation's homeDirectoryForCurrentUser
// is rewritten to the app's own container; using it as a scan root doesn't error, it just quietly scans an empty shell
// and tells the user "there's almost nothing on your machine". So authorization must happen before any scan;
// without it the UI stays on this page and shows no numbers at all.
//
// We take the Apple-sanctioned route: NSOpenPanel lets the user pick the home folder themselves -> security-scoped
// bookmark is saved -> restore() resumes it on every later launch, without bothering the user again.

@MainActor
final class HomeGrant: ObservableObject {
    static let shared = HomeGrant()

    @Published private(set) var needsGrant = HomeAccess.needsGrant
    @Published var failure: String?

    func refresh() { needsGrant = HomeAccess.needsGrant }

    func request() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = L("Grant Access")
        panel.message = L("Your home folder is already selected — just press Grant Access. CleanPilot reads this one folder and nothing else.")
        panel.directoryURL = realHomeDir()

        guard panel.runModal() == .OK, let picked = panel.url else { return }
        if HomeAccess.grant(picked) {
            failure = nil
            refresh()
        } else {
            failure = L("That didn't take — try again.")
        }
    }

    /// Escape hatch for when the wrong folder was picked (e.g. an external drive).
    func revoke() {
        HomeAccess.revoke()
        refresh()
    }
}

struct HomeGrantView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var grant = HomeGrant.shared

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            ZStack {
                Circle().fill(theme.palette.tintSoft)
                    .frame(width: 76, height: 76)
                Image(systemName: "lock.badge.clock")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.palette.tint)
            }
            .accessibilityHidden(true)

            Text(L("No folder access yet"))
                .font(theme.display(.headline))
                .foregroundStyle(theme.palette.ink)

            Text(L("The App Store build can't browse your disk on its own. Point it at your home folder once and it never asks again."))
                .font(theme.bodyFont(.callout))
                .foregroundStyle(theme.palette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            ThemeButton(kind: .primary, symbol: "folder.badge.gearshape",
                        title: L("Grant home folder")) { grant.request() }

            if let failure = grant.failure {
                Text(failure)
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkSecondary)
            }

            Text(L("It reads only the folder you pick: no network, no uploads, and every delete goes to the Trash."))
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
