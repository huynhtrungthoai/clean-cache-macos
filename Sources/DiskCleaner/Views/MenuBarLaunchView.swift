import SwiftUI
import DiskCleanerCore

// ── Menu bar & launch page (the new screen from mockup 1) ──────────────────────────────────────
//
// This screen has just two toggles; it's where ⌘, should land. Mockup 1 says scan scope, units, language and the like
// come in only when there's a real need; no pre-placed empty slots - so we don't lay out a knock-off of System Settings here.
//
// The two notes under the rows use small inkTertiary gray text, no accent or warning color:
// cross-skin rule #1, body text is not tinted; and neither toggle is "something that can be moved".

struct MenuBarLaunchView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(symbol: "gearshape.2",
                           title: L("Menu Bar & Launch"),
                           subtitle: L("Where to find CleanPilot when no window is open"),
                           variant: .display)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switches
                        diagnostics
                        footnote
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    // Same width as the feedback page: two toggles plus a note, stretched into a banner, reads like settings for all of macOS
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .themedList()
            }
            .pagePadding()
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Two toggles

    private var switches: some View {
        VStack(spacing: 0) {
            SwitchLine(title: L("Show free space in the menu bar"),
                       note: L("It only asks the volume how much is left — no disk scan, no reading your files · on by default"),
                       isOn: Binding(get: { prefs.menuBarEnabled },
                                     set: { prefs.setMenuBar($0) }))
            Divider().overlay(theme.palette.separator)
            SwitchLine(title: L("Open at Login"),
                       note: L("Without it the number shows only while CleanPilot is open · it takes effect once you allow it in System Settings"),
                       isOn: Binding(get: { prefs.loginItemEnabled },
                                     set: { prefs.setLoginItem($0) })) {
                if prefs.loginItemBlocked { openSettingsButton }
            }
        }
        .padding(.vertical, 4)
        .background(theme.cardShape().fill(theme.palette.surface))
        .overlay(theme.cardShape().stroke(theme.palette.separator, lineWidth: theme.metric.stroke))
    }

    private var openSettingsButton: some View {
        ThemeButton(kind: .compact, symbol: "arrow.up.right.square",
                    title: L("Open System Settings")) { Prefs.openLoginItemsSettings() }
            .fixedSize()
    }

    // MARK: Diagnostics (PR-4)
    //
    // Probes off by default is the boundary of the privacy promise (PRIVACY.md "What we read"); retention policy is off by default,
    // and is suggested only once on the crash-dump page the first time a regenerating category is seen; never auto-enabled.

    @AppStorage("diagnosticProbeEnabled") private var probeEnabled = false
    @AppStorage("retention.crash-dumps.enabled") private var retentionOn = false
    @AppStorage("retention.crash-dumps.count") private var retentionCount = 2_000

    private var diagnostics: some View {
        VStack(spacing: 0) {
            SectionLabel(text: L("Diagnostics"))
            SwitchLine(title: L("Content probe"),
                       note: L("Reads only the first 64 KB of crash dumps · results stay local · off by default"),
                       isOn: $probeEnabled)
            Divider().overlay(theme.palette.separator)
            SwitchLine(title: L("Retention: crash dumps"),
                       note: LF("Keep the newest %@; trim the rest manually — never automatic", cnt(retentionCount, "items")),
                       isOn: $retentionOn)
            if retentionOn {
                HStack {
                    ThemeStepper(label: L("Keep count"), value: $retentionCount,
                                 range: 100...10_000, step: 100)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
        .background(theme.cardShape().fill(theme.palette.surface))
        .overlay(theme.cardShape().stroke(theme.palette.separator, lineWidth: theme.metric.stroke))
    }

    private var footnote: some View {
        Text(L("These two switches are the whole page. Scan scope, unit basis and language come when there’s a real need for them."))
            .font(theme.bodyFont(.caption))
            .foregroundStyle(theme.palette.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One row = a toggle name in plain language + a note on what it means + the system switch.
/// The switch is not custom-drawn: `.switch` is the one from System Settings; the 38×22 pt measured on mockup 1 is its actual size.
private struct SwitchLine<Trailing: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    var note: String
    var isOn: Binding<Bool>
    var trailing: Trailing

    init(title: String, note: String, isOn: Binding<Bool>,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.note = note
        self.isOn = isOn
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(theme.bodyFont(.callout))
                    .foregroundStyle(theme.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
