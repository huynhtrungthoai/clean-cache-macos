import SwiftUI
import DiskCleanerCore

/// Shared presentation of the lifecycle reported by the scanning model.
struct ScanStatusView: View {
    @Environment(\.theme) private var theme
    var model: any ScanStatusReporting
    var lastTrashAt: Date?
    var rescan: () -> Void
    @State private var showsIssues = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(stateText, systemImage: model.isPartial ? "exclamationmark.triangle" : "info.circle")
                    if let date = model.scannedAt {
                        Text(date, format: .dateTime.day().month().hour().minute())
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if model.scanState != .scanning && model.isStale(lastTrashAt: lastTrashAt) {
                        Text(L("Results may be out of date"))
                        Button(L("Scan again"), action: rescan)
                    } else if model.scanState != .scanning {
                        Button(model.scanState == .idle ? L("Scan now") : L("Scan again"), action: rescan)
                    }
                }
                if !model.issues.isEmpty {
                    HStack(spacing: 12) {
                        Button { showsIssues.toggle() } label: {
                            Label(LF("%d locations were not fully scanned", model.issues.count),
                                  systemImage: "exclamationmark.triangle")
                        }
                        .popover(isPresented: $showsIssues) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(model.issues) { issue in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(issue.root).textSelection(.enabled)
                                            Text(issueReason(issue)).foregroundStyle(theme.palette.inkSecondary)
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }.padding(16)
                            }
                            .font(theme.bodyFont(.caption))
                            .foregroundStyle(theme.palette.ink)
                            .frame(width: 440, height: 280)
                        }
                        if model.issues.contains(where: { $0.kind == .noPermission }) {
                            Button(L("Grant access")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .help(L("Opens System Settings › Privacy & Security › Full Disk Access; restart CleanPilot once you've ticked it"))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(theme.bodyFont(.caption))
            .foregroundStyle(theme.palette.inkSecondary)
            .buttonStyle(.borderless)
            .padding(.horizontal, 20).padding(.bottom, 6)
        }
    }

    private var stateText: String {
        switch model.scanState {
        case .idle: return L("Not scanned yet")
        case .scanning: return L("Scanning…")
        case .stopped: return L("Scan stopped. Results are incomplete.")
        case .completed: return model.isPartial ? L("Partial scan results") : L("Scan completed")
        }
    }

    private func issueReason(_ issue: ScanIssue) -> String {
        switch issue.kind {
        case .noPermission: return L("Access denied. Check folder permissions or Full Disk Access in System Settings > Privacy & Security, then scan again.")
        case .notFound: return L("Location not found")
        case .error(let detail): return LF("Scan failed: %@", detail)
        }
    }
}

