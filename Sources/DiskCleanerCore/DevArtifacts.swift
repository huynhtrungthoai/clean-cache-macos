import Foundation

// ── V2-DEV layer 2: per-project build output and environments (owner decision 07/11/2026) ──
//
// Owner: build output, venvs, SDK/simulators/AI models are *listed* and the user *ticks* what to
// clean. So every artifact here is `redo` tier: never bulk/group-selected, always a manual tick,
// always through the Trash (undoable). A folder name alone is never enough (plan-v2 §6.7): each
// detection needs evidence next to it — a project manifest, a `.gitignore` rule, a CACHEDIR.TAG
// signature or `pyvenv.cfg`. Docker stays view-only: cleaning it means running docker commands,
// not moving files to the Trash.

public enum DevArtifactType: String, CaseIterable, Sendable {
    case nextBuild = "next_build"          // .next            + package.json
    case nuxtBuild = "nuxt_build"          // .nuxt / .output  + package.json + nuxt.config.*
    case turboCache = "turbo_cache"        // .turbo           + package.json
    case svelteKit = "svelte_kit"          // .svelte-kit      + package.json
    case parcelCache = "parcel_cache"      // .parcel-cache    + package.json
    case angularCache = "angular_cache"    // .angular         + angular.json
    case jsOutput = "js_output"            // dist/build/out/coverage + package.json + listed in .gitignore
    case rustTarget = "rust_target"        // target + Cargo.toml
    case mavenTarget = "maven_target"      // target + pom.xml
    case gradleBuild = "gradle_build"      // build / .gradle + build.gradle(.kts) or settings.gradle(.kts)
    case swiftBuild = "swiftpm_build"      // .build + Package.swift
    case cocoaPods = "cocoapods_pods"      // Pods + Podfile.lock
    case taggedCache = "cachedir_tagged"   // any folder with a valid CACHEDIR.TAG
    case pythonVenv = "python_venv"        // folder with pyvenv.cfg

    public var titleKey: String {
        switch self {
        case .nextBuild: return "Next.js build output"
        case .nuxtBuild: return "Nuxt build output"
        case .turboCache: return "Turborepo cache"
        case .svelteKit: return "SvelteKit build output"
        case .parcelCache: return "Parcel cache"
        case .angularCache: return "Angular cache"
        case .jsOutput: return "Build output (ignored by Git)"
        case .rustTarget: return "Rust build output"
        case .mavenTarget: return "Maven build output"
        case .gradleBuild: return "Gradle build output"
        case .swiftBuild: return "Swift package build output"
        case .cocoaPods: return "CocoaPods dependencies"
        case .taggedCache: return "Tagged cache folder"
        case .pythonVenv: return "Python virtual environment"
        }
    }

    public var kind: DevDataKind {
        switch self {
        case .pythonVenv: return .environment
        case .cocoaPods: return .dependency
        default: return .buildOutput
        }
    }

    public var ecosystem: DevEcosystem {
        switch self {
        case .nextBuild, .nuxtBuild, .turboCache, .svelteKit, .parcelCache, .angularCache, .jsOutput: return .javascript
        case .rustTarget: return .rust
        case .mavenTarget, .gradleBuild: return .jvm
        case .swiftBuild, .cocoaPods: return .apple
        case .pythonVenv: return .python
        case .taggedCache: return .other
        }
    }
}

public struct DevArtifact: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let projectRoot: String
    public let type: DevArtifactType
    /// The files that proved it, relative to the project root (`Cargo.toml`, `.gitignore`…).
    public let evidence: [String]
    /// Regenerate command when the tool is known (text only, never run).
    public let reinstallHint: String?
    public var bytes: Int64? = nil
    /// Part of it could not be read: `bytes` is a lower bound.
    public var partial = false
    public var selected = false

    public init(path: String, projectRoot: String, type: DevArtifactType, evidence: [String],
                reinstallHint: String?, bytes: Int64? = nil, partial: Bool = false, selected: Bool = false) {
        self.path = path; self.projectRoot = projectRoot; self.type = type; self.evidence = evidence
        self.reinstallHint = reinstallHint; self.bytes = bytes; self.partial = partial; self.selected = selected
    }
}

/// Does this `.gitignore` text ignore a top-level folder `name`? Only plain rules count
/// (`name`, `/name`, `name/`, `/name/`, `**/name`, `**/name/`); a later `!name` negation wins.
public func gitignoreIgnores(_ text: String, name: String) -> Bool {
    var ignored = false
    let forms: Set<String> = [name, "/\(name)", "\(name)/", "/\(name)/", "**/\(name)", "**/\(name)/"]
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line.hasPrefix("!") {
            if forms.contains(String(line.dropFirst())) { ignored = false }
        } else if forms.contains(line) {
            ignored = true
        }
    }
    return ignored
}

/// Standard CACHEDIR.TAG signature (https://bford.info/cachedir/).
let cachedirSignature = "Signature: 8a477f597d28d172789f06886806bc55"

private func exists(_ dir: String, _ name: String) -> Bool {
    FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(name))
}

private func firstExisting(_ dir: String, _ names: [String]) -> String? { names.first { exists(dir, $0) } }

/// Is the folder `dir` (named `name`, inside project folder `parent`) a build artifact or
/// environment, and on what evidence? Reads only marker files, never content of the folder.
public func detectDevArtifact(dir: String, name: String, parent: String) -> DevArtifact? {
    func make(_ t: DevArtifactType, _ ev: [String], _ hint: String? = nil) -> DevArtifact {
        DevArtifact(path: dir, projectRoot: parent, type: t, evidence: ev, reinstallHint: hint)
    }
    if exists(dir, "pyvenv.cfg") {
        let hint: String?
        if exists(parent, "uv.lock") { hint = "uv sync" }
        else if exists(parent, "poetry.lock") { hint = "poetry install" }
        else if exists(parent, "Pipfile.lock") { hint = "pipenv install" }
        else if exists(parent, "requirements.txt") { hint = "pip install -r requirements.txt" }
        else { hint = nil }
        return make(.pythonVenv, [name + "/pyvenv.cfg"], hint)
    }
    let hasPackage = exists(parent, "package.json")
    switch name {
    case ".next" where hasPackage: return make(.nextBuild, ["package.json"])
    case ".nuxt", ".output":
        if hasPackage, let cfg = firstExisting(parent, ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs"]) {
            return make(.nuxtBuild, ["package.json", cfg])
        }
    case ".turbo" where hasPackage: return make(.turboCache, ["package.json"])
    case ".svelte-kit" where hasPackage: return make(.svelteKit, ["package.json"])
    case ".parcel-cache" where hasPackage: return make(.parcelCache, ["package.json"])
    case ".angular" where exists(parent, "angular.json"): return make(.angularCache, ["angular.json"])
    case "dist", "build", "out", "coverage":
        if hasPackage, let gi = try? String(contentsOfFile: (parent as NSString).appendingPathComponent(".gitignore"), encoding: .utf8),
           gitignoreIgnores(gi, name: name) {
            return make(.jsOutput, ["package.json", ".gitignore"])
        }
    case "target":
        if exists(parent, "Cargo.toml") { return make(.rustTarget, ["Cargo.toml"], "cargo build") }
        if exists(parent, "pom.xml") { return make(.mavenTarget, ["pom.xml"], "mvn package") }
    case ".build" where exists(parent, "Package.swift"): return make(.swiftBuild, ["Package.swift"], "swift build")
    case "Pods" where exists(parent, "Podfile.lock"): return make(.cocoaPods, ["Podfile.lock"], "pod install")
    default: break
    }
    if name == "build" || name == ".gradle",
       let g = firstExisting(parent, ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]) {
        return make(.gradleBuild, [g], "gradle build")
    }
    if let tag = try? String(contentsOfFile: (dir as NSString).appendingPathComponent("CACHEDIR.TAG"), encoding: .utf8),
       tag.hasPrefix(cachedirSignature) {
        return make(.taggedCache, [name + "/CACHEDIR.TAG"])
    }
    return nil
}

/// Folders never walked into: VCS data, dependencies counted by the node_modules scan, the
/// Trash, and app bundles/packages.
let devWalkSkip: Set<String> = [".git", ".hg", ".svn", "node_modules", ".Trash"]

public struct DevArtifactScan: Sendable {
    public var artifacts: [DevArtifact]
    /// Folders that could not be listed (permissions): results under them are missing.
    public var unreadable: [String]
}

/// Walks `roots` (default: the top-level folders of home except `Library` and dot-folders —
/// projects do not live in tool state) and returns detected artifacts, measured.
/// Never follows symlinks, never crosses volumes, never descends into a detected artifact.
/// Artifacts under `minBytes` are dropped as noise.
public func findDevArtifacts(roots: [String]? = nil, minBytes: Int64 = 1_000_000,
                             progress: ScanProgress? = nil) async -> DevArtifactScan {
    let fm = FileManager.default
    let home = homePath()
    let starts: [String] = roots ?? ((try? fm.contentsOfDirectory(atPath: home)) ?? []).sorted().compactMap { k in
        guard !k.hasPrefix("."), k != "Library" else { return nil }
        return (home as NSString).appendingPathComponent(k)
    }
    var found: [DevArtifact] = []
    var unreadable: [String] = []
    for root in starts {
        if Task.isCancelled { break }
        var rs = stat()
        guard lstat(root, &rs) == 0, (rs.st_mode & S_IFMT) == S_IFDIR else { continue }
        var stack = [root]
        while let d = stack.popLast() {
            if Task.isCancelled { break }
            let kids: [String]
            do { kids = try fm.contentsOfDirectory(atPath: d) } catch {
                let posix = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code
                if posix == Int(EPERM) || posix == Int(EACCES) { unreadable.append(d) }
                continue
            }
            for k in kids where !devWalkSkip.contains(k) {
                let p = (d as NSString).appendingPathComponent(k)
                var st = stat()
                guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_dev == rs.st_dev else { continue }
                if k.hasSuffix(".app") || k.hasSuffix(".photoslibrary") || k.hasSuffix(".xcarchive") { continue }
                if let a = detectDevArtifact(dir: p, name: k, parent: d), isReclaimableWhole(URL(fileURLWithPath: p)) {
                    found.append(a)
                    continue
                }
                stack.append(p)
            }
            progress?.walk(files: kids.count, bytes: 0, in: d)
        }
    }
    // Measure (bounded concurrency through the task group's natural scheduling).
    var measured: [DevArtifact] = []
    await withTaskGroup(of: DevArtifact.self) { group in
        for a in found {
            group.addTask {
                var m = a
                let r = await dirSizeReport(URL(fileURLWithPath: a.path))
                m.bytes = r.bytes
                m.partial = !r.needFullDiskAccess.isEmpty || !r.needAdmin.isEmpty
                return m
            }
        }
        for await m in group where (m.bytes ?? 0) >= minBytes || m.partial { measured.append(m) }
    }
    measured.sort { ($0.bytes ?? 0, $1.path) > ($1.bytes ?? 0, $0.path) }
    return DevArtifactScan(artifacts: measured, unreadable: unreadable)
}
