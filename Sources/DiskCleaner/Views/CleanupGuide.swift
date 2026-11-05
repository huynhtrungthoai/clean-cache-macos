import SwiftUI
import DiskCleanerCore

// ── 「清理说明」那四页 ────────────────────────────────────────────────────────
//
// **为什么要有这一套**：这一版把 1.9 的两处口径都改了——环心从「还能腾出多少」换成
// 「现在能用多少」，动手从「勾上再按主钮」换成「同一段点两下」。两处都是好改动，
// 但都会让一个用惯了 1.9 的人第一眼读错。读错的代价不是看不懂，是**按错**：
// 他以为还要先勾选，于是去点账本行，点完什么也没发生，就以为软件坏了。
// 引导页（`FirstRunView`）管不到这件事：它站在授权之前，那会儿盘上一个数都没有，
// 能讲的只有「一圈就是这块盘」。这一套讲的是**怎么动手**，必须落在有数之后。
//
// **为什么是四页而不是一屏说明文**：每页只回答一个会被误解的动作。合成一屏就变成
// 「一段产品更新公告」，没人读，读完也记不住哪一条跟自己接下来那一下有关。
// 页眉的 01/04 与页脚那四颗点就是这条约束的产物：它明说「只有四下就能走完」。
//
// **页脚只有前后两钮**（样稿同）：中间再放一颗「继续」，读起来像「继续看」，
// 干的却是关掉——一个动作两个名字。退出这一套的路子已经有三条：页眉的「跳过」、
// 点背面、Esc。最后一张那颗换成「开始用这块盘」，正向走完和就地收口合成同一下。
//
// **为什么盖在窗口上而不是 sheet**：同 `FirstRunView` 头注——截图链路只拍自己这一扇窗，
// sheet 是另一扇子窗，用 sheet 这一套一张图都拍不到。取证走
// `DISKWISE_GUIDE=1~4`（见 `SnapshotMode.guidePage`）。
//
// **右边那一栏的数全是示意的**，页内明写「示意数字，不是你这台盘的数」。这四页要讲的
// 是关系（上膛→移入、移入≠腾出），关系用假数讲最清楚；拿真盘数讲反而会把人钉在
// 自己那 6.3 GB 上，忘了这一页说的是所有段。示意的三个数自己加得起来：
// 整块盘 96.0 = 已用 80.0 + 可用 16.0；清空 6.3 之后可用 16.0 + 6.3 = 22.3。
//
// **不做逐页动画**：这一套只在第一次出现，四页加起来读十几秒。为它挂一条常驻
// 时间线，是把「说明一个交互」花成「和交互抢帧」——本项目的红线（见 `PerfProbe`）
// 不允许。页与页之间只有 SwiftUI 那一下转场。

/// 四页的内容。`kicker` 是页码那一行，`notes` 是编号那几条。
struct GuidePage: Identifiable {
    let id: Int
    let kicker: String
    let headline: String
    let lede: String
    let notes: [(String, String)]
}

/// 「清理说明」那一屏。由 `ContentView` 盖在两列之上。
struct CleanupGuide: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var systemScheme

    /// 截图链路用 `DISKWISE_GUIDE=<1~4>` 钉页；平时是用户自己翻。
    @State private var page: Int
    let onClose: () -> Void

    init(startPage: Int? = nil, onClose: @escaping () -> Void) {
        _page = State(initialValue: max(1, min(Self.pages.count, startPage ?? 1)))
        self.onClose = onClose
    }

    static let pages: [GuidePage] = [
        GuidePage(
            id: 1,
            kicker: L("01 / The number in the middle"),
            headline: L("The biggest number is no longer “can still free”"),
            lede: L("The old ring centre printed a promise: “can still free 12.9”. This version puts the space you actually have right now, and what you might reclaim moved down into the ledger."),
            notes: [
                (L("Ring centre = what's usable right now"), L("Not how much you'd have after cleaning. That number only changes once the Trash is genuinely emptied.")),
                (L("How much is reclaimable lives in the ledger"), L("Each segment's share is exactly how long its bar is; the ring centre doesn't add them up for you.")),
                (L("What wasn't measured counts separately"), L("It isn't folded into “used” — that figure shrinks at any moment, and mixing them would lie to you.")),
            ]),
        GuidePage(
            id: 2,
            kicker: L("02 / Taking action"),
            headline: L("Two clicks to actually move anything, 3 s to stand down"),
            lede: L("The first click only arms it; the second moves this segment to the Trash. During those three seconds, clicking elsewhere, switching segment or pressing Esc all stand it down."),
            notes: [
                (L("First click: just arming"), L("The ring centre reports that segment's size and the main button says what it will do; no file has been touched yet.")),
                (L("Second click: only now does it move to the Trash"), L("Click the same segment again. If you don't, it returns to normal after 3 s.")),
                (L("Clicking another segment means you changed your mind"), L("Arming moves to the new segment and the old one stands down; Esc does the same.")),
            ]),
        GuidePage(
            id: 3,
            kicker: L("03 / Where the bytes went"),
            headline: L("It's in the Trash — the space isn't back yet"),
            lede: L("This tool only does the “move to Trash” step: the bytes are still on disk and the available figure doesn't jump. Emptying is Finder's move — press it in Finder or call Finder from the Trash page, either way that's the moment the space comes back."),
            notes: [
                (L("After moving in: available doesn't move"), L("That segment on the ring only changed colour — it still occupies space.")),
                (L("After emptying: only now does available grow"), L("Finder does this step. This tool doesn't take your rubbish out for you, and doesn't clean behind your back.")),
                (L("Want a file back"), L("The Trash page can open Finder; until you empty it, the whole batch goes back as it was.")),
            ]),
        GuidePage(
            id: 4,
            kicker: L("04 / When a click does nothing"),
            headline: L("If it can't be cleaned, you're told why on the spot"),
            lede: L("Not every segment can be moved. One that can't won't pretend to be busy — it gives you the reason straight away. Anything already moved in can come back."),
            notes: [
                (L("Protected by the system"), L("Take the System Data arc: a whole root folder never moves as one piece. What's inside still gets cleaned — pick it on the other cleanup pages.")),
                (L("Outside this scope"), L("Other users' folders and the system areas at the top of the disk: we measure them and report the number, but deleting only touches your home folder, /Applications and the two temp folders.")),
                (L("Just a combined total"), L("A combined line like “Not measured” isn't one folder, so it can't move as a whole — open that row in the ledger on the right to see it block by block.")),
                (L("Moved the wrong thing: put it back"), L("The Trash page puts this batch back exactly as it was; it's all still there until you empty it.")),
            ]),
    ]

    private var current: GuidePage { Self.pages[max(0, min(page - 1, Self.pages.count - 1))] }
    private var isLast: Bool { page == Self.pages.count }

    var body: some View {
        ZStack {
            theme.palette.shadow
                .opacity(isDark ? 0.68 : 0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            sheet
                .frame(maxWidth: 860)
                .padding(.horizontal, 28)
        }
        .accessibilityAddTraits(.isModal)
        .onExitCommand(perform: onClose)
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.palette.separator)
            HStack(alignment: .top, spacing: 26) {
                copy.frame(maxWidth: .infinity, alignment: .leading)
                visual.frame(width: 268)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            Divider().background(theme.palette.separator)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .fill(theme.palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard, style: .continuous)
                .stroke(theme.palette.separator, lineWidth: theme.metric.stroke)
        )
        .shadow(color: theme.palette.shadow.opacity(isDark ? 0.62 : 0.20),
                radius: 26, y: 12)
    }

    // MARK: 页眉

    private var header: some View {
        HStack(spacing: 10) {
            Text(L("First run after upgrading · How cleaning works"))
                .font(theme.bodyFont(.caption))
                .foregroundStyle(theme.palette.inkSecondary)
            Spacer(minLength: 8)
            Text(String(format: "%02d / %02d", page, Self.pages.count))
                .font(theme.bodyFont(.caption))
                .monospacedDigit()
                .foregroundStyle(theme.palette.inkTertiary)
                .accessibilityLabel(LF("Page %1$@ of %2$@",
                                       String(page), String(Self.pages.count)))
            Button(action: onClose) {
                Text(L("Skip"))
                    .font(theme.bodyFont(.caption))
                    .foregroundStyle(theme.palette.inkTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Skip the cleanup walkthrough"))
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    // MARK: 左栏：这一页讲什么

    private var copy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(current.kicker)
                .font(theme.bodyFont(.caption))
                .tracking(0.6)
                .foregroundStyle(theme.palette.tint)
            Text(current.headline)
                .font(theme.display(.title))
                .tracking(theme.titleTracking)
                .foregroundStyle(theme.palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(current.lede)
                .font(theme.prose(size: 14))
                .foregroundStyle(theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(current.notes.enumerated()), id: \.offset) { idx, note in
                    noteRow(idx + 1, note.0, note.1)
                }
            }
            .padding(.top, 4)
        }
    }

    private func noteRow(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(String(n))
                .font(theme.bodyFont(.caption2)).monospacedDigit()
                .foregroundStyle(theme.palette.inkTertiary)
                .frame(width: 16, height: 16)
                .background(Circle().stroke(theme.palette.separator, lineWidth: theme.metric.stroke))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(theme.bodyFont(.footnote)).fontWeight(.medium)
                    .foregroundStyle(theme.palette.ink)
                Text(detail)
                    .font(theme.bodyFont(.caption2))
                    .foregroundStyle(theme.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 右栏：这一页那笔账

    private var visual: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch current.id {
            case 1: visualOne
            case 2: visualTwo
            case 3: visualThree
            default: visualFour
            }
            Text(L("Illustrative numbers, not readings from your disk"))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(theme.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard - 2, style: .continuous)
                .fill(theme.palette.surfaceAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.metric.radiusCard - 2, style: .continuous)
                .stroke(theme.palette.separator, lineWidth: theme.metric.stroke)
        )
    }

    /// 第 1 页：环心那一个大数，和它「不再是」的那句旧话。
    ///
    /// 那行小字复用总览页的同一对键（`整块盘 %1$@ · 已用 %2$@`），不另造一句：
    /// 同一屏上「整块盘 / 已用 / 可用」若两处措辞不一样，人就当成两本账——
    /// 这条规矩是 `FirstRunView.hero` 先立下的，这里照办。
    private var visualOne: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Available"))
                .font(theme.bodyFont(.caption2))
                .tracking(2.2)
                .foregroundStyle(theme.palette.tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("16.0")
                    .font(theme.display(.largeTitle))
                    .foregroundStyle(theme.palette.ink)
                Text("GB")
                    .font(theme.bodyFont(.footnote))
                    .foregroundStyle(theme.palette.inkTertiary)
            }
            Text(LF("Disk %1$@ · %2$@ used", "96.0 GB", "80.0 GB"))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(theme.palette.inkSecondary)
            Text(L("can still free 12.9"))
                .font(theme.bodyFont(.caption2))
                .strikethrough()
                .foregroundStyle(theme.palette.inkTertiary.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    /// 第 2 页：同一段的两下，中间那三秒。
    private var visualTwo: some View {
        VStack(alignment: .leading, spacing: 9) {
            stepRow(L("First click"), L("Armed · App Caches 6.3 GB"), lit: true)
            HStack(spacing: 7) {
                Rectangle().fill(theme.palette.separator).frame(height: 1)
                Text(L("Or it stands down after 3 s"))
                    .font(theme.bodyFont(.caption2))
                    .foregroundStyle(theme.palette.inkTertiary)
                Rectangle().fill(theme.palette.separator).frame(height: 1)
            }
            stepRow(L("Second click"), L("Moved to Trash +6.3 GB"), lit: false)
        }
        .accessibilityElement(children: .combine)
    }

    /// 第 3 页：移入与清空是两件事，可用数只认后者。
    private var visualThree: some View {
        VStack(alignment: .leading, spacing: 9) {
            stepRow(L("After moving in"), L("Available 16.0 GB · unchanged"), lit: false)
            HStack(spacing: 7) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.palette.inkTertiary)
                Text(L("Empty it in Finder"))
                    .font(theme.bodyFont(.caption2))
                    .foregroundStyle(theme.palette.inkTertiary)
                Spacer(minLength: 0)
            }
            stepRow(L("After emptying "), L("Available 22.3 GB"), lit: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// 第 4 页：四种「动不了」，每一种都给原因。
    private var visualFour: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(current.notes.enumerated()), id: \.offset) { _, note in
                HStack(spacing: 7) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(theme.palette.inkTertiary)
                    Text(note.0)
                        .font(theme.bodyFont(.caption))
                        .foregroundStyle(theme.palette.inkSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stepRow(_ tag: String, _ body: String, lit: Bool) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(lit ? theme.palette.onTint : theme.palette.inkTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(lit ? theme.palette.tint : theme.palette.surface))
            Text(body)
                .font(theme.bodyFont(.caption))
                .foregroundStyle(lit ? theme.palette.ink : theme.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 页脚：四颗点 + 前后

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(Self.pages) { p in
                    Button {
                        withAnimation(theme.animation) { page = p.id }
                    } label: {
                        Circle()
                            .fill(p.id == page ? theme.palette.tint : theme.palette.separator)
                            .frame(width: 6, height: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LF("Page %1$@", String(p.id)))
                }
            }
            Spacer(minLength: 0)
            Text(L("Shows once after an upgrade · reopen it any time from the ? at the top right"))
                .font(theme.bodyFont(.caption2))
                .foregroundStyle(theme.palette.inkTertiary)
                .layoutPriority(1)
            Spacer(minLength: 0)
            ThemeButton(kind: .ghost, title: L("Previous")) {
                guard page > 1 else { return }
                withAnimation(theme.animation) { page -= 1 }
            }
            .disabled(page == 1)
            // 走完最后一张与中途关掉是同一件事：都回到这块盘。所以最后一张
            // 不另起一颗钮，把「下一页」那颗改名字、换主色、改成收口。
            ThemeButton(kind: isLast ? .primary : .secondary,
                        title: isLast ? L("Start using this disk") : L("Next")) {
                if isLast { onClose() } else { withAnimation(theme.animation) { page += 1 } }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 54)
    }

    private var isDark: Bool { (theme.scheme ?? systemScheme) == .dark }
}

// MARK: - 右上角那颗「?」

/// 工具条上的「?」。复看这一套四页——样稿里它就是顶栏最右那一颗，
/// 和「声音」「重新扫描」并排，不藏进设置页：需要它的时刻是**正卡在主画面上**，
/// 而不是已经退到设置里翻的时候。
struct GuideButton: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            Prefs.shared.reopenGuide()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.palette.inkTertiary)
                .frame(width: 22, height: 22)
                .background(Circle().stroke(theme.palette.separator, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(L("How cleaning works: what changed since the last version"))
        .accessibilityLabel(L("How cleaning works"))
    }
}
