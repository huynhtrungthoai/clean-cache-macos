import SwiftUI
import DiskCleanerCore

// Small shared pieces for the V2 screens (docs/plan-v2.md §5–6). Presentation only: every value
// and every action comes from a model API in enhance-feat.md §11 "V2".

/// Group checkbox with three states. The model decides what a click changes.
struct TriStateCheck: View {
    @Environment(\.theme) private var theme
    var state: GroupSelection
    var label: String
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .all ? "checkmark.square.fill"
                  : state == .some ? "minus.square.fill" : "square")
                .font(.system(size: 15))
                .foregroundStyle(state == .none ? theme.palette.inkSecondary : theme.palette.tint)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityValue(state == .all ? L("All selected") : state == .some ? L("Partly selected") : L("Not selected"))
    }
}

/// Search box used by the list pages; filtering never changes the selection.
struct SearchBox: View {
    @Environment(\.theme) private var theme
    var prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain).accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel(L("Clear search"))
            }
        }
        .font(theme.prose(size: 13))
        .foregroundStyle(theme.palette.inkSecondary)
        .padding(10)
        .background(theme.controlShape().fill(theme.palette.surface))
    }
}

/// Human text for a module state: never "clean" for something not read.
func moduleStateText(_ s: SmartScanModuleState) -> String {
    switch s {
    case .idle: return L("Not scanned yet")
    case .queued: return L("Waiting")
    case .running: return L("Scanning…")
    case .completed: return L("Done")
    case .partial: return L("Partly read")
    case .cancelled: return L("Stopped")
    case .permissionDenied: return L("Needs access")
    case .failed: return L("Couldn't scan")
    }
}

func moduleStateSymbol(_ s: SmartScanModuleState) -> String {
    switch s {
    case .idle: return "circle.dashed"
    case .queued: return "clock"
    case .running: return "arrow.triangle.2.circlepath"
    case .completed: return "checkmark.circle.fill"
    case .partial: return "exclamationmark.circle"
    case .cancelled: return "pause.circle"
    case .permissionDenied: return "lock.circle"
    case .failed: return "xmark.octagon"
    }
}

/// Kind chips + search for Large / Old Files (V2-FILES). Filters only the listed rows.
struct FileFacetBar: View {
    @Environment(\.theme) private var theme
    var counts: [(kind: FileKind, count: Int, bytes: Int64)]
    @Binding var kind: FileKind?
    @Binding var query: String
    var truncated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Picker(L("Kind"), selection: $kind) {
                    Text(L("All kinds")).tag(FileKind?.none)
                    ForEach(counts, id: \.kind) { c in
                        Text("\(L(c.kind.titleKey)) · \(c.count)").tag(Optional(c.kind))
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
                SearchBox(prompt: L("Search files"), text: $query)
            }
            if truncated && (kind != nil || !query.isEmpty) {
                Text(L("Filters apply to the listed files only"))
                    .font(theme.prose(size: 11)).foregroundStyle(theme.palette.inkSecondary)
            }
        }
    }
}

func shortDate(_ d: Date?) -> String {
    guard let d else { return L("Unknown") }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}
