import Foundation
import DiskCleanerCore

/// Localize presentation only. Core retains byte units and column rounding.
private func localizedSize(_ value: String) -> String {
    let separator = Locale(identifier: L10n.active.code).decimalSeparator ?? "."
    return separator == "." ? value : value.replacingOccurrences(of: ".", with: separator)
}

func uiHuman(_ bytes: Int64) -> String {
    localizedSize(DiskCleanerCore.human(bytes))
}

func uiHuman(_ bytes: Int64, inRulerOf total: Int64) -> String {
    localizedSize(DiskCleanerCore.human(bytes, inRulerOf: total))
}

func uiAddableHumanColumn(_ parts: [Int64], total: Int64) -> [String] {
    DiskCleanerCore.addableHumanColumn(parts, total: total).map(localizedSize)
}

func uiAddableHumanColumn(_ parts: [Int64], total: Int64, inRulerOf ruler: Int64) -> [String] {
    DiskCleanerCore.addableHumanColumn(parts, total: total, inRulerOf: ruler).map(localizedSize)
}

func uiUnifiedHuman(_ values: [Int64]) -> [String] {
    DiskCleanerCore.unifiedHuman(values).map(localizedSize)
}
