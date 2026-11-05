import SwiftUI
import AppKit
import DiskCleanerCore

// ── Feedback page ─────────────────────────────────────────────────────────────
//
// This app is offline, so a "Send feedback" button simply can't exist. What the page can do is lay out the three
// public channels clearly, keep them readable at a glance and copyable in one click, and tell users how to report usefully.
//
// All addresses come from Contact in Product.swift. CleanPilot only lists its own GitHub repo:
// the upstream author's email / QQ group were removed so user reports never go to a third party.

struct FeedbackView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject private var grant = HomeGrant.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(symbol: "text.bubble", title: L("Feedback"),
                           subtitle: L("This app never touches the network, so feedback has to come from you"),
                           variant: .display)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if HomeAccess.runsSandboxed { sandboxCard }
                        githubCard
                        hints
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    // This is a text page, not a list page: uncapped line length reads like a banner; left-aligned to match the header
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

    // MARK: Three channels

    /// App Store build only: a "nothing was scanned" report is 90% an expired grant or the wrong folder picked,
    /// so rather than have the user file an issue, put the current grant status and a re-pick entry in front of them.
    private var sandboxCard: some View {
        FeedbackCard(symbol: "checkmark.shield", title: L("Folder access"),
                     subtitle: HomeAccess.granted.map { LF("Granted: %@", $0.path) } ?? L("Not granted yet"),
                     extra: { EmptyView() }) {
            ThemeButton(kind: .secondary, symbol: "folder.badge.gearshape",
                        title: L("Re-grant")) { grant.revoke(); grant.request() }
        }
    }

    private var githubCard: some View {
        FeedbackCard(symbol: "chevron.left.forwardslash.chevron.right",
                     title: L("GitHub Issue"),
                     subtitle: LF("Repo %@", Contact.repoSlug),
                     extra: { EmptyView() }) {
            ThemeButton(kind: .compact, symbol: "doc.on.doc",
                        title: L("Copy repo URL")) { copy(Contact.repo) }
            ThemeButton(kind: .secondary, symbol: "arrow.up.right.square",
                        title: L("Open an issue")) { open(Contact.issues) }
        }
    }

    // MARK: How to report usefully

    private var hints: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: L("What makes a report useful"))
            VStack(alignment: .leading, spacing: 8) {
                ExplainLine(key: L("Where"),
                            value: L("Which page, which button, which folder you scanned"))
                ExplainLine(key: L("What you saw"),
                            value: L("Paste the error verbatim, or attach a screenshot"))
                ExplainLine(key: L("Your machine"),
                            value: L("macOS version, Apple Silicon or Intel"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.cardShape().fill(theme.palette.surface))
            .overlay(theme.cardShape().stroke(theme.palette.separator,
                                             lineWidth: theme.metric.stroke))

            Text(L("No network, no telemetry: none of the above exists until you send it yourself."))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(theme.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    // MARK: Actions

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        store.notice = pb.setString(text, forType: .string)
            ? LF("Copied: %@", text)
            : L("Copy failed — select the text and copy it by hand")
    }

    private func open(_ target: String) {
        guard let url = URL(string: target) else { return }
        if !NSWorkspace.shared.open(url) {
            store.notice = LF("Couldn't open %@ — your system may have blocked it", target)
        }
    }
}

// MARK: - Channel card

/// One card = one channel: icon tile + name + address + action on the right.
/// Addresses always use body text color, never colored links - design rule in docs/DESIGN.md §2.
private struct FeedbackCard<Actions: View, Extra: View>: View {
    @Environment(\.theme) private var theme
    var symbol: String
    var title: String
    var subtitle: String
    @ViewBuilder var extra: () -> Extra
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                IconTile(symbol: symbol, side: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(theme.display(.subheadline))
                        .tracking(theme.titleTracking)
                        .foregroundStyle(theme.palette.ink)
                    Text(subtitle)
                        .font(theme.bodyFont(.callout))
                        .foregroundStyle(theme.palette.inkSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                actions()
            }
            extra()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardShape().fill(theme.palette.surface))
        .overlay(theme.cardShape().stroke(theme.palette.separator,
                                         lineWidth: theme.metric.stroke))
    }
}

extension FeedbackCard where Extra == EmptyView {
    init(symbol: String, title: String, subtitle: String,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.extra = { EmptyView() }
        self.actions = actions
    }
}
