import AppKit
import Foundation

// ── 本地化：中文原文当 key，其余每种语言各维护一份译文 ──
//
// 为什么不用 SPM 的 .process(.strings) + Bundle.module：见 docs/ARCHITECTURE.md §4.1，
// Bundle.module 在手工拼的 .app 里会 fatalError 并把构建机绝对路径烧进二进制。
// 这里走 Apple 的正路：Contents/Resources/<语言>.lproj/Localizable.strings +
// CFBundleDevelopmentRegion，运行时自己挑 .lproj 目录，`swift run` 也能用。
//
// 三条规矩：
// 1. 界面里所有中文一律包进 L("…")，带变量的写成 L("已选 %d 项") + String(format:)；
// 2. 拉丁语言的量词要分单复数，由 cnt() 按数字挑（中文与日韩没这烦恼）；
// 3. 漏译不会崩，退回显示中文——所以 build.sh 有覆盖率断言，漏一条就构建失败。
//
// 加一门语言 = 建一个 Sources/DiskCleaner/Resources/<语言>.lproj/Localizable.strings
// （简体中文除外，它的文案就是源码原文），再加下面一个 case。
// 闸门与构建脚本都按目录自动发现语言，不存在第二份需要同步的名单。
//
// 界面语言的清单按「这门语言有多少人真的会用这个 App」排，不按字母：
// 简繁中文、英、日、韩、德、西、法、俄、巴葡。

enum AppLanguage: String, CaseIterable {
    case system
    case en
    case vi
    case ja
    case ko
    case de
    case es
    case fr
    case ru
    case ptBR

    /// 写进 AppleLanguages 的语言码，同时也是词表目录名（`<code>.lproj`）。
    var code: String {
        switch self {
        case .system: return ""
        case .en: return "en"
        case .vi: return "vi"
        case .ja: return "ja"
        case .ko: return "ko"
        case .de: return "de"
        case .es: return "es"
        case .fr: return "fr"
        case .ru: return "ru"
        case .ptBR: return "pt-BR"
        }
    }

    /// 选择器上的短标签。语言名用自称，不查词表；只有「自动」是界面文案。
    ///
    /// 自称这几条必须挂 `l10n-scan: skip`：`hasHan` 认得出「繁體中文」「日本語」里的汉字，
    /// 不标就会被当成待译词条收进闸门，然后要求八种语言各译一遍「日本語」——
    /// 一种语言的名字不该被翻译。
    var menuLabel: String {
        switch self {
        case .system: return L("Automatic")
        case .en: return "English"
        case .vi: return "Tiếng Việt"
        case .ja: return "日本語"           // l10n-scan: skip 语言自称
        case .ko: return "한국어"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .fr: return "Français"
        case .ru: return "Русский"
        case .ptBR: return "Português"
        }
    }
}

enum L10n {
    /// 用户选择：nil = 跟随系统
    static let choiceKey = "diskcleaner.language"

    static var choice: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: choiceKey),
                  let v = AppLanguage(rawValue: raw) else { return .system }
            return v
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: choiceKey) }
    }

    /// 启动时系统给的语言。选「自动」时一直用它——本会话写进 AppleLanguages 的
    /// 覆盖不该反过来让「自动」在运行中变卦。
    private static let systemResolved: AppLanguage = match(Locale.preferredLanguages.first ?? "en")

    /// 系统语言标签 → 我们支持的哪一门。
    ///
    /// 按前缀认，因为同一门语言的标签长得五花八门（`zh-Hant-TW`、`pt-BR`、`es-419`）。
    /// 中文要先分简繁：`zh` 后面跟着 hant / tw / hk / mo 的都算繁体，其余（含光秃秃的
    /// `zh`）算简体。认不出来就退回英文——退回中文会让一门没有词表的语言显示成简体，
    /// 那比显示英文更不像话。
    static func match(_ tag: String) -> AppLanguage {
        let t = tag.lowercased().replacingOccurrences(of: "_", with: "-")
        if t.hasPrefix("ja") { return .ja }
        if t.hasPrefix("ko") { return .ko }
        if t.hasPrefix("vi") { return .vi }
        if t.hasPrefix("de") { return .de }
        if t.hasPrefix("es") { return .es }
        if t.hasPrefix("fr") { return .fr }
        if t.hasPrefix("ru") { return .ru }
        if t.hasPrefix("pt") { return .ptBR }
        return .en
    }

    private static func resolve(_ c: AppLanguage) -> AppLanguage {
        c == .system ? systemResolved : c
    }

    /// 当前实际生效的语言。切换由 AppStore.setLanguage 走 apply，
    /// 改完还要发布一次状态让界面重画——所以它不是常量。
    static var active: AppLanguage = resolve(SnapshotMode.requestedLang ?? choice)

    /// 换词表：下一次取文案就生效
    static func apply(_ lang: AppLanguage) { active = resolve(lang) }

    private static var tableCode: String?
    private static var table: Bundle = .main

    private static var resolved: Bundle {
        let code = active.code
        if code != tableCode {
            tableCode = code
            table = bundle(for: code)
        }
        return table
    }

    private static func bundle(for code: String) -> Bundle {
        if let u = Bundle.main.url(forResource: code, withExtension: "lproj"),
           let b = Bundle(url: u) {
            return b
        }
        // `swift run`：Bundle.main 是 .build/release 里的裸二进制，去源码树里找
        let dev = FileManager.default.currentDirectoryPath
        let candidate = (dev as NSString).appendingPathComponent("Sources/DiskCleaner/Resources/\(code).lproj")
        if FileManager.default.fileExists(atPath: candidate), let b = Bundle(url: URL(fileURLWithPath: candidate)) {
            return b
        }
        return .main
    }

    /// 简体中文：源码里的中文原文就是它的文案，压根不必查表。

    /// 汉字排版（简繁都算）。
    ///
    /// 标题字距是照着汉字调的——方块字要透气，衬线皮肤得给到 0.8/1.2；同一套值套到拉丁
    /// 字母上会散成一排省略号。全角标点也按这条分，所以繁体不能只改 `isChinese`：
    /// 它的文案要走词表，但排版规矩跟简体一模一样。

    /// Keys are the English source text: a missing translation falls back to English.
    static func string(_ key: String) -> String {
        resolved.localizedString(forKey: key, value: key, table: nil)
    }

    /// 切语言：记住选择，并写 AppleLanguages 让下次启动时系统级一致。
    /// 本次会话的生效走 apply，不靠重启。
    static func setChoice(_ lang: AppLanguage) {
        choice = lang
        if lang == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang.code], forKey: "AppleLanguages")
        }
    }
}

/// 界面文案。中文原文即 key，所以源码里看见的中文就是兜底文案。
@inline(__always)
func L(_ key: String) -> String { L10n.string(key) }

@inline(__always)
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

/// 中文量词 → 带数量的文案。简体直接拼；繁体换一张换算表；其余语言查单复数表。
func cnt(_ n: Int, _ unit: String) -> String {
    // 千分位在这里统一加，而不是各页自己格式化：整盘扫描的读数动辄六位
    // （实测 306772 个目录项），有的写「306,772」有的写「306772」，
    // 同一屏两处长得不一样的数会被读成两个不同的量。
    let head = n.formatted(.number.grouping(.automatic))
    guard let forms = measureWords(L10n.active)[unit] else { return "\(head) \(unit)" }
    return "\(head)\(measureGap(L10n.active))\(forms.form(n, in: L10n.active))"
}

/// 数词与量词之间的间隔。拉丁与西里尔语系用空格（`6 files`），
/// 韩语的量词紧贴数词（`6개 파일`），中间插一个空格就是错字。
/// 日语维持空格，与本表里「6 つのスキン」那类写法一致。
private func measureGap(_ lang: AppLanguage) -> String {
    lang == .ko ? "" : " "
}

// MARK: - 非中文语言的量词表
//
// 中文（含繁体）不必查表：简体直接拼，繁体在 cnt() 里换一张换算表。
// 这门语言之外，量词要按各自的正字法变形——这正是 cnt() 存在的理由。
//
// 表里的 key 是源码里那串简体中文，值只是三种数形态的译文，所以整块圈在
// l10n-scan: off 里：这些中文是查表入参，不是界面词条，不该进 Localizable.strings。
// 加一门语言 = 在这里添一张表 + AppLanguage 里加一个 case，没有第三处要同步。
// l10n-scan: off

/// 一个量词在三种数形态下的写法。多数语言只用得上 one / many 两形，
/// 俄语还要 few（2–4 那档），日韩三形相同。
private struct MeasureForms {
    let one: String
    let few: String
    let many: String

    init(_ one: String, _ many: String) { self.init(one, many, many) }

    init(_ one: String, _ few: String, _ many: String) {
        self.one = one
        self.few = few
        self.many = many
    }

    /// 按数字挑形态。
    ///
    /// 俄语的规则看末位与末两位：末位 1 且末两位不是 11 用 one；末位 2–4 且末两位
    /// 不是 12–14 用 few；其余（含 0、5–20、25–30……）用 many。11–14 之所以要单独
    /// 排除，是因为它们末位是 1–4 却全归 many——「11 файлов」不是「11 файл」。
    func form(_ n: Int, in lang: AppLanguage) -> String {
        switch lang {
        case .ja, .ko:
            return one                      // 日韩不分单复数
        case .ru:
            let m10 = n % 10, m100 = n % 100
            if m10 == 1 && m100 != 11 { return one }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
            return many
        default:
            return n == 1 ? one : many
        }
    }
}

/// 取一门语言的量词表。zh-Hans / zh-Hant 走不到这里（cnt 里已经分流）。
private func measureWords(_ lang: AppLanguage) -> [String: MeasureForms] {
    switch lang {
    case .vi:
        return [
            "items": MeasureForms("mục", "mục"),
            "files": MeasureForms("file", "file"),
            "folders": MeasureForms("thư mục", "thư mục"),
            "copies": MeasureForms("bản sao", "bản sao"),
            "leftovers": MeasureForms("mục còn sót", "mục còn sót"),
            "projects": MeasureForms("dự án", "dự án"),
            "groups": MeasureForms("nhóm", "nhóm"),
            "shares": MeasureForms("bản", "bản"),
            "days": MeasureForms("ngày", "ngày"),
            "minutes": MeasureForms("phút", "phút"),
            "duplicate groups": MeasureForms("nhóm trùng", "nhóm trùng"),
            "apps": MeasureForms("ứng dụng", "ứng dụng"),
            "packages": MeasureForms("gói", "gói"),
            "node_modules folders": MeasureForms("node_modules", "node_modules"),
            "cleanable items": MeasureForms("mục có thể dọn", "mục có thể dọn"),
            "suspicious spots": MeasureForms("mục cần xem", "mục cần xem"),
            "times": MeasureForms("lần", "lần"),
            "operations": MeasureForms("thao tác", "thao tác"),
            "skins": MeasureForms("giao diện", "giao diện"),
            "extra copies": MeasureForms("bản sao dư", "bản sao dư"),
            "entries": MeasureForms("mục", "mục"),
            "environments": MeasureForms("môi trường", "môi trường"),
            "spots": MeasureForms("vị trí", "vị trí"),
        ]
    case .ja:
        return [
            "items": MeasureForms("件", "件"),
            "files": MeasureForms("ファイル", "ファイル"),
            "folders": MeasureForms("フォルダ", "フォルダ"),
            "copies": MeasureForms("コピー", "コピー"),
            "leftovers": MeasureForms("件の残存データ", "件の残存データ"),
            "projects": MeasureForms("プロジェクト", "プロジェクト"),
            "groups": MeasureForms("グループ", "グループ"),
            "shares": MeasureForms("コピー", "コピー"),
            "days": MeasureForms("日", "日"),
            "minutes": MeasureForms("分", "分"),
            "duplicate groups": MeasureForms("件の重複グループ", "件の重複グループ"),
            "apps": MeasureForms("アプリ", "アプリ"),
            "packages": MeasureForms("パッケージ", "パッケージ"),
            "node_modules folders": MeasureForms("node_modules", "node_modules"),
            "cleanable items": MeasureForms("件の削除候補", "件の削除候補"),
            "suspicious spots": MeasureForms("件の要注意", "件の要注意"),
            "times": MeasureForms("回", "回"),
            "operations": MeasureForms("回の操作", "回の操作"),
            "skins": MeasureForms("スキン", "スキン"),
            "extra copies": MeasureForms("件の余分なコピー", "件の余分なコピー"),
            "entries": MeasureForms("件", "件"),
            "environments": MeasureForms("環境", "環境"),
            "spots": MeasureForms("箇所", "箇所"),
        ]
    case .ko:
        return [
            "items": MeasureForms("개 항목", "개 항목"),
            "files": MeasureForms("개 파일", "개 파일"),
            "folders": MeasureForms("개 폴더", "개 폴더"),
            "copies": MeasureForms("개 사본", "개 사본"),
            "leftovers": MeasureForms("개 잔여 항목", "개 잔여 항목"),
            "projects": MeasureForms("개 프로젝트", "개 프로젝트"),
            "groups": MeasureForms("개 그룹", "개 그룹"),
            "shares": MeasureForms("개 사본", "개 사본"),
            "days": MeasureForms("일", "일"),
            "minutes": MeasureForms("분", "분"),
            "duplicate groups": MeasureForms("개 중복 그룹", "개 중복 그룹"),
            "apps": MeasureForms("개 앱", "개 앱"),
            "packages": MeasureForms("개 패키지", "개 패키지"),
            "node_modules folders": MeasureForms("개 node_modules", "개 node_modules"),
            "cleanable items": MeasureForms("개 정리 항목", "개 정리 항목"),
            "suspicious spots": MeasureForms("개 의심 항목", "개 의심 항목"),
            "times": MeasureForms("회", "회"),
            "operations": MeasureForms("회 작업", "회 작업"),
            "skins": MeasureForms("개 스킨", "개 스킨"),
            "extra copies": MeasureForms("개 중복 사본", "개 중복 사본"),
            "entries": MeasureForms("개 항목", "개 항목"),
            "environments": MeasureForms("개 환경", "개 환경"),
            "spots": MeasureForms("개 위치", "개 위치"),
        ]
    case .de:
        return [
            "items": MeasureForms("Eintrag", "Einträge"),
            "files": MeasureForms("Datei", "Dateien"),
            "folders": MeasureForms("Ordner", "Ordner"),
            "copies": MeasureForms("Kopie", "Kopien"),
            "leftovers": MeasureForms("Überrest", "Überreste"),
            "projects": MeasureForms("Projekt", "Projekte"),
            "groups": MeasureForms("Gruppe", "Gruppen"),
            "shares": MeasureForms("Kopie", "Kopien"),
            "days": MeasureForms("Tag", "Tage"),
            "minutes": MeasureForms("Minute", "Minuten"),
            "duplicate groups": MeasureForms("Duplikatgruppe", "Duplikatgruppen"),
            "apps": MeasureForms("App", "Apps"),
            "packages": MeasureForms("Paket", "Pakete"),
            "node_modules folders": MeasureForms("node_modules-Ordner", "node_modules-Ordner"),
            "cleanable items": MeasureForms("löschbarer Eintrag", "löschbare Einträge"),
            "suspicious spots": MeasureForms("verdächtige Stelle", "verdächtige Stellen"),
            "times": MeasureForms("Mal", "Mal"),
            "operations": MeasureForms("Aktion", "Aktionen"),
            "skins": MeasureForms("Skin", "Skins"),
            "extra copies": MeasureForms("überzählige Kopie", "überzählige Kopien"),
            "entries": MeasureForms("Eintrag", "Einträge"),
            "environments": MeasureForms("Umgebung", "Umgebungen"),
            "spots": MeasureForms("Stelle", "Stellen"),
        ]
    case .es:
        return [
            "items": MeasureForms("elemento", "elementos"),
            "files": MeasureForms("archivo", "archivos"),
            "folders": MeasureForms("carpeta", "carpetas"),
            "copies": MeasureForms("copia", "copias"),
            "leftovers": MeasureForms("residuo", "residuos"),
            "projects": MeasureForms("proyecto", "proyectos"),
            "groups": MeasureForms("grupo", "grupos"),
            "shares": MeasureForms("copia", "copias"),
            "days": MeasureForms("día", "días"),
            "minutes": MeasureForms("minuto", "minutos"),
            "duplicate groups": MeasureForms("grupo duplicado", "grupos duplicados"),
            "apps": MeasureForms("app", "apps"),
            "packages": MeasureForms("paquete", "paquetes"),
            "node_modules folders": MeasureForms("carpeta node_modules", "carpetas node_modules"),
            "cleanable items": MeasureForms("elemento limpiable", "elementos limpiables"),
            "suspicious spots": MeasureForms("punto sospechoso", "puntos sospechosos"),
            "times": MeasureForms("vez", "veces"),
            "operations": MeasureForms("operación", "operaciones"),
            "skins": MeasureForms("aspecto", "aspectos"),
            "extra copies": MeasureForms("copia extra", "copias extra"),
            "entries": MeasureForms("entrada", "entradas"),
            "environments": MeasureForms("entorno", "entornos"),
            "spots": MeasureForms("punto", "puntos"),
        ]
    case .fr:
        return [
            "items": MeasureForms("élément", "éléments"),
            "files": MeasureForms("fichier", "fichiers"),
            "folders": MeasureForms("dossier", "dossiers"),
            "copies": MeasureForms("copie", "copies"),
            "leftovers": MeasureForms("résidu", "résidus"),
            "projects": MeasureForms("projet", "projets"),
            "groups": MeasureForms("groupe", "groupes"),
            "shares": MeasureForms("copie", "copies"),
            "days": MeasureForms("jour", "jours"),
            "minutes": MeasureForms("minute", "minutes"),
            "duplicate groups": MeasureForms("groupe de doublons", "groupes de doublons"),
            "apps": MeasureForms("app", "apps"),
            "packages": MeasureForms("paquet", "paquets"),
            "node_modules folders": MeasureForms("dossier node_modules", "dossiers node_modules"),
            "cleanable items": MeasureForms("élément nettoyable", "éléments nettoyables"),
            "suspicious spots": MeasureForms("emplacement suspect", "emplacements suspects"),
            "times": MeasureForms("fois", "fois"),
            "operations": MeasureForms("opération", "opérations"),
            "skins": MeasureForms("apparence", "apparences"),
            "extra copies": MeasureForms("copie en trop", "copies en trop"),
            "entries": MeasureForms("entrée", "entrées"),
            "environments": MeasureForms("environnement", "environnements"),
            "spots": MeasureForms("emplacement", "emplacements"),
        ]
    case .ru:
        return [
            "items": MeasureForms("элемент", "элемента", "элементов"),
            "files": MeasureForms("файл", "файла", "файлов"),
            "folders": MeasureForms("папка", "папки", "папок"),
            "copies": MeasureForms("копия", "копии", "копий"),
            "leftovers": MeasureForms("остаток", "остатка", "остатков"),
            "projects": MeasureForms("проект", "проекта", "проектов"),
            "groups": MeasureForms("группа", "группы", "групп"),
            "shares": MeasureForms("копия", "копии", "копий"),
            "days": MeasureForms("день", "дня", "дней"),
            "minutes": MeasureForms("минуту", "минуты", "минут"),
            "duplicate groups": MeasureForms("группа дубликатов", "группы дубликатов", "групп дубликатов"),
            "apps": MeasureForms("приложение", "приложения", "приложений"),
            "packages": MeasureForms("пакет", "пакета", "пакетов"),
            "node_modules folders": MeasureForms("папка node_modules", "папки node_modules", "папок node_modules"),
            "cleanable items": MeasureForms("объект для очистки", "объекта для очистки", "объектов для очистки"),
            "suspicious spots": MeasureForms("подозрительное место", "подозрительных места", "подозрительных мест"),
            "times": MeasureForms("раз", "раза", "раз"),
            "operations": MeasureForms("действие", "действия", "действий"),
            "skins": MeasureForms("оформление", "оформления", "оформлений"),
            "extra copies": MeasureForms("лишняя копия", "лишние копии", "лишних копий"),
            "entries": MeasureForms("запись", "записи", "записей"),
            "environments": MeasureForms("окружение", "окружения", "окружений"),
            "spots": MeasureForms("место", "места", "мест"),
        ]
    case .ptBR:
        return [
            "items": MeasureForms("item", "itens"),
            "files": MeasureForms("arquivo", "arquivos"),
            "folders": MeasureForms("pasta", "pastas"),
            "copies": MeasureForms("cópia", "cópias"),
            "leftovers": MeasureForms("resíduo", "resíduos"),
            "projects": MeasureForms("projeto", "projetos"),
            "groups": MeasureForms("grupo", "grupos"),
            "shares": MeasureForms("cópia", "cópias"),
            "days": MeasureForms("dia", "dias"),
            "minutes": MeasureForms("minuto", "minutos"),
            "duplicate groups": MeasureForms("grupo de duplicados", "grupos de duplicados"),
            "apps": MeasureForms("app", "apps"),
            "packages": MeasureForms("pacote", "pacotes"),
            "node_modules folders": MeasureForms("pasta node_modules", "pastas node_modules"),
            "cleanable items": MeasureForms("item limpável", "itens limpáveis"),
            "suspicious spots": MeasureForms("ponto suspeito", "pontos suspeitos"),
            "times": MeasureForms("vez", "vezes"),
            "operations": MeasureForms("operação", "operações"),
            "skins": MeasureForms("tema", "temas"),
            "extra copies": MeasureForms("cópia extra", "cópias extras"),
            "entries": MeasureForms("entrada", "entradas"),
            "environments": MeasureForms("ambiente", "ambientes"),
            "spots": MeasureForms("ponto", "pontos"),
        ]
    default:
        // en，同时也是兜底：认不出的语言退回英文量词，总比拼中文强。
        return [
            "items": MeasureForms("item", "items"),
            "files": MeasureForms("file", "files"),
            "folders": MeasureForms("folder", "folders"),
            "copies": MeasureForms("copy", "copies"),
            "leftovers": MeasureForms("leftover", "leftovers"),
            "projects": MeasureForms("project", "projects"),
            "groups": MeasureForms("group", "groups"),
            "shares": MeasureForms("copy", "copies"),
            "days": MeasureForms("day", "days"),
            "minutes": MeasureForms("minute", "minutes"),
            "duplicate groups": MeasureForms("duplicate group", "duplicate groups"),
            "apps": MeasureForms("app", "apps"),
            "packages": MeasureForms("package", "packages"),
            "node_modules folders": MeasureForms("node_modules folder", "node_modules folders"),
            "cleanable items": MeasureForms("cleanable item", "cleanable items"),
            "suspicious spots": MeasureForms("suspicious spot", "suspicious spots"),
            "times": MeasureForms("time", "times"),
            "operations": MeasureForms("operation", "operations"),
            "skins": MeasureForms("skin", "skins"),
            "extra copies": MeasureForms("extra copy", "extra copies"),
            "entries": MeasureForms("entry", "entries"),
            "environments": MeasureForms("environment", "environments"),
            "spots": MeasureForms("spot", "spots"),
        ]
    }
    // l10n-scan: on
}

/// 拼接多条失败原因。汉字用全角分号，其余语言照各自的正字法来。
func errList(_ msgs: [String]) -> String {
    msgs.joined(separator: "; ")
}
