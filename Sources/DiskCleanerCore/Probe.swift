import Foundation

// MARK: - Content probe & provenance (PR-3)
//
// Design: plans/design-diagnostic-dumps-velocity-provenance-2026-10-27.md §5,
// review revision §2.3: probe off by default, reads only the first 64KB of crash dumps, results stay on this machine, display redacted by default.
// This explicitly relaxes the PRIVACY.md promise "we don't read document contents"; the promise text was rewritten in this PR.

/// Content probe. Reads only the file header, no full minidump parsing: v1 only needs
/// one piece of corroboration, "which process crashed", not an incident report.
public protocol ContentProbe {
    var maxReadBytes: Int { get }
    func probe(_ url: URL) -> ProbeResult
}

public struct ProbeResult: Equatable {
    /// false = not probed (file over limit / wrong format / unreadable); shown honestly, never fake a conclusion
    public let probed: Bool
    public let executablePath: String?
    /// Originator fingerprints (raw key=value, redacted uniformly before display)
    public let originHints: [String]

    public init(probed: Bool, executablePath: String? = nil, originHints: [String] = []) {
        self.probed = probed
        self.executablePath = executablePath
        self.originHints = originHints
    }
}

/// Crashpad minidump probe: checks the MDMP magic, strings-scans for executable_path and environment fingerprint keys.
public struct CrashpadProbe: ContentProbe {
    public let maxReadBytes = 64 * 1024
    /// Fingerprint key suffix convention: a hit is taken as an originator clue; the value is masked before display
    static let hintSuffixes = ["_SESSION_ID=", "_TOOL_CALL_ID="]
    static let bundleKey = "CFBundleIdentifier="

    public init() {}

    public func probe(_ url: URL) -> ProbeResult {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return ProbeResult(probed: false) }
        defer { try? fh.close() }
        let data = (try? fh.read(upToCount: maxReadBytes)) ?? Data()
        guard data.count >= 4 else { return ProbeResult(probed: false) }
        // Magic check prevents false hits: anything that isn't a minidump (even if the user dropped it here) is "not probed"
        guard data.prefix(4) == Data("MDMP".utf8) else { return ProbeResult(probed: false) }

        let bytes = [UInt8](data)
        var exe: String?
        if let r = find("executable_path=", in: bytes) {
            exe = readToken(in: bytes, from: r.end)
        }
        var hints: [String] = []
        for suffix in Self.hintSuffixes {
            if let r = find(suffix, in: bytes) {
                // Key name = uppercase run traced back from the '=' (e.g. CODEBUDDY) + the matched suffix (_SESSION_ID)
                let back = readKey(in: bytes, before: r.start) ?? ""
                if let val = readToken(in: bytes, from: r.end), !back.isEmpty {
                    hints.append("\(back)\(suffix)\(val)")
                }
            }
        }
        if let r = find(Self.bundleKey, in: bytes) {
            if let val = readToken(in: bytes, from: r.end) {
                hints.append("CFBundleIdentifier=\(val)")
            }
        }
        return ProbeResult(probed: true, executablePath: exe, originHints: hints)
    }

    private struct Range { let start: Int; let end: Int }

    private func find(_ needle: String, in bytes: [UInt8]) -> Range? {
        let n = Array(needle.utf8)
        guard !n.isEmpty, bytes.count >= n.count else { return nil }
        for i in 0...(bytes.count - n.count) {
            var ok = true
            for j in 0..<n.count where bytes[i + j] != n[j] { ok = false; break }
            if ok { return Range(start: i, end: i + n.count) }
        }
        return nil
    }

    /// Read a "path/value" token from a position: up to NUL, newline or a control character
    private func readToken(in bytes: [UInt8], from start: Int) -> String? {
        var out: [UInt8] = []
        var i = start
        while i < bytes.count, bytes[i] >= 0x20, bytes[i] != 0x7F {
            out.append(bytes[i])
            i += 1
            if out.count > 512 { break }   // No path is half a KB long; exceeding that means we scanned into garbage
        }
        let s = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    /// Read back from the '=' a key name made of uppercase/digits/underscores (like CODEBUDDY_SESSION_ID)
    private func readKey(in bytes: [UInt8], before end: Int) -> String? {
        var i = end
        while i > 0 {
            let c = bytes[i - 1]
            if (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 { i -= 1 } else { break }
        }
        let s = String(decoding: bytes[i..<end], as: UTF8.self)
        return s.isEmpty ? nil : s
    }
}

/// Provenance settlement for one entry: directory provenance × content provenance.
public struct AttributionOutcome: Equatable {
    public let directoryOwner: String?
    public let contentOwner: String?
    public let mixed: Bool
    public let probed: Bool
    public let samples: Int
    /// Redacted originator fingerprints (KEY=d5•••3f form), displayed locally only
    public let redactedHints: [String]

    public var crossAttribution: Bool {
        guard let content = contentOwner, let dir = directoryOwner else { return false }
        return !content.isEmpty && !dir.isEmpty
            && !content.localizedCaseInsensitiveContains(dir)
    }
}

/// Sampling strategy: newest 3 + oldest 1 + random 1 (design mock screen ③). Fewer than 5 files: sample all.
public func probeSampleFiles(under dirs: [URL], limit: Int = 5) -> [URL] {
    let fm = FileManager.default
    var files: [(url: URL, mtime: Date)] = []
    for d in dirs {
        guard let names = try? fm.contentsOfDirectory(atPath: d.path) else { continue }
        for n in names where (n as NSString).pathExtension.lowercased() == "dmp" {
            let u = d.appendingPathComponent(n)
            var st = stat()
            guard lstat(u.path, &st) == 0 else { continue }
            files.append((u, Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec))))
        }
    }
    guard files.count > limit else { return files.map(\.url) }
    files.sort { $0.mtime > $1.mtime }
    var picked = Array(files.prefix(3).map(\.url))
    picked.append(files[files.count - 1].url)
    if let rand = files.dropFirst(3).dropLast().randomElement()?.url { picked.append(rand) }
    return picked
}

/// Settle provenance: "content provenance" only if all samples agree; disagreement is "mixed sources"; none probed is "not probed".
public func resolveAttribution(directoryOwner: String?, results: [ProbeResult]) -> AttributionOutcome {
    let probed = results.filter(\.probed)
    guard !probed.isEmpty else {
        return AttributionOutcome(directoryOwner: directoryOwner, contentOwner: nil, mixed: false,
                                  probed: false, samples: 0, redactedHints: [])
    }
    let owners = Set(probed.compactMap(\.executablePath).map { ownerName(of: $0) })
    let mixed = owners.count > 1
    let hints = Array(Set(probed.flatMap(\.originHints))).sorted()
    return AttributionOutcome(directoryOwner: directoryOwner,
                              contentOwner: owners.first,
                              mixed: mixed,
                              probed: true,
                              samples: probed.count,
                              redactedHints: hints.map(redactHint))
}

/// Path → process name: last component with the .app wrapper stripped gives the bundle name, otherwise the executable name
public func ownerName(of executablePath: String) -> String {
    let url = URL(fileURLWithPath: executablePath)
    var parts = url.pathComponents.filter { !$0.isEmpty && $0 != "/" }
    if let idx = parts.lastIndex(where: { $0.hasSuffix(".app") }) {
        return parts[idx].replacingOccurrences(of: ".app", with: "")
    }
    if let last = parts.popLast(), !last.isEmpty { return last }
    return executablePath
}

/// Fingerprint redaction: keep only the first 2 and last 2 chars of the value, dots in between. Guards against screenshot leaks, not local reading.
public func redactHint(_ hint: String) -> String {
    guard let eq = hint.firstIndex(of: "=") else { return hint }
    let key = String(hint[hint.startIndex..<eq])
    let val = String(hint[hint.index(after: eq)...])
    guard val.count > 4 else { return "\(key)=••••" }
    let head = val.prefix(2)
    let tail = val.suffix(2)
    return "\(key)=\(head)••••\(tail)"
}

/// Probe master switch. Off by default: this is the privacy-promise boundary (PRIVACY.md "what we read" is rewritten in sync with this key).
public func diagnosticProbeEnabled() -> Bool {
    UserDefaults.standard.object(forKey: "diagnosticProbeEnabled") as? Bool ?? false
}
