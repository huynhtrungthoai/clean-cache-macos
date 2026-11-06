import SwiftUI
import DiskCleanerCore

/// Shared presentation of the lifecycle reported by the scanning model.
struct ScanStatusView: View {
    @Environment(\.theme) private var theme
    var model: any ScanStatusReporting
    var lastTrashAt: Date?
    var rescan: () -> Void

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
                    } else if model.scanState == .idle || model.scanState == .stopped {
                        Button(L("Scan now"), action: rescan)
                    }
                }
                if !model.issues.isEmpty {
                    DisclosureGroup(LF("%d locations were not fully scanned", model.issues.count)) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.issues) { issue in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(issue.root).textSelection(.enabled)
                                        Text(issueReason(issue)).foregroundStyle(theme.palette.inkSecondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }
                }
            }
            .font(theme.bodyFont(.caption))
            .foregroundStyle(theme.palette.inkSecondary)
            .buttonStyle(.borderless)
            .padding(.horizontal, 24).padding(.bottom, 8)
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

