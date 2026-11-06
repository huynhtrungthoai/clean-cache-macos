import SwiftUI
import DiskCleanerCore

/// A short, deliberate path into the existing cache review and reversible cleanup flow.
/// The model lives in ScanStore, so navigating away never discards a running scan.
struct SmartScanView: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @ObservedObject var model: CachesModel
    @State private var reviewing = false
    @State private var usage = volumeUsage()
    /// C8: the plan frozen when "Clean" is pressed; the confirmation executes exactly this.
    @State private var confirming: SmartCleanPlan?
    @State private var pendingResult: TrashBatch?
    @State private var result: TrashBatch?
    /// C9: running apps that own cleanable caches, asked about before a scan starts.
    @State private var runningPrompt: RunningAppsPrompt?

    private var measured: Int { model.items.filter { $0.size != nil }.count }
    private var progress: Double {
        guard !model.items.isEmpty else { return 0 }
        return Double(measured) / Double(model.items.count)
    }
    private var ready: Bool { model.completed && !model.scanning }
    /// What one click would move right now (app caches, no-impact tier, running apps held back).
    private var preview: SmartCleanPlan? { ready ? model.smartCleanPlan() : nil }

    var body: some View {
        if reviewing {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        reviewing = false
                        usage = volumeUsage()
                    } label: {
                        Label(L("Back to Smart Scan"), systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .font(theme.prose(size: 13, weight: .medium))
                    .foregroundStyle(theme.palette.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                CachesView(model: model, page: .smart)
            }
        } else {
            dashboard
        }
    }

    private var dashboard: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack {
                            Text(L("Smart Scan"))
                                .font(theme.prose(size: 17, weight: .semibold))
                            Spacer()
                            Label(L("Everything stays on your Mac"), systemImage: "lock.shield")
                                .font(theme.prose(size: 11))
                                .foregroundStyle(theme.palette.inkSecondary)
                        }

                        HStack(spacing: 28) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L("More room.\nLess clutter."))
                                    .font(theme.prose(size: 34, weight: .bold))
                                    .tracking(-1)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(L("Find caches you can clear in one scan. You decide what goes."))
                                    .font(theme.prose(size: 14))
                                    .foregroundStyle(theme.palette.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(4)
                                if let usage {
                                    HStack(spacing: 6) {
                                        Image(systemName: "internaldrive")
                                        Text(LF("%@ free of %@", uiHuman(usage.free + usage.purgeable), uiHuman(usage.total)))
                                    }
                                    .font(theme.prose(size: 12, weight: .medium))
                                    .foregroundStyle(theme.palette.inkSecondary)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(theme.palette.surfaceAlt))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            scanEmblem
                        }
                        .padding(.vertical, 8)

                        HStack(spacing: 12) {
                            summaryCard(symbol: "sparkles", title: L("App Caches"),
                                        detail: L("Temporary files from everyday apps"),
                                        count: count(groups: ["general", "cn_app"]))
                            summaryCard(symbol: "shippingbox", title: L("Dev Caches"),
                                        detail: L("Build tools and download caches"),
                                        count: count(groups: ["dev"]))
                            Button { store.arrive(NavStop(panel: .overview)) } label: {
                                summaryCard(symbol: "internaldrive", title: L("Overview"),
                                            detail: L("See what takes up your disk"), count: nil,
                                            navigates: true)
                            }.buttonStyle(.plain)
                        }

                        status
                        if model.started {
                            ScanStatusView(model: model, lastTrashAt: store.lastTrashAt,
                                           rescan: { model.load(force: true) })
                        }
                    }
                    .foregroundStyle(theme.palette.ink)
                    .padding(.horizontal, 32).padding(.vertical, 22)
                    .frame(maxWidth: .infinity, minHeight: max(0, proxy.size.height - 112), alignment: .center)
                }
                actionBar
            }
        }
        .onAppear { usage = volumeUsage() }
        .sheet(item: $confirming, onDismiss: {
            result = pendingResult
            pendingResult = nil
            usage = volumeUsage()
        }) { plan in
            SmartCleanConfirmSheet(plan: plan) {
                Task {
                    if let batch = await model.smartClean(plan, using: store) {
                        pendingResult = batch
                        confirming = nil
                    }
                }
            }
            .themed(theme)
        }
        .sheet(item: $result) { batch in BatchResultSheet(batch: batch).themed(theme) }
        .sheet(item: $runningPrompt) { prompt in
            RunningAppsSheet(apps: prompt.apps,
                             quit: { ids in await model.quitApps(ids) },
                             proceed: {
                                 runningPrompt = nil
                                 model.load(force: true)
                             })
            .themed(theme)
        }
    }

    /// Scan / Rescan: ask about running apps that own caches first (quit or skip), like CleanMyMac.
    private func startScan() {
        let apps = model.runningCacheOwners()
        if apps.isEmpty { model.load(force: true) } else { runningPrompt = RunningAppsPrompt(apps: apps) }
    }

    private var scanEmblem: some View {
        ZStack {
            Circle().fill(theme.palette.tintSoft.opacity(0.65)).frame(width: 214, height: 214)
            Circle().stroke(theme.palette.tint.opacity(0.10), lineWidth: 1).frame(width: 240, height: 240)
            Circle().stroke(theme.palette.separator, lineWidth: 6).frame(width: 194, height: 194)
            Circle()
                .trim(from: 0, to: model.scanning ? progress : (ready ? 1 : 0.72))
                .stroke(theme.palette.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 194, height: 194)
                .animation(reduceMotion ? nil : theme.animation, value: progress)
            VStack(spacing: 10) {
                Image(systemName: ready ? "checkmark.seal" : "desktopcomputer")
                    .font(.system(size: 58, weight: .light))
                    .foregroundStyle(theme.palette.tint)
                    .accessibilityHidden(true)
                Text(model.scanning ? "\(Int(progress * 100))%" : (ready ? L("Scan Complete") : "Mac"))
                    .font(theme.prose(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.ink)
            }
            Image(systemName: "sparkle")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(theme.palette.tint)
                .offset(x: 87, y: -78)
        }
        .frame(width: 242, height: 242)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.scanning ? LF("Checked %1$d of %2$d cache locations", measured, model.items.count)
                                : (ready ? L("Scan Complete") : L("Ready to scan")))
    }

    private func count(groups: Set<String>) -> Int? {
        ready ? model.items.filter { groups.contains($0.groupKey) && ($0.size ?? 0) > 0 }.count : nil
    }

    private func summaryCard(symbol: String, title: String, detail: String,
                             count: Int?, navigates: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).font(.system(size: 23, weight: .light))
                    .foregroundStyle(theme.palette.tint)
                Spacer()
                if navigates {
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.palette.inkSecondary)
                } else if let count {
                    Text("\(count)").font(theme.numeric(size: 19, weight: .semibold))
                        .foregroundStyle(theme.palette.ink)
                }
            }
            Text(title).font(theme.prose(size: 13, weight: .semibold))
                .foregroundStyle(theme.palette.ink)
            Text(detail).font(theme.prose(size: 11))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: theme.metric.radiusCard).fill(theme.palette.surface))
        .overlay(RoundedRectangle(cornerRadius: theme.metric.radiusCard).stroke(theme.palette.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: theme.metric.radiusCard))
    }

    @ViewBuilder private var status: some View {
        if model.scanning {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("Looking for caches to clear…"))
                    Spacer()
                    Text("\(measured) / \(model.items.count)").monospacedDigit()
                }
                .font(theme.prose(size: 12))
                .foregroundStyle(theme.palette.inkSecondary)
                ProgressView(value: progress).tint(theme.palette.tint)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(model.progress.snapshot().current.replacingOccurrences(of: homePath(), with: "~"))
                        .font(theme.prose(size: 10)).foregroundStyle(theme.palette.inkSecondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if ready {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28))
                    .foregroundStyle(theme.palette.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LF("Found %@ of recommended caches to clear", uiHuman(preview?.bytes ?? 0)))
                        .font(theme.prose(size: 17, weight: .semibold))
                    Text(L("Only no-impact app caches are counted here. Dev caches and items that need a re-download or risk data loss stay in the list for you to choose."))
                        .font(theme.prose(size: 11)).foregroundStyle(theme.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: theme.metric.radiusCard).fill(theme.palette.surfaceAlt))
        } else {
            Label(model.started ? L("Scan stopped. Start again whenever you like.") : L("Scanning only. No files are removed automatically."),
                  systemImage: model.started ? "pause.circle" : "checkmark.shield")
                .font(theme.prose(size: 12)).foregroundStyle(theme.palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        }
    }

    private var actionBar: some View {
        let plan = preview
        let canClean = !(plan?.isEmpty ?? true)
        return VStack(spacing: 10) {
            HStack(spacing: 18) {
                if ready {
                    Button(L("Rescan")) { startScan() }
                        .buttonStyle(.plain).foregroundStyle(theme.palette.inkSecondary)
                        .disabled(store.isTrashing)
                }
                if ready && canClean {
                    Button(L("Review & Choose")) { reviewing = true }
                        .buttonStyle(.plain).foregroundStyle(theme.palette.inkSecondary)
                }
                Button {
                    if model.scanning { model.stop() }
                    else if ready {
                        // Re-read at press time: the confirmation shows and runs this frozen plan.
                        if let fresh = model.smartCleanPlan(), !fresh.isEmpty { confirming = fresh }
                        else { reviewing = true }
                    }
                    else { startScan() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.scanning ? "stop.fill"
                              : (ready ? (canClean ? "sparkles" : "list.bullet") : "magnifyingglass"))
                        Text(model.scanning ? L("Stop Scan")
                             : (ready ? (canClean ? LF("Clean %@", uiHuman(plan?.bytes ?? 0)) : L("Review & Choose"))
                                : L("Scan")))
                    }
                    .font(theme.prose(size: 14, weight: .semibold))
                    .foregroundStyle(theme.palette.onTint)
                    .frame(minWidth: 190).padding(.horizontal, 22).padding(.vertical, 15)
                    .background(Capsule().fill(theme.palette.tint))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(store.isTrashing)
            }
            Text(ready && canClean
                 ? L("Clean moves only no-impact app caches to the Trash. You can undo it.")
                 : L("Review first, then clean. Anything moved to the Trash can be restored."))
                .font(theme.prose(size: 11)).foregroundStyle(theme.palette.inkSecondary)
        }
        .padding(.top, 16).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(theme.palette.surface.opacity(0.7))
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.separator).frame(height: 1) }
    }
}

extension SmartCleanPlan: Identifiable {
    var id: String { items.map(\.path).joined(separator: "\n") }
}

/// C8 confirmation: a summary, not a checklist. The item list is there to inspect, folded away.
private struct SmartCleanConfirmSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let plan: SmartCleanPlan
    let confirm: () -> Void
    @State private var showItems = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(symbol: "sparkles", title: L("Clean recommended caches"),
                       subtitle: LF("%d items · app caches with no impact", plan.items.count))
            HStack {
                Text(L("To move to the Trash")).font(theme.bodyFont(.callout))
                Spacer()
                Text(uiHuman(plan.bytes)).font(theme.prose(size: 24, weight: .semibold)).monospacedDigit()
            }
            Text(L("Apps rebuild these files when needed. Items move to the Trash and can be restored; free space may not increase until the Trash is emptied."))
                .font(theme.bodyFont(.callout))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !plan.heldBack.isEmpty {
                Label(LF("Skipped while the app is running: %@. Quit it and scan again to clean it too.",
                         plan.heldBack.joined(separator: ", ")),
                      systemImage: "app.badge.checkmark")
                    .font(theme.bodyFont(.callout))
                    .foregroundStyle(theme.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $showItems) {
                List(plan.items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).fontWeight(.medium)
                            Text(item.path.replacingOccurrences(of: homePath(), with: "~"))
                                .font(theme.bodyFont(.caption))
                                .foregroundStyle(theme.palette.inkSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(uiHuman(item.bytes)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .frame(height: 200)
            } label: {
                Text(L("Show items")).font(theme.bodyFont(.callout))
            }
            Spacer(minLength: 0)
            if store.isTrashing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Moving to Trash…")).font(theme.bodyFont(.callout))
                    Spacer()
                    Button(L("Stop")) { store.cancelTrash() }
                }.accessibilityElement(children: .combine)
            }
            HStack {
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.isTrashing)
                    .foregroundStyle(theme.palette.ink)
                Spacer()
                ThemeButton(kind: .primary, symbol: "sparkles", title: L("Clean"),
                            isDisabled: plan.isEmpty || store.isTrashing) { confirm() }
            }
        }
        .padding(24)
        .frame(width: 560, height: showItems ? 560 : 360)
        .interactiveDismissDisabled(store.isTrashing)
        .background(theme.palette.paper)
        .foregroundStyle(theme.palette.ink)
        .buttonStyle(.borderless)
    }
}

struct RunningAppsPrompt: Identifiable {
    let id = UUID()
    let apps: [RunningCacheApp]
}

/// C9: before scanning, each running app that owns caches is either quit (its caches get cleaned)
/// or skipped (its caches are left alone). Nothing is quit without this explicit choice.
private struct RunningAppsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let apps: [RunningCacheApp]
    let quit: (Set<String>) async -> [String]
    let proceed: () -> Void
    @State private var toQuit: Set<String>
    @State private var quitting = false

    init(apps: [RunningCacheApp], quit: @escaping (Set<String>) async -> [String], proceed: @escaping () -> Void) {
        self.apps = apps
        self.quit = quit
        self.proceed = proceed
        _toQuit = State(initialValue: Set(apps.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(symbol: "app.badge", title: L("These apps are running"),
                       subtitle: L("Quit them so their caches can be cleaned, or skip them."))
            List(apps) { app in
                HStack(spacing: 10) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 24, height: 24).accessibilityHidden(true)
                    } else {
                        Image(systemName: "app").frame(width: 24, height: 24).accessibilityHidden(true)
                    }
                    Text(app.name).fontWeight(.medium)
                    Spacer()
                    Picker(app.name, selection: Binding(
                        get: { toQuit.contains(app.id) },
                        set: { on in if on { toQuit.insert(app.id) } else { toQuit.remove(app.id) } })) {
                        Text(L("Quit app")).tag(true)
                        Text(L("Skip app")).tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .disabled(quitting)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Text(L("Apps may ask you to save your work before they quit. Skipped apps keep their caches."))
                .font(theme.bodyFont(.callout))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if quitting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Quitting apps…")).font(theme.bodyFont(.callout))
                }
            }
            HStack {
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(quitting)
                    .foregroundStyle(theme.palette.ink)
                Spacer()
                Button(L("Skip all and scan")) { proceed() }.disabled(quitting)
                    .foregroundStyle(theme.palette.ink)
                ThemeButton(kind: .primary, symbol: "magnifyingglass",
                            title: toQuit.isEmpty ? L("Scan") : L("Quit and scan"),
                            isDisabled: quitting) {
                    guard !toQuit.isEmpty else { proceed(); return }
                    quitting = true
                    Task {
                        _ = await quit(toQuit)   // apps still running are held back by the clean plan
                        quitting = false
                        proceed()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: min(520, 260 + CGFloat(apps.count) * 40))
        .interactiveDismissDisabled(quitting)
        .background(theme.palette.paper)
        .foregroundStyle(theme.palette.ink)
        .buttonStyle(.borderless)
    }
}
