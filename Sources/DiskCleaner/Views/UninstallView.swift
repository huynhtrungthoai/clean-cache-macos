import SwiftUI
import DiskCleanerCore

//

//

struct UninstallView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @ObservedObject var model: UninstallModel
    @State private var review: TrashReviewPlan?
    @State private var pendingResult: TrashBatch?
    @State private var result: TrashBatch?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(symbol: AppPanel.uninstall.symbol, title: L("Uninstall Apps"),
                           subtitle: L("Review an app and its private data before uninstalling"),
                           variant: .compact, scope: L("Installed apps; related data in the home folder"))
                ControlStrip {
                    if model.scanning {
                        LoadingRow(text: L("Taking stock of installed apps…"), progress: model.progress)
                    } else {
                        Text(LF("Found %1$@ — %2$@ can be uninstalled",
                                cnt(model.scanned, "apps"),
                                cnt(model.uninstallableCount, "apps")))
                    }
                    ThemeBadge(text: L("Home folder only"), tone: .neutral)
                } trailing: {
                    ScanControl(scanning: model.scanning, kind: .compact,
                                rescan: { model.scan() }, stop: { model.stop() })
                }
            }
            .pagePadding()
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt, rescan: { model.scan() })
            Button(L("Review leftover app data")) { store.arrive(NavStop(panel: .orphans)) }
                .buttonStyle(.link).padding(.bottom, 8)

            if model.scanning && model.apps.isEmpty {
                ScanChecklist(progress: model.progress)
            } else if !model.scanning && model.apps.isEmpty {
                EmptyState(symbol: "trash.slash", title: L("Nothing here can be uninstalled"),
                           hint: L("Apps in system folders and apps that only appear as a link are left out — they cannot move, or only a link would move"))
                    .frame(maxHeight: .infinity)
            } else {
                SummaryCards(metrics: [
                    .init(title: L("Listed items"), value: String(model.apps.count), detail: L("Applications"), symbol: "app"),
                    .init(title: L("Selected"), value: planSizeText, detail: model.current?.name ?? L("No app picked yet"), symbol: "checkmark.circle")
                ]).pagePadding().padding(.bottom, 6)
                HStack(alignment: .top, spacing: 14) {
                    picker
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 260)
                    detail
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .pagePadding()
                .frame(maxHeight: .infinity, alignment: .top)
            }

            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if !model.started { model.scan() }
            if let q = SnapshotMode.requestedQuery { model.query = q }
            pickSnapshotAppIfAsked()
        }

        .onChange(of: model.apps.count) { _ in pickSnapshotAppIfAsked() }
        .sheet(item: $review, onDismiss: {
            result = pendingResult
            pendingResult = nil
        }) { review in
            UninstallConfirmationSheet(model: model, plan: review.items) { batch in
                pendingResult = batch
                self.review = nil
            }.themed(theme)
        }
        .sheet(item: $result) { batch in BatchResultSheet(batch: batch).themed(theme) }
    }

    private func pickSnapshotAppIfAsked() {
        guard let want = SnapshotMode.requestedApp, model.current == nil,
              let app = model.shown.first(where: {
                  $0.name.lowercased().contains(want) || $0.bundleID.lowercased().contains(want)
              }) else { return }
        model.choose(app)
    }

    private var picker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.palette.inkTertiary)
                TextField(L("Search apps"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont(.callout))
                    .foregroundStyle(theme.palette.ink)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.palette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Clear search"))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.controlShape().fill(theme.palette.surfaceAlt))
            .padding(10)

            Rectangle().fill(theme.palette.separator).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.shown) { app in
                        appRow(app)
                    }
                    if model.shown.isEmpty && !model.scanning {
                        Text(L("No apps match"))
                            .font(theme.bodyFont(.caption))
                            .foregroundStyle(theme.palette.inkTertiary)
                            .padding(.top, 18)
                    }
                }
                .padding(6)
            }
        }
        .panelCard()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let selfRow = model.isSelf(app)
        let on = !selfRow && model.current?.id == app.id
        return Button {
            model.choose(app)
        } label: {
            HStack(spacing: 9) {
                RowIconView(icon: .path(app.path), side: 26)
                    .opacity(selfRow ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(theme.bodyFont(.callout))
                        .foregroundStyle(selfRow ? theme.palette.inkTertiary : theme.palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(selfRow
                         ? L("This is CleanPilot itself · to remove it, drag it to the Trash in the Finder")
                         : (app.bundleID.isEmpty ? app.path.path : app.bundleID))
                        .font(theme.bodyFont(.caption2))
                        .foregroundStyle(theme.palette.inkTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if case .running = model.runState(of: app) {
                    Text(L("Running")).font(theme.bodyFont(.caption2))
                }
                if app.isAppStore && !selfRow {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.palette.inkTertiary)
                        .help(L("Installed from the App Store"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? theme.palette.tintSoft : Color.clear,
                        in: theme.controlShape())
            .contentShape(theme.controlShape())
        }
        .buttonStyle(.plain)

        .disabled(selfRow)
        .help(selfRow ? L("This is CleanPilot itself · to remove it, drag it to the Trash in the Finder") : "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var detail: some View {
        if let app = model.current {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    appCard(app)
                    if model.planning {
                        LoadingRow(text: LF("Measuring “%@” and its data…", app.name),
                                   progress: model.planProgress, fillsRow: true)
                            .panelCard()
                    } else {
                        dataCard(app)
                        notes(app)
                    }
                }
                .padding(.bottom, 8)
            }
        } else {
            EmptyState(symbol: "square.split.2x1", title: L("Pick an app on the left"),
                       hint: L("Its bundle and data show up here; tick the ones you want to move"))
                .frame(maxHeight: .infinity)
        }
    }

    private func appCard(_ app: InstalledApp) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RowIconView(icon: .path(app.path), side: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(theme.display(.title3))
                    .foregroundStyle(theme.palette.ink)
                HStack(spacing: 8) {
                    Text(app.bundleID.isEmpty ? L("No bundle ID") : app.bundleID)
                        .font(theme.bodyFont(.caption))
                        .foregroundStyle(theme.palette.inkSecondary)
                        .lineLimit(1)
                    if case .running = model.runState(of: app) {
                        ThemeBadge(text: L("Running"), tone: .warn, symbol: "circle.fill")
                    }
                    if app.isAppStore {
                        ThemeBadge(text: L("App Store"), tone: .tint, symbol: "arrow.down.circle")
                    }
                }
                Text(displayPath(app.path))
                    .font(theme.bodyFont(.caption2))
                    .foregroundStyle(theme.palette.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 2) {
                Text(L("App plus ticked data"))
                    .font(theme.bodyFont(.caption2))
                    .foregroundStyle(theme.palette.inkTertiary)
                SizeNumber(shown: planSizeText, size: 26)
            }
        }
        .padding(16)
        .panelCard()
    }

    private func dataCard(_ app: InstalledApp) -> some View {
        VStack(spacing: 0) {

            ItemRow(selected: .constant(false),
                    icon: .path(app.path),
                    name: app.name,
                    sub: L("App bundle · always moved"),
                    sizeText: model.bundleBytes.map(uiHuman) ?? L("Unknown"),
                    fraction: fraction(model.bundleBytes ?? 0),
                    selectable: false,
                    lit: true,
                    showRule: false) {
                ExplainLine(key: L("What it is"), value: L("The app program itself (the .app bundle)"))
                ExplainLine(key: L("What breaks"), value: L("The app leaves Applications; drag it back out of the Trash to reinstall"))
            }
            .themedRow()

            ForEach($model.items) { $it in
                ItemRow(selected: $it.selected,
                        icon: .path(it.path),
                        name: it.name,
                        sub: it.loc,
                        sizeText: it.size.map(uiHuman) ?? L("Unknown"),
                        fraction: fraction(it.size ?? 0),
                        badge: verdictBadge(it.level == "warn" ? .risky : .safe),
                        lit: it.level != "warn") {
                    ExplainLine(key: L("What it is"), value: LF("Data that %1$@ left in %2$@", app.name, it.loc))
                    ExplainLine(key: L("What breaks"), value: riskLine(it))
                    ExplainLine(key: L("How to recover"), value: L("Put it back from the Trash, or reinstall the app"))
                    if let what = contentsLine(it.files, it.newest) {
                        ExplainLine(key: L("Contents"), value: what)
                    }
                    PathLine(path: it.path.path)
                }
                .themedRow()
            }
        }
        .panelCard()
    }

    @ViewBuilder private func notes(_ app: InstalledApp) -> some View {
        if !model.sharedPaths.isEmpty {
            DisclosureGroup(L("Excluded shared data")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.sharedPaths, id: \.path) { path in
                        Text(displayPath(path)).font(theme.bodyFont(.caption))
                            .foregroundStyle(theme.palette.inkSecondary).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ListNote(text: LF("%1$@ (%2$@) also belong to another installed app, so they are neither listed nor deleted.",
                              cnt(model.sharedPaths.count, "spots"),
                              model.sharedPaths.prefix(3).map(\.lastPathComponent)
                                  .joined(separator: ", ")))
        }
        if let b = model.bundleBytes, b > 0, model.items.isEmpty, !model.planning {
            ListNote(text: L("No other data found under this app — only the app itself will move."))
        }
        if app.isAppStore {
            ListNote(text: L("Installed from the App Store — reinstall it there for free whenever you need it."))
        }
    }

    private var footer: some View {
        SelectionActionBar(count: model.current == nil ? 0 : model.moveCount,
                           bytes: planSizeText,
                           busy: model.scanning || model.planning || store.isTrashing,
                           consequence: L("The app and selected private data will move to the Trash. Shared data is excluded.")) {
            let plan = model.trashPlan()
            if !plan.isEmpty { review = TrashReviewPlan(items: plan) }
        }
    }

    private var planSizeText: String {
        if model.planning { return L("Counting…") }
        if model.current != nil && model.bundleBytes == nil { return L("Unknown") }
        return uiHuman(model.totalBytes)
    }

    private func fraction(_ bytes: Int64) -> Double {
        let top = max(model.bundleBytes ?? 0, model.items.compactMap(\.size).max() ?? 1)
        return Double(bytes) / Double(max(1, top))
    }

    private func riskLine(_ it: AppDataItem) -> String {
        if it.loc == "Preferences" {
            return L("Unticked: settings and sign-in stay. Ticked: the app starts fresh next time and may ask you to sign in or enter a licence again.")
        }
        return it.level == "warn"
            ? L("Reinstalling the app won't bring these settings back; other apps are unaffected")
            : L("The app rebuilds it when needed")
    }

}

private struct PanelCard: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let shape = theme.cardShape()
        content
            .background(shape.fill(theme.palette.surface))
            .clipShape(shape)
            .overlay(shape.stroke(theme.palette.separator, lineWidth: theme.metric.stroke))
    }
}

private extension View {
    func panelCard() -> some View { modifier(PanelCard()) }
}


private struct UninstallConfirmationSheet: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var model: UninstallModel
    let plan: [TrashPlanItem]
    var completed: (TrashBatch) -> Void
    @State private var quitPrompt = false
    @State private var quitting = false
    @State private var quitError: String?

    var body: some View {
        TrashReviewSheet(items: plan.map(TrashReviewItem.init),
                         bytes: uiHuman(plan.reduce(0) { $0 + $1.bytes }),
                         consequence: L("The app and selected private data will move to the Trash. Shared data is excluded."),
                         busy: store.isTrashing || quitting,
                         busyText: quitting ? L("Waiting for the app to quit…") : L("Moving to Trash…"),
                         dismissOnConfirm: false,
                         stop: store.isTrashing ? { store.cancelTrash() } : nil) {
            Task { await performUninstall() }
        }
        .alert(LF("%@ is running. Quit it and uninstall?", model.current?.name ?? ""), isPresented: $quitPrompt) {
            Button(L("Cancel"), role: .cancel) { }
            Button(L("Quit and uninstall"), role: .destructive) {
                guard let app = model.current else { return }
                quitting = true
                Task {
                    defer { quitting = false }
                    switch await model.requestQuit(app) {
                    case .quit: await performUninstall()
                    case .refused: quitError = L("The app refused to quit. Nothing was uninstalled.")
                    case .timedOut: quitError = L("The app has not quit. It may be asking to save a document. Nothing was uninstalled.")
                    }
                }
            }
        }
        .alert(L("Cannot uninstall"), isPresented: Binding(get: { quitError != nil }, set: { if !$0 { quitError = nil } })) {
            Button(L("Close"), role: .cancel) { quitError = nil }
        } message: { Text(quitError ?? "") }
    }

    private func performUninstall() async {
        guard plan == model.trashPlan(), !store.isTrashing else {
            quitError = L("Selection changed. Review and confirm again.")
            return
        }
        switch await model.uninstall(using: store) {
        case .done(let batch): completed(batch)
        case .appRunning: quitPrompt = true
        case .busy, .nothingToDo: break
        }
    }


}
