import Foundation

// Size argument parsing: 500MB / 2GB / 1.5GB / plain byte count.
// Decimal (1 GB = 10^9), same convention as the app and Finder's Get Info. Mixing both bases on one machine
// silently turns a "100MB threshold" into 104.9MB and nobody can reconcile it.

enum SizeArgError: Error, CustomStringConvertible {
    case bad(String)

    var description: String {
        switch self {
        case .bad(let s): return "cannot parse size '\(s)' (examples: 500MB, 2GB, 1.5GB, 1048576)"
        }
    }
}

func parseSize(_ raw: String) throws -> Int64 {
    let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
    guard !s.isEmpty else { throw SizeArgError.bad(raw) }
    var digits = ""
    var unit = ""
    var seenDot = false
    for ch in s {
        if ch.isNumber {
            digits.append(ch)
        } else if ch == "." && !seenDot && !digits.isEmpty {
            seenDot = true
            digits.append(ch)
        } else {
            unit = String(s[s.firstIndex(of: ch)!...])
            break
        }
    }
    let scale: Double
    switch unit {
    case "", "b": scale = 1
    case "kb": scale = 1_000
    case "mb": scale = 1_000_000
    case "gb": scale = 1_000_000_000
    case "tb": scale = 1_000_000_000_000
    default: throw SizeArgError.bad(raw)
    }
    guard let v = Double(digits), v >= 0, v.isFinite else { throw SizeArgError.bad(raw) }
    return Int64((v * scale).rounded())
}
