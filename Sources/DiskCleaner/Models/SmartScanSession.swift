import SwiftUI
import Combine
import DiskCleanerCore

/// V2-SCAN (docs/enhance-feat.md §11; owner decision 07/11/2026: Smart Scan covers more modules).
///
/// One Smart Scan session over the models `ScanStore` already holds, so every page shows the
/// same results and nothing is scanned twice. App + developer caches start first (the one-click
/// clean needs them); Trash, leftovers, large files and dev projects follow one at a time to keep
/// the disk from thrashing. Auto-selection is unchanged: the one-click Clean is still C8 (app
/// caches, no-impact tier). The other modules report what they found and point to their page.
@MainActor
final class SmartScanSession: ObservableObject {
    enum ModuleID: String, CaseIterable, Identifiable {
        case appCaches = "app_caches"
        case developerCaches = "developer_caches"
        case trash
        case leftovers
        case largeFiles = "large_files"
        case devProjects = "dev_projects"

        var id: String { rawValue }

        /// English source text; the UI shows `L(titleKey)`.
        var titleKey: String {
            switch self {
            case .appCaches: return "App caches"
            case .developerCaches: return "Developer caches"
            case .trash: return "Trash"
            case .leftovers: return "Leftovers"
            case .largeFiles: return "Large Files"
            case .devProjects: return "Developer projects"
            }
        }
    }

    struct Module: Identifiable, Equatable {
        let id: ModuleID
        let state: SmartScanModuleState
        /// nil while unknown (idle/queued/running, or not readable).
        let itemCount: Int?
        /// Measured bytes; nil while unknown. A lower bound when `partial`/`cancelled`, and for
        /// large files it covers the listed (largest) files only.
        let bytes: Int64?
        let issues: [ScanIssue]
    }

    private let smart: CachesModel
    private let trash: TrashModel
    private let orphans: OrphansModel
    private let big: BigFilesModel
    private let nodeModules: NMModel
    private let artifacts: DevArtifactsModel
    private var bag = Set<AnyCancellable>()

    /// Current/last session; nil before the first Smart Scan.
    @Published private(set) var sessionID: UUID? = nil
    @Published private(set) var startedAt: Date? = nil
    @Published private(set) var finishedAt: Date? = nil
    @Published private(set) var cancelled = false
    /// Modules this session included (all of `ModuleID.allCases` for now).
    @Published private(set) var scope: [ModuleID] = []
    /// Modules started by this session so far (a queued one is in `scope` but not here).
    @Published private(set) var launched: Set<ModuleID> = []
    private var runner: Task<Void, Never>? = nil

    init(smart: CachesModel, trash: TrashModel, orphans: OrphansModel, big: BigFilesModel,
         nodeModules: NMModel, artifacts: DevArtifactsModel) {
        self.smart = smart; self.trash = trash; self.orphans = orphans; self.big = big
        self.nodeModules = nodeModules; self.artifacts = artifacts
        for m in [smart.objectWillChange, trash.objectWillChange, orphans.objectWillChange,
                  big.objectWillChange, nodeModules.objectWillChange, artifacts.objectWillChange] {
            m.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
    }

    var isRunning: Bool { runner != nil }

    /// Starts a session. A model that is already scanning is not restarted (its run is adopted).
    /// Call it where `smart.load(force: true)` was called (after the C9 running-apps prompt).
    func start() {
        guard runner == nil else { return }
        let sid = UUID()
        sessionID = sid
        startedAt = Date()
        finishedAt = nil
        cancelled = false
        scope = ModuleID.allCases
        launched = [.appCaches, .developerCaches]
        if !smart.scanning { smart.load(force: true) }
        runner = Task { [weak self] in
            guard let self else { return }
            await self.waitWhile { self.smart.scanning }
            for step in [ModuleID.trash, .leftovers, .largeFiles, .devProjects] {
                if Task.isCancelled { break }
                self.launched.insert(step)
                switch step {
                case .trash:
                    if !self.trash.measuring { self.trash.refresh() }
                    await self.waitWhile { self.trash.measuring }
                case .leftovers:
                    if !self.orphans.scanning { self.orphans.scan() }
                    await self.waitWhile { self.orphans.scanning }
                case .largeFiles:
                    if !self.big.scanning { self.big.scan(scope: self.big.scope) }
                    await self.waitWhile { self.big.scanning }
                case .devProjects:
                    if !self.nodeModules.scanning { self.nodeModules.scan() }
                    if !self.artifacts.scanning { self.artifacts.scan() }
                    await self.waitWhile { self.nodeModules.scanning || self.artifacts.scanning }
                default: break
                }
            }
            // A cancelled run must not touch a session started after it.
            guard self.sessionID == sid, !Task.isCancelled else { return }
            self.finishedAt = Date()
            self.runner = nil
        }
    }

    /// Stops every module of the session; results so far stay and read as cancelled/partial.
    func cancel() {
        guard runner != nil else { return }
        runner?.cancel()
        runner = nil
        cancelled = true
        finishedAt = Date()
        smart.stop()
        if launched.contains(.leftovers) { orphans.stop() }
        if launched.contains(.largeFiles) { big.stop() }
        if launched.contains(.devProjects) { nodeModules.stop(); artifacts.stop() }
    }

    private func waitWhile(_ busy: @escaping () -> Bool) async {
        while busy() && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: Module status

    var modules: [Module] { (scope.isEmpty ? ModuleID.allCases : scope).map(module) }

    private func lifecycle(_ id: ModuleID, _ s: ScanState, issues: [ScanIssue]) -> SmartScanModuleState {
        if sessionID != nil && !launched.contains(id) { return cancelled ? .cancelled : .queued }
        switch s {
        case .idle: return .idle
        case .scanning: return .running
        case .stopped: return .cancelled
        case .completed: return issues.isEmpty ? .completed : .partial
        }
    }

    private func known(_ st: SmartScanModuleState) -> Bool {
        [.completed, .partial, .cancelled, .permissionDenied].contains(st)
    }

    func module(_ id: ModuleID) -> Module {
        switch id {
        case .appCaches, .developerCaches:
            let want: SmartScanModuleID = id == .appCaches ? .appCaches : .developerCaches
            guard let m = smart.scanModules().first(where: { $0.id == want }) else {
                return Module(id: id, state: .idle, itemCount: nil, bytes: nil, issues: [])
            }
            let ok = known(m.state)
            return Module(id: id, state: m.state, itemCount: ok ? m.itemCount : nil, bytes: ok ? m.bytes : nil, issues: m.issues)
        case .trash:
            let st: SmartScanModuleState
            if sessionID != nil && !launched.contains(.trash) { st = cancelled ? .cancelled : .queued }
            else if trash.measuring { st = .running }
            else if let _ = trash.summary { st = .completed }
            else { st = launched.contains(.trash) ? .permissionDenied : .idle }
            return Module(id: id, state: st, itemCount: trash.summary?.items, bytes: trash.summary?.bytes,
                          issues: st == .permissionDenied ? [ScanIssue(root: "~/.Trash", kind: .noPermission)] : [])
        case .leftovers:
            let st = lifecycle(id, orphans.scanState, issues: orphans.issues)
            return Module(id: id, state: st, itemCount: known(st) ? orphans.items.count : nil,
                          bytes: known(st) ? orphans.totalBytes : nil, issues: orphans.issues)
        case .largeFiles:
            let st = lifecycle(id, big.scanState, issues: big.issues)
            return Module(id: id, state: st, itemCount: known(st) ? big.count : nil,
                          bytes: known(st) ? big.rows.reduce(0) { $0 + $1.size } : nil, issues: big.issues)
        case .devProjects:
            let combined: ScanState = [nodeModules.scanState, artifacts.scanState].contains(.scanning) ? .scanning
                : [nodeModules.scanState, artifacts.scanState].contains(.stopped) ? .stopped
                : [nodeModules.scanState, artifacts.scanState].allSatisfy { $0 == .completed } ? .completed : .idle
            let issues = nodeModules.issues + artifacts.issues
            let st = lifecycle(id, combined, issues: issues)
            let t = devInventoryTotals(devInventory(caches: [], projects: nodeModules.items, artifacts: artifacts.items))
            return Module(id: id, state: st, itemCount: known(st) ? nodeModules.items.count + artifacts.items.count : nil,
                          bytes: known(st) ? t.knownBytes : nil, issues: issues)
        }
    }

    // MARK: Totals

    /// Everything the session measured, each path once (nested paths and overlaps between modules
    /// counted once; the Trash is a separate location and is added). Lower bound while running.
    var foundBytes: Int64 {
        var sizes: [(path: String, bytes: Int64)] = pathSizes(of: smart.items)
        if launched.contains(.leftovers) {
            sizes += orphans.items.compactMap { o in o.size.map { (o.path.standardizedFileURL.path, $0) } }
        }
        if launched.contains(.largeFiles) { sizes += big.rows.map { ($0.url.standardizedFileURL.path, $0.size) } }
        if launched.contains(.devProjects) {
            sizes += nodeModules.items.map { (NMModel.nodeModulesURL($0).standardizedFileURL.path, $0.size) }
            sizes += artifacts.items.compactMap { a in a.bytes.map { (a.path, $0) } }
        }
        let trashBytes = launched.contains(.trash) ? (trash.summary?.bytes ?? 0) : 0
        return contentsUnionSize(sizes) + trashBytes
    }

    /// What the one-click Clean would take (C8, unchanged): nil until the cache scan finished.
    var suggestedBytes: Int64? { smart.smartCleanPlan()?.bytes }

    /// No module failed to read anything and none was stopped.
    var isComplete: Bool {
        finishedAt != nil && !cancelled && modules.allSatisfy { $0.state == .completed }
    }
}
