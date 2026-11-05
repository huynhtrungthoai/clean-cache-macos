import SwiftUI
import DiskCleanerCore

struct TrashView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(symbol: "trash", title: L("Trash"),
                       subtitle: L("Review this session’s moves and restore the last item when possible"),
                       variant: .display, scope: L("This CleanPilot session"))
                .pagePadding().padding(.top, 14).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SummaryCards(metrics: [
                        .init(title: L("Moved this session"), value: human(store.trashedBytes),
                              detail: LF("%d history entries", store.trashHistory.count), symbol: "trash"),
                        .init(title: L("History"), value: String(store.trashHistory.count),
                              detail: L("This CleanPilot session"), symbol: "clock.arrow.circlepath")
                    ])
                    ThemedCard {
                        Label(L("Items move to the Trash. Free space may not increase until it is emptied."),
                              systemImage: "info.circle")
                            .font(theme.bodyFont(.callout))
                            .foregroundStyle(theme.palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let message {
                        ThemedCard {
                            Label(message, systemImage: "info.circle")
                                .font(theme.bodyFont(.callout))
                                .foregroundStyle(theme.palette.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                        }
                    }
                    if store.trashHistory.isEmpty {
                        EmptyState(symbol: "clock.arrow.circlepath", title: L("No moves recorded this session"),
                                   hint: L("Open Finder to inspect the current contents of the Trash."))
                    } else {
                        SectionLabel(text: L("This session"), detail: L("Newest first"))
                        ThemedCard(padding: 0) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(store.trashHistory.reversed().enumerated()), id: \.offset) { index, record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(record.displayName).fontWeight(.medium)
                                            Spacer(minLength: 8)
                                            Text(human(record.size)).monospacedDigit()
                                        }
                                        Text(record.original.path)
                                            .font(theme.bodyFont(.caption))
                                            .foregroundStyle(theme.palette.inkSecondary)
                                            .textSelection(.enabled)
                                    }
                                    .font(theme.bodyFont(.callout))
                                    .padding(12)
                                    .accessibilityElement(children: .combine)
                                    if index < store.trashHistory.count - 1 { Divider() }
                                }
                            }
                        }
                    }
                }
                .pagePadding().padding(.bottom, 24)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    undoButton
                    Spacer()
                    finderButton
                }
                VStack(alignment: .leading, spacing: 8) { undoButton; finderButton }
            }
            Text(L("Empty the Trash in Finder after reviewing its contents. Emptying cannot be undone."))
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(theme.palette.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private var undoButton: some View {
        ThemeButton(kind: .secondary, symbol: "arrow.uturn.backward", title: L("Undo last"),
                    isDisabled: store.trashHistory.isEmpty) {
            message = store.undoLast()
        }
    }

    private var finderButton: some View {
        ThemeButton(kind: .primary, symbol: "folder", title: L("Open in Finder")) {
            openTrashInFinder()
        }
    }
}
