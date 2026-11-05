# CleanPilot — TODO: Lỗi tính năng, Bảo mật & Rủi ro

> Audit ngày 2026-11-05 trên commit `70beb8f`. `swift build` OK (nhiều warning Swift 6 concurrency), `swift run SelfTest` → ALL PASS.
> Mức độ: 🔴 Critical · 🟠 High · 🟡 Medium · 🟢 Low. Đánh dấu `[x]` khi xử lý xong và ghi commit.

---

## 0. Ưu tiên ngay (trước bản phát hành tiếp theo)

- [x] 🔴 **P0-1** _(đã sửa, chưa commit — `deletionGate` trong `Models.swift`)_ Vá bypass bảo vệ đường dẫn do không phân biệt hoa/thường + symlink (mục 1.1, 1.2)
- [x] 🔴 **P0-2** _(→ `com.huynhtrungthoai.cleanpilot`, ký bằng tài khoản Apple cá nhân huynhtrungthoai (`HN2G8HJ96Q`))_ Đổi bundle ID khỏi bundle ID cũ của tác giả gốc, ký bằng tài khoản cá nhân (mục 3.1)
- [x] 🟠 **P0-3** Gỡ biến môi trường `DISKWISE_HOME_SHIM` khỏi bản release (mục 1.3)
- [x] 🟠 **P0-4** _(`RELEASE=1` bắt buộc Developer ID của tài khoản cá nhân)_ Release bắt buộc Developer ID + hardened runtime + notarize, không tự rơi về ad-hoc (mục 3.3)
- [x] 🟠 **P0-5** _(website khác ngoài GA chưa rebrand — xem 3.12)_ Thay Cask / kênh báo lỗi bảo mật / liên hệ / Google Analytics đang trỏ về tác giả gốc (mục 3.2, 3.7, 3.8)
- [x] 🟠 **P0-6** Bỏ nút "Empty Trash" không xác nhận ở trang Diagnostic (mục 2.1)
- [x] 🟠 **P0-7** _(đã sửa, chưa commit — `isInSensitiveTree`/`isBulkSelectable`)_ Folder Drill: select-all không được chọn dotfile, Keychains, iCloud (mục 2.2, 1.4)
- [x] 🟠 **P0-8** Xoá file trùng: kiểm tra lại bản giữ trước khi xoá (mục 2.3)
- [x] 🟠 **P0-9** Sandbox grant chỉ chấp nhận home thật (mục 2.4)
- [x] 🟠 **P0-10** _(cổng `devHooksEnabled` + `scrubDevEnvironment()`; `DEV_HOOKS=1` để chụp screenshot)_ Bọc SnapshotMode, PerfProbe và mọi `DISKWISE_*` env trong `#if DEBUG` (mục 1.3, 2.5)

---

## 1. Lõi xoá file (DiskCleanerCore) — rủi ro mất dữ liệu

### 1.1 🔴 Bảo vệ đường dẫn chỉ so khớp chuỗi, phân biệt hoa/thường
- **File:** `Sources/DiskCleanerCore/Models.swift:400-446` (`protectedPaths`, `isProtected`, `isDeletable`), `Scanner.swift:666` (`trashItem`)
- **Vấn đề:** APFS mặc định **không phân biệt hoa/thường**, nhưng `isProtected` so sánh `Set<String>` chính xác. Đã kiểm chứng bằng `diskwise explain`:
  - `~/Library` → `protected` ✅, còn `~/LIBRARY` / `~/library` → chỉ `unknown_to_knowledge_base`
  - `~/Documents` → `protected`, còn `~/DOCUMENTS` → `unknown`
- **Hậu quả:** `diskwise plan "~/DOCUMENTS" --i-am-human` rồi `diskwise trash --plan <id>` sẽ chuyển **toàn bộ Documents/Library** vào Thùng rác (`--i-am-human` cho phép tier `unknown`).
- **Đã sửa:** `isProtected` so khớp không phân biệt hoa/thường + NFC; thêm `deletionGate()` (realpath phần cha + so lại dạng canonical) dùng trong `trashItem` và `agentPipeline`. SelfTest 15.1b (18 ca) PASS.
- **Sửa:**
  - [x] Chuẩn hoá đường dẫn trước mọi kiểm tra: `realpath()` / `URL.resolvingSymlinksInPath()` cho phần cha + lấy tên thật trên đĩa (`URLResourceKey.canonicalPathKey`), so sánh case-insensitive (`.caseInsensitive` / `lowercased()` sau canonical).
  - [ ] (tuỳ chọn, chưa làm) So sánh bằng **inode/dev** của các thư mục được bảo vệ (lấy 1 lần lúc khởi động) thay vì chuỗi.
  - [x] Thêm test SelfTest: `~/LIBRARY`, `~/Library/../LIBRARY`, `/USERS/<me>/Documents`, `~/./Desktop`.

### 1.2 🔴 Symlink ở thư mục cha không bị kiểm tra
- **File:** `AgentAPI.swift:311-333` (`agentPipeline`), `Models.swift:438`
- **Vấn đề:** `standardizedFileURL` **không resolve symlink**; pipeline chỉ `lstat` thành phần cuối. Nếu `~/x` là symlink → `~` (hoặc → `/Volumes/...`), thì `~/x/Documents` vượt qua `isProtected` và `isDeletable` (prefix `home + "/"`), rồi `FileManager.trashItem` theo symlink và chuyển thư mục thật.
- **Sửa:**
  - [x] Resolve symlink cho **phần cha** (`deletingLastPathComponent().resolvingSymlinksInPath()`), giữ nguyên thành phần cuối (để vẫn chỉ chuyển link chứ không chuyển đích).
  - [x] Từ chối nếu bất kỳ thành phần cha nào là symlink trỏ ra ngoài vùng cho phép.

### 1.3 🟠 `DISKWISE_HOME_SHIM` dời ranh giới xoá trong bản release
- **File:** `HomeAccess.swift:120-127`, `Models.swift:87-115`
- **Vấn đề:** Biến môi trường đổi `homeDir()` → đổi luôn `isDeletable`/`protectedPaths`/`applicationsDir`. CLI/MCP chạy với env do agent host cấu hình (file config MCP có trường `env`) → có thể đặt `DISKWISE_HOME_SHIM=/Users` hoặc `/` để mở rộng vùng được xoá.
- **Sửa:**
  - [x] Chỉ đọc `DISKWISE_HOME_SHIM`, `DISKWISE_STORE_SHOTS`, `DISKWISE_PERF*`, `DISKWISE_COST`, `DISKWISE_RESOURCES` trong `#if DEBUG` (hoặc build flag `DEMO`).
  - [ ] Nếu cần ở release: yêu cầu shim nằm trong `$TMPDIR` và có file marker do `make_demo_home.sh` tạo.

### 1.4 🟠 Danh sách bảo vệ quá hẹp — thư mục nhạy cảm trong HOME xoá được
- **File:** `Models.swift:400-412`
- **Vấn đề:** Chỉ bảo vệ **đúng** vài đường dẫn gốc. `~/.ssh`, `~/.gnupg`, `~/Library/Keychains`, `~/Library/Mobile Documents` (iCloud Drive), `~/Pictures/Photos Library.photoslibrary`, `~/Library/Mail`, `~/Library/Messages`, `~/.aws`, `~/.kube`, `~/.config` đều thuộc tier `unknown` → `--i-am-human` và các màn hình UI (FolderDrill, BigOld) đều xoá được.
- **Đã sửa:** `sensitiveTreeRelRoots` + `isInSensitiveTree()` trong `Models.swift` (`.ssh`, `.gnupg`, `.aws`, `.azure`, `.kube`, `.config/gcloud`, `.config/gh`, `.password-store`, `Library/Keychains`, `Mobile Documents`, `Mail`, `Messages`, `Accounts`, `Cookies`, `Calendars`, `AddressBook`, `MobileSync`, gói `*.photoslibrary`/`.musiclibrary`/`.tvlibrary`). `deletionGate` chặn cả cây (lexical + canonical); `isReclaimableWhole` khoá hàng trên UI. SelfTest 15.1c PASS.
- **Sửa:**
  - [x] Thêm "deny-list theo cây" (chặn cả thư mục **và mọi thứ bên trong**) cho credential/keychain/iCloud/Photos/Mail.
  - [ ] (không cần nữa — gate chặn trước knowledge base) Đưa các mục này vào `safety_db.json` tier `risky` để UI cũng khoá checkbox.

### 1.5 🟠 `--i-am-human` không xác thực được là người thật
- **File:** `DiskWiseCLI/main.swift:137-151`, `AgentAPI.swift:561`
- **Vấn đề:** Agent có quyền shell chỉ cần thêm cờ `--i-am-human`. Plan file lưu `human: true` và MCP `execute_cleanup` thực thi plan đó mà không phân biệt người tạo. "Show the plan to the user and get consent" trong MCP chỉ là lời khuyên.
- **Sửa:**
  - [ ] `--i-am-human` chỉ chấp nhận khi `isatty(STDIN_FILENO) && isatty(STDOUT_FILENO)` và yêu cầu gõ xác nhận (ví dụ nhập 4 ký tự ngẫu nhiên).
  - [ ] MCP `execute_cleanup` từ chối plan có `human == true`.
  - [ ] Cân nhắc: plan > N GB hoặc ngoài cache phải được xác nhận qua app GUI (notification/dialog).

### 1.6 🟡 Plan file & operations log không được bảo vệ toàn vẹn
- **Tiến độ (feat/claude-p0):** khôi phục (app `TrashBatch` lẫn `diskwise undo`) giờ chỉ đi từ thư mục Thùng rác, đúng inode, đích qua `deletionGate`; lịch sử app lưu 0600 + atomic. Chưa làm: ký HMAC plan/operation.
- **File:** `AgentAPI.swift:603-605` (ghi plan), `618-695` (`agentExecute`), `697-720` (`agentUndo`), `Scanner.swift:678-693` (`untrash`)
- **Vấn đề:**
  - Plan JSON ở `~/Library/Application Support/DiskWise/agent/plans/` có thể bị sửa (đổi `human`, `expiresAt`, thêm item). Pipeline chạy lại giảm thiểu phần lớn, nhưng cờ `human` và hạn dùng thì tin tuyệt đối.
  - `agentUndo` → `untrash` gọi `moveItem(inTrash → original)` **không kiểm tra** `inTrash` nằm trong `~/.Trash` hay `original` nằm trong vùng cho phép → sửa `operations.jsonl` là có thể dùng `undo` để di chuyển file tuỳ ý.
- **Sửa:**
  - [ ] Ký HMAC plan/operation bằng khoá lưu trong Keychain; từ chối nếu sai chữ ký.
  - [ ] `untrash`: yêu cầu `inTrash` nằm dưới `~/.Trash` (hoặc trash volume `/.Trashes/<uid>`) và `original` qua `isDeletable && !isProtected`.
  - [ ] Ghi file với quyền `0600`, thư mục `0700`; ghi atomic (`.atomic`).

### 1.7 🟡 TOCTOU giữa kiểm tra và `trashItem`
- **Tiến độ:** đường thực thi mới (`executeTrashPlan`) chạy `preflight` từng mục ngay trước khi chuyển (tồn tại, size/mtime so với lúc quét, gate). Cửa sổ race nhỏ giữa preflight và `trashItem` vẫn còn.
- **File:** `AgentAPI.swift:641-668`, các View gọi `trashItem` sau khi quét xong (mục 2)
- **Vấn đề:** Kiểm tra inode rồi mới `trashItem(url)` theo đường dẫn; cửa sổ race nhỏ (thay thư mục cha bằng symlink). Ở UI, danh sách quét có thể đã cũ nhiều phút.
- **Sửa:**
  - [ ] Mở thư mục cha bằng `open(O_DIRECTORY|O_NOFOLLOW)` và kiểm tra lại `fstatat(..., AT_SYMLINK_NOFOLLOW)` ngay trước khi chuyển; hoặc ít nhất re-`lstat` + so dev/ino ở **mọi** luồng UI (hiện chỉ `DiagnosticViews.swift:173` làm).

### 1.8 🟡 Nạp `safety_db.json` / `skins.json` / strings từ thư mục hiện hành
- **File:** `Verdict.swift:147-151`, `SkinCatalog.swift:13-17`, `L10n.swift:146-150`, `AgentAPI.swift:436-447`
- **Vấn đề:** Nếu `Bundle.main` không thấy resource (CLI chạy ngoài .app, symlink, dev build), sẽ đọc `Sources/DiskCleaner/Resources/safety_db.json` **tương đối CWD**. MCP server thường được khởi chạy với CWD = project của người dùng → repo độc hại có thể đánh dấu `~/Documents` là `safe/exact` để agent được phép xoá.
- **Sửa:**
  - [x] Bọc fallback dev bằng `#if DEBUG` (`devHooksEnabled`; cả bảng en của AgentAPI).
  - [ ] Nhúng SHA-256 của `safety_db.json` vào binary lúc build và kiểm tra khi load; sai → từ chối mọi thao tác xoá của agent.

### 1.9 🟢 Tìm `docker` qua shell + PATH; đọc pipe sau khi chờ
- **File:** `ScanJobs.swift:750-762` (`runCmd`), `795-805` (`dockerCLI`)
- **Vấn đề:**
  - `/bin/sh -c "command -v docker"` dùng PATH của agent host → binary `docker` giả trên PATH sẽ được chạy; `DOCKER_HOST` từ xa khiến app "không kết nối mạng" lại gọi mạng.
  - `runCmd` chỉ đọc stdout **sau** khi tiến trình thoát → output > 64 KB làm đầy pipe, tiến trình treo tới timeout 20 s rồi bị kill, trả `nil` (mất dữ liệu Docker). Thêm `Thread.sleep` busy-wait.
- **Sửa:**
  - [ ] Chỉ dùng danh sách đường dẫn tuyệt đối cố định; đặt `environment` sạch cho Process (bỏ `DOCKER_HOST`, PATH tối thiểu).
  - [ ] Đọc pipe bất đồng bộ (`readabilityHandler`) hoặc đọc trước `waitUntilExit`, dùng `terminationHandler` thay sleep.

### 1.10 🟢 `diag_probe` (MCP) nhận đường dẫn tuỳ ý
- **File:** `MCPServer.swift:351-382`
- **Vấn đề:** Không kiểm tra phạm vi; chỉ đọc file có magic `MDMP` và trả tên chủ sở hữu đã che. Rủi ro thấp nhưng nên giới hạn.
- **Sửa:** [ ] Chỉ cho phép trong các root crash-dump đã liệt kê ở `diag_coverage`.

### 1.11 🟢 MCP server không giới hạn kích thước dòng
- **File:** `MCPServer.swift:20-38`
- **Vấn đề:** `buffer` tăng vô hạn nếu client gửi dữ liệu không có `\n` → tốn RAM.
- **Sửa:** [ ] Giới hạn ~4 MB/dòng, vượt quá thì trả lỗi `-32700` và xoá buffer.

---

## 2. Tầng ứng dụng / UI (Sources/DiskCleaner)

> Tất cả luồng xoá UI đều qua `trashItem` và có `confirmTrash`; không có `removeItem`, không có `Process`/shell ở tầng UI; trang Feedback không gửi mạng (chỉ clipboard / `mailto:`). Bản dịch đủ key ở 10 ngôn ngữ (gồm `vi`).

### 2.1 🟠 Nút "在访达中清空" xoá vĩnh viễn TOÀN BỘ Thùng rác, không xác nhận
- **File:** `Views/DiagnosticViews.swift:717-720`
- **Vấn đề:** Sau khi trim crash dump, nút này chạy `Task.detached { _ = try? await emptyTrashViaFinder() }`: xoá vĩnh viễn cả những file không liên quan, nuốt lỗi, không gọi `store.clearHistory()` (trang Trash vẫn hiện undo cho file không còn), nằm ngay cạnh nút "撤销整批". Điều kiện là `Channel.isAppStore` thay vì `HomeAccess.runsSandboxed`.
- **Sửa:** [x] (chọn cách mở Finder) Dùng lại alert xác nhận + xử lý lỗi của `TrashView`, hoặc chỉ mở Finder.

### 2.2 🟠 Folder Drill "Chọn tất cả" chọn cả dotfile / Keychains / iCloud
- **File:** `Views/FolderDrillView.swift:255, 443`
- **Vấn đề:** Chỉ dùng `isDeletable` và liệt kê file ẩn → trong `~` một click + một xác nhận chung là chuyển `~/.ssh`, `~/.gnupg`, `~/.zshrc` vào Thùng rác; trong `~/Library` là `Keychains`, `Mail`, `Mobile Documents` (iCloud, đồng bộ xoá sang mọi thiết bị). Hàng được bảo vệ cũng bị chọn rồi báo lỗi.
- **Đã sửa:** hàng dùng `isReclaimableWhole`; select-all dùng `isBulkSelectable` (bỏ dotfile + con trực tiếp của `~/Library`); alert liệt kê tối đa 10 tên mục và đếm theo `selectedEntries`.
- **Sửa:**
  - [x] Dùng `isReclaimableWhole`; loại dotfile và con của `~/Library` khỏi select-all.
  - [x] Hộp xác nhận liệt kê tên các mục; cảnh báo riêng khi có mục ẩn hoặc nhạy cảm (liên quan 1.4).

### 2.3 🟠 Xoá file trùng không kiểm tra lại bản được giữ
- **Tiến độ:** đường thực thi mới gắn `keptCopy` cho từng bản dư, kiểm tra trong `preflight`.
- **File:** `Views/DupOrphansViews.swift:250-258`
- **Vấn đề:** Dựa vào hash lúc quét. Nếu bản giữ lại (`files[0]`) đã bị di chuyển, xoá hay sửa thì bản duy nhất của nội dung bị chuyển vào Thùng rác.
- **Sửa:** [x] (`duplicateStillMatches`) Ngay trước khi xoá: kiểm tra bản giữ còn tồn tại, cùng size + mtime (tốt nhất hash lại); không khớp thì bỏ qua cả nhóm.

### 2.4 🟠 Quyền sandbox chấp nhận thư mục bất kỳ làm "home"
- **File:** `HomeGrant.swift:36-37`, `DiskCleanerCore/HomeAccess.swift`
- **Vấn đề:** Thư mục được chọn trở thành `homeDir()` → định nghĩa lại `isDeletable`/`protectedPaths`. Chọn `/Users` thì thư mục của user khác cũng xoá được; chọn ổ ngoài thì mọi quy tắc `~/Library/...` lệch.
- **Sửa:** [x] `HomeAccess.isRealHome` trong `grant` và `restore`.

### 2.5 🟡 Hook debug trong SnapshotMode xoá file thật ở bản release
- **File:** `DiskCleanerApp.swift:13`, `SnapshotMode.swift:580-864`
- **Vấn đề:** `DISKWISE_SHOTS` + `DISKWISE_RING=arm` / `DISKWISE_CLEAN=run` chuyển file thật vào Thùng rác mà không cần xác nhận. Không bắt buộc có `DISKWISE_HOME_SHIM` (chỉ ghi trong comment), nên sẽ chạy trên home thật. Toàn project không có `#if DEBUG` nào.
- **Sửa:** [x] Bọc toàn bộ SnapshotMode/PerfProbe trong `#if DEBUG` (cùng hướng với 1.3).

### 2.6 🟡 `NSAppleScript` chạy ngoài main thread
- **File:** `Views/TrashView.swift:240-243`, `DiagnosticViews.swift:719` → `Scanner.swift:735`
- **Vấn đề:** `NSAppleScript` không thread-safe, nên đôi khi gây crash hoặc treo. Chuỗi "访达会让你确认" (`TrashView.swift:65,136,216`) có thể sai, vì lệnh `empty the trash` chạy bằng script có thể không hiện cảnh báo.
- **Sửa:** [ ] Chạy trên `@MainActor` hoặc dùng `NSUserAppleScriptTask`; kiểm tra lại trên máy thật và sửa câu chữ.

### 2.7 🟡 Trim crash dump làm đơ main thread
- **File:** `Views/DiagnosticViews.swift:163-185`
- **Vấn đề:** `runTrim` lặp đồng bộ trên `@MainActor` qua tới khoảng 160 nghìn file, nên UI đơ, tiến trình không hiển thị và không huỷ được.
- **Sửa:** [ ] Chạy trong task nền, báo tiến độ theo lô, hỗ trợ `Task.isCancelled`.

### 2.8 🟡 "Hoàn tác lần trước" chỉ khôi phục 1 mục; lịch sử mất khi thoát app
- **Tiến độ:** API lô bền vững (`store.batches`, `undo(batchID:)`, kết quả từng mục) đã có; chờ UI chuyển từ `undoLast` sang lô.
- **File:** `DiskCleanerApp.swift:311-343`, `Views/UninstallView.swift:516-537`
- **Vấn đề:** Gỡ app ghi 1 + N bản ghi, nhưng undo chỉ trả lại 1 thư mục dữ liệu và để app nằm lại trong Thùng rác. Lịch sử chỉ lưu trong RAM, trái với câu "随时可撤销" (hoàn tác bất cứ lúc nào). Undo cũng không kiểm tra `inTrash` có còn là đúng file đó không (dev/ino).
- **Sửa:**
  - [ ] Gom bản ghi theo batch và undo theo batch.
  - [ ] Lưu lịch sử ra đĩa (0600).
  - [ ] Lưu dev/ino lúc xoá và so lại khi hoàn tác.

### 2.9 🟡 Gỡ app khi app đó đang chạy
- **Tiến độ:** C4 — `runState`, `requestQuit` (thoát bình thường, ≤10 s), `uninstall(using:)` từ chối khi app đang chạy; bundle là mục critical. Chờ UI hộp thoại.
- **File:** `Views/UninstallView.swift:509-541`
- **Sửa:** [ ] Kiểm tra `NSRunningApplication` theo bundle ID; từ chối, hoặc đề nghị thoát app trước.

### 2.10 🟡 Sai kế toán dung lượng ở trang Caches
- **File:** `Views/CachesView.swift:449-470`
- **Vấn đề:**
  - Mục có nhiều đường dẫn ghi size bằng `fileSize(p)` (chỉ lấy `st_blocks` của chính thư mục) nên báo thiếu rất nhiều.
  - Chọn cả cha lẫn con thì bị đếm 2 lần hoặc báo lỗi "not found" giả.
  - Sau khi xoá một phần, `size = nil` và không đo lại, nên hàng kẹt ở "统计中…" (đang thống kê) và không chọn lại được.
- **Đã sửa (C3, `feat/claude-p0`):** `CachesModel.trashSelected()` + `cacheTrashPlan`/`cacheItemsTouched`/`cacheRowState` trong Core; chờ Codex nối `CachesView.clean()` vào API.
- **Sửa:**
  - [x] Dùng `it.pathSizes[p.path]`.
  - [x] Áp `dropNested` trước khi xoá.
  - [x] Đo lại các path còn lại.

### 2.11 🟡 Kết quả quét cũ / TOCTOU giữa các trang
- **Tiến độ:** `scanState`/`scannedAt`/`isStale(lastTrashAt:)` trên mọi model quét + `preflight` khi thực thi. Chờ UI hiện "Quét lại".
- **File:** `Views/BigOldViews.swift:304-321, 549-562`, `FolderDrillView.swift:91-96, 469-485`, `OverviewView.swift:1772-1790`, `DiskCleanerApp.swift:92-114`
- **Vấn đề:**
  - Xoá theo URL/size lúc quét mà không kiểm tra lại.
  - FolderDrill cache từng cấp thư mục tới lần quét toàn cục sau.
  - Smart Scan dùng một `CachesModel` riêng, nên trang Caches/Overview không được cập nhật.
- **Sửa:**
  - [ ] Kiểm tra dev/ino/mtime lúc xoá (như `runTrim` đang làm).
  - [ ] Invalidate model sau mỗi lần xoá; dùng chung một model.

### 2.12 🟡 Ép tiếng Việt cho mọi user mới và user nâng cấp, bỏ qua onboarding
- **File:** `DiskCleanerApp.swift:17-23`
- **Vấn đề:** Khi chưa có `diskcleaner.simpleUI.v1`, app gọi `setChoice(.vi)` (ghi đè ngôn ngữ user đã chọn), đồng thời đánh dấu đã xem first-run và guide, nên user mới bỏ lỡ màn hình cấp quyền/giải thích.
- **Sửa:** [ ] Chỉ mặc định `vi` khi lựa chọn đang là `.system` và locale là `vi`; không bỏ qua onboarding.

### 2.13 🟢 Lỗi nhỏ
- [ ] `DiagnosticViews.swift:522`: `hub.removeReports` xoá cả những hàng xoá thất bại khỏi danh sách. Chỉ nên bỏ các hàng đã xoá thành công.
- [x] `FolderDrillView.swift:215`: số lượng trong alert đếm `model.selected` (có thể chứa path của cấp trước), trong khi thao tác chạy trên `selectedEntries`. Nên dùng `selectedEntries.count`.
- [ ] `UninstallView.swift:47`: tìm kiếm so `bundleID` chưa lowercase với query đã lowercase.
- [ ] `Product.swift:22-30`: email/QQ góp ý là của tác giả gốc (xem 3.7).

---

## 3. Build, phát hành & chuỗi cung ứng

### 3.1 🔴 Bundle ID vẫn là của tác giả gốc
- **File:** `build_app/build.sh:50`, `Sources/DiskCleaner/Product.swift:14` → bundle ID cũ của tác giả gốc
- **Hậu quả:** Chia sẻ UserDefaults/TCC/LaunchServices với DiskWise thật; `brew zap` của DiskWise xoá prefs CleanPilot; không thể ký Developer ID/App Store với bundle ID của người khác; dễ bị nhầm/mạo danh.
- **Đã sửa:** `build.sh` + `Product.swift` (đoạn chuyển prefs từ bundle cũ đã bỏ sau khi chạy xong). `build.sh` chỉ tự chọn chứng chỉ của tài khoản cá nhân huynhtrungthoai và kiểm `TeamIdentifier` sau khi ký (chứng chỉ khác → build fail).
- **Sửa:** [x] Đổi sang ID của mình (`com.huynhtrungthoai.cleanpilot`), migrate prefs một lần, cập nhật `Product.swift`, `build.sh`, Cask `zap`.

### 3.2 🟠 Homebrew Cask cài app của người khác
- **File:** `Casks/diskwise.rb:2-27`, `docs/homebrew.md`, `Views/AgentPageView.swift:117` (+ chuỗi dịch ở mọi `*.lproj`)
- **Vấn đề:** URL tải `repo tác giả gốc/...DiskWise-*.dmg`, `app "DiskWise.app"`; app hướng dẫn lệnh brew trỏ về tap của tác giả gốc. Người dùng CleanPilot sẽ cài binary bên thứ ba.
- **Đã sửa:** `Casks/diskwise.rb` → `Casks/cleanpilot.rb` (sha256 placeholder tới khi có release Developer ID), `docs/homebrew.md`, lệnh brew trong app + 10 lproj.
- **Sửa:** [x] Tạo `Casks/cleanpilot.rb` (URL release của mình + `sha256`, `app "CleanPilot.app"`, `binary` cho CLI, `zap` theo bundle ID mới); sửa docs & chuỗi trong app.

### 3.3 🟠 Release tự rơi về ký ad-hoc, không hardened runtime
- **File:** `build_app/build.sh:300-303, 374, 386-394, 482-489, 572`
- **Vấn đề:** Không có identity "Developer ID Application" → `codesign --sign -` không `--options runtime`, không timestamp; DMG chỉ ký khi `NOTARIZE=1`; README dạy người dùng "Open Anyway" (tập cho người dùng bỏ qua Gatekeeper — rủi ro virus nếu có bản giả mạo).
- **Sửa:**
  - [x] Bản release (`RELEASE=1`): thiếu identity → **fail**; ad-hoc chỉ khi `SIGN_IDENTITY=none` rõ ràng.
  - [x] Luôn `--options runtime` (timestamp với Developer ID); luôn ký + notarize + staple DMG.
  - [ ] Công bố SHA-256 của DMG trong release notes.

### 3.4 🟡 Workflow `release.yml` vẫn có thể ghi đè file release
- **File:** `.github/workflows/release.yml:28-29, 136-150`
- **Vấn đề:** `workflow_dispatch` trên tag chạy `gh release upload --clobber` với bản ad-hoc (khi không có secrets), đè DMG đã ký.
- **Sửa:** [ ] Bỏ bước upload hoặc yêu cầu `signed == 'true'`; bỏ `--clobber`; `permissions: contents: read`.

### 3.5 🟡 GitHub Actions ghim theo tag, không theo SHA
- **File:** `release.yml:44,129`, `website.yml:19,21,25,39,50` (`pnpm/action-setup@v4` là bên thứ ba, chạy cùng secrets ký)
- **Sửa:** [ ] Ghim full commit SHA; bật Dependabot cho `github-actions`.

### 3.6 🟡 `website.yml` cấp `pages: write` + `id-token: write` cho cả job build
- **File:** `.github/workflows/website.yml:6-9`
- **Sửa:** [ ] Job `build` chỉ `contents: read`; quyền Pages/OIDC chỉ ở job `deploy`; `pnpm install --frozen-lockfile --ignore-scripts`.

### 3.7 🟡 Kênh báo lỗi bảo mật / phản hồi trỏ về tác giả gốc
- **File:** `SECURITY.md:9`, `.github/SECURITY.md:24`, `Product.swift:23-24` (email, nhóm chat của tác giả gốc), ảnh QR trong `docs/contact/` (đóng gói bởi `build.sh:81,199`)
- **Hậu quả:** Báo cáo lỗ hổng và phản hồi người dùng CleanPilot bị gửi cho bên thứ ba.
- **Sửa:** [x] Thay bằng GitHub Security Advisories của repo mình; gỡ email/QQ khỏi app, bỏ ảnh QR khỏi bundle.

### 3.8 🟡 Website có Google Analytics trong khi tuyên bố "không telemetry"
- **File:** `website/index.html:67-73` (`G-4Y56RFLD4W`), `docs/PRIVACY.md:3,7,40`
- **Sửa:** [x] Gỡ GA khỏi `website/index.html`; [x] rebrand PRIVACY.md — (hoặc dùng property riêng + consent); rebrand PRIVACY.md. (App không có network call — đã xác nhận không có `URLSession`/`NWConnection`.)

### 3.9 🟢 Mật khẩu notarize lộ trên command line
- **File:** `build_app/build.sh:577-578`
- **Sửa:** [ ] Dùng `notarytool store-credentials` + `--keychain-profile`.

### 3.10 🟢 Mật khẩu keychain CI dễ đoán (`$RUNNER_TEMP`)
- **File:** `release.yml:96-98,105`
- **Sửa:** [ ] `openssl rand -hex 32`.

### 3.11 🟢 Script dev ghi vào đường dẫn cố định trong `/tmp`
- **File:** `build_app/l10n_batch1.py`, `build_app/l10n_batch1b.py:5` (`/tmp/dw-v19/...`)
- **Sửa:** [ ] Xoá script hoặc dùng đường dẫn tương đối repo / `mktemp -d`.

### 3.12 🟢 Tàn dư tên DiskWise (dễ xung đột/nhầm lẫn)
- `Package.swift:5` (`name: "DiskWise"`), target `DiskWiseCLI`, binary `diskwise` (`build.sh:187`), tên MCP server `diskwise` (`AgentClientRecipes.swift:74-96`), state dir `Application Support/DiskWise` (`AgentAPI.swift:403`), release title (`release.yml:131,161,170`), website gốc (đã xoá), biến môi trường `DISKWISE_*`.
- **Sửa:** [ ] Đổi tên đồng bộ + migrate state dir cũ một lần.

---

## 4. Chất lượng mã & kiểm thử

- [ ] 🟡 Hàng loạt warning Swift 6 concurrency (`main actor-isolated let 'fm'`, `wait() unavailable from async`) — chủ yếu trong `SelfTest/main.swift`; dọn trước khi bật Swift 6 language mode.
- [ ] 🟡 Bổ sung SelfTest cho các ca: case-insensitive path, symlink cha, `HOME_SHIM` trong release, `untrash` với record bị sửa, plan bị sửa `human`, MCP dòng quá dài.
- [ ] 🟢 Thêm CI chạy `swift build` + `swift run SelfTest` trên mỗi PR (hiện chỉ có release/website workflow).
- [ ] 🟢 Fuzz `agentPipeline` với đường dẫn có `..`, `//`, Unicode NFD/NFC (APFS chuẩn hoá Unicode — `é` dạng NFC vs NFD cũng là một kiểu bypass so khớp chuỗi giống 1.1).

---

## 5. Đã kiểm tra — ổn

- Mọi luồng xoá đi qua `trashItem` (Thùng rác, có undo); không có `removeItem` lên dữ liệu người dùng (chỉ xoá plan file nội bộ).
- Agent API: bắt buộc plan → trash, TTL 10 phút, giới hạn 200 mục / 200 GB, kiểm tra lại inode, từ chối symlink ở thành phần cuối, tier `risky` không ai xoá được.
- `planId` được lọc ký tự `/`, `\`, `.` đầu → không path traversal.
- Entitlements bản trực tiếp rỗng; bản App Store có sandbox, không có network.
- Không có secret/token hard-code; `.gitignore` chặn `*.p12`, `*.key`, ...; website có lockfile + `--frozen-lockfile`.
- Không có `pull_request_target` hay script injection qua `github.event.*`.
