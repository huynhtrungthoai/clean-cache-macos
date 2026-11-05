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

    private var measured: Int { model.items.filter { $0.size != nil }.count }
    private var progress: Double {
        guard !model.items.isEmpty else { return 0 }
        return Double(measured) / Double(model.items.count)
    }
    private var ready: Bool { model.completed && !model.scanning }

    var body: some View {
        if reviewing {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        reviewing = false
                        usage = volumeUsage()
                    } label: {
                        Label(L("返回智能扫描"), systemImage: "chevron.left")
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
                            Text(L("智能扫描"))
                                .font(theme.prose(size: 17, weight: .semibold))
                            Spacer()
                            Label(L("只在本机处理"), systemImage: "lock.shield")
                                .font(theme.prose(size: 11))
                                .foregroundStyle(theme.palette.inkSecondary)
                        }

                        HStack(spacing: 28) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(L("为你的 Mac 腾出空间"))
                                    .font(theme.prose(size: 34, weight: .bold))
                                    .tracking(-1)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(L("一次扫描，找到可以清理的缓存。每一步都由你决定。"))
                                    .font(theme.prose(size: 14))
                                    .foregroundStyle(theme.palette.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(4)
                                if let usage {
                                    HStack(spacing: 6) {
                                        Image(systemName: "internaldrive")
                                        Text(LF("可用 %@ / %@", human(usage.free + usage.purgeable), human(usage.total)))
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
                            summaryCard(symbol: "sparkles", title: L("应用缓存"),
                                        detail: L("日常应用留下的临时文件"),
                                        count: count(groups: ["general", "cn_app"]))
                            summaryCard(symbol: "shippingbox", title: L("开发缓存"),
                                        detail: L("开发工具与下载缓存"),
                                        count: count(groups: ["dev"]))
                            Button { store.arrive(NavStop(panel: .overview)) } label: {
                                summaryCard(symbol: "internaldrive", title: L("空间总览"),
                                            detail: L("查看整个磁盘的空间分布"), count: nil,
                                            navigates: true)
                            }.buttonStyle(.plain)
                        }

                        status
                    }
                    .foregroundStyle(theme.palette.ink)
                    .padding(.horizontal, 32).padding(.vertical, 22)
                    .frame(maxWidth: .infinity, minHeight: max(0, proxy.size.height - 112), alignment: .center)
                }
                actionBar
            }
        }
        .onAppear { usage = volumeUsage() }
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
                Text(model.scanning ? "\(Int(progress * 100))%" : (ready ? L("扫描完成") : "Mac"))
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
        .accessibilityLabel(model.scanning ? LF("已检查 %1$d / %2$d 处缓存", measured, model.items.count)
                                : (ready ? L("扫描完成") : L("准备好扫描")))
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
                    Text(L("正在查找可清理的缓存…"))
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
                    Text(LF("发现 %@ 可清理的缓存", human(model.selectableBytes)))
                        .font(theme.prose(size: 17, weight: .semibold))
                    Text(L("仅统计清理后无影响的项目；需要重新下载或可能丢失数据的项目单独列出。"))
                        .font(theme.prose(size: 11)).foregroundStyle(theme.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: theme.metric.radiusCard).fill(theme.palette.surfaceAlt))
        } else {
            Label(model.started ? L("扫描已暂停，可以重新开始。") : L("只扫描，不会自动删除任何文件。"),
                  systemImage: model.started ? "pause.circle" : "checkmark.shield")
                .font(theme.prose(size: 12)).foregroundStyle(theme.palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                if ready {
                    Button(L("重新扫描")) { model.load(force: true) }
                        .buttonStyle(.plain).foregroundStyle(theme.palette.inkSecondary)
                }
                Button {
                    if model.scanning { model.stop() }
                    else if ready { reviewing = true }
                    else { model.load(force: true) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.scanning ? "stop.fill" : (ready ? "list.bullet" : "magnifyingglass"))
                        Text(model.scanning ? L("停止扫描") : (ready ? L("查看并选择清理") : L("开始扫描")))
                    }
                    .font(theme.prose(size: 14, weight: .semibold))
                    .foregroundStyle(theme.palette.onTint)
                    .frame(minWidth: 190).padding(.horizontal, 22).padding(.vertical, 15)
                    .background(Capsule().fill(theme.palette.tint))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
            Text(L("先预览，再清理。移入废纸篓后可以撤销。"))
                .font(theme.prose(size: 11)).foregroundStyle(theme.palette.inkSecondary)
        }
        .padding(.top, 16).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(theme.palette.surface.opacity(0.7))
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.separator).frame(height: 1) }
    }
}
