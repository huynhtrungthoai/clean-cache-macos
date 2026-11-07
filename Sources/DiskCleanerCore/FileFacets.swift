import Foundation
import UniformTypeIdentifiers

// ── V2-FILES: file kind and date semantics for Large & Old Files (docs/plan-v2.md §6.4 / §7) ──
//
// `FileRow.mtime` is the content-modification date and stays what "old" means (threshold
// unchanged). `FileRow.accessedAt` is the filesystem's last-access time (atime): macOS updates it
// lazily, so it is shown as "last accessed (file system record)" and is never used to call a
// file unused. Filters run over the rows a scan returned (the scan keeps the largest N); the
// model says so through `rowsAreTruncated`.

public enum FileKind: String, CaseIterable, Sendable {
    case image, video, audio, archive, diskImage = "disk_image", document, code, application, other

    public var titleKey: String {
        switch self {
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .archive: return "Archives"
        case .diskImage: return "Disk images"
        case .document: return "Documents"
        case .code: return "Code & data"
        case .application: return "Apps & installers"
        case .other: return "Other files"
        }
    }
}

/// Kind from the file extension's system type (UTType). Pure: no file is opened.
public func fileKind(for url: URL) -> FileKind {
    let ext = url.pathExtension.lowercased()
    guard !ext.isEmpty else { return .other }
    if ["dmg", "iso", "sparseimage", "sparsebundle", "img", "vmdk", "qcow2", "vdi", "raw"].contains(ext) { return .diskImage }
    if ["pkg", "mpkg", "app", "ipa", "apk", "xip"].contains(ext) { return .application }
    guard let t = UTType(filenameExtension: ext) else { return .other }
    if t.conforms(to: .image) { return .image }
    if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
    if t.conforms(to: .audio) { return .audio }
    if t.conforms(to: .archive) || ["zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar", "zst"].contains(ext) { return .archive }
    if t.conforms(to: .sourceCode) || t.conforms(to: .json) || t.conforms(to: .xml) || t.conforms(to: .database)
        || ["sqlite", "db", "csv", "log", "yaml", "yml"].contains(ext) { return .code }
    if t.conforms(to: .pdf) || t.conforms(to: .presentation) || t.conforms(to: .spreadsheet)
        || t.conforms(to: .text) || t.conforms(to: .compositeContent) || ["doc", "docx", "pages", "key", "numbers", "epub"].contains(ext) {
        return .document
    }
    return .other
}

/// Search + kind filter over returned rows. Never changes selection (rows keep their flags).
public func filterFileRows(_ rows: [FileRow], query: String = "", kinds: Set<FileKind> = []) -> [FileRow] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    return rows.filter { r in
        (kinds.isEmpty || kinds.contains(r.kind))
            && (q.isEmpty || r.name.lowercased().contains(q) || r.url.path.lowercased().contains(q))
    }
}

/// Rows per kind (filter chips with counts); only kinds that occur.
public func fileKindCounts(_ rows: [FileRow]) -> [(kind: FileKind, count: Int, bytes: Int64)] {
    var c: [FileKind: (Int, Int64)] = [:]
    for r in rows { let k = r.kind; c[k] = ((c[k]?.0 ?? 0) + 1, (c[k]?.1 ?? 0) + r.size) }
    return FileKind.allCases.compactMap { k in c[k].map { (k, $0.0, $0.1) } }
}
