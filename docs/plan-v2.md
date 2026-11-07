# CleanPilot V2 — phân tích ảnh và kế hoạch UI / tính năng

Ngày: 07/11/2026. Chủ sản phẩm: Thoai Huynh. Codex: phân tích, theme, navigation, SwiftUI. Claude: model, scanner, quyền truy cập, thực thi và lịch sử.

## 1. Mục tiêu và nguồn sự thật

Tái thiết kế CleanPilot theo trải nghiệm thể hiện trong 9 ảnh tại `docs/anh-clean-my-mac`: thân thiện, ít chi tiết kỹ thuật ở bước đầu, màu sắc có chủ đích, xem được dữ liệu trước khi quyết định. Thứ tự: tài liệu này → Codex dựng UI bằng API hiện có → Claude bổ sung lõi theo contract → Codex nối và nghiệm thu.

Đây là phân tích ảnh do chủ sản phẩm cung cấp, không phải kiểm thử CleanMyMac và không khẳng định tính năng của phiên bản mới nhất. Không suy ra engine, quyền, độ an toàn, tốc độ hoặc chính sách tự chọn từ ảnh. Những tính năng chỉ có tên trên sidebar được đánh dấu riêng. Số GB trong ảnh là dữ liệu của máy tham khảo, tuyệt đối không đưa vào UI CleanPilot làm kết quả giả.

V2 bổ sung kế hoạch cũ `enhance-feat.md`; §11 của kế hoạch cũ vẫn là contract có hiệu lực cho C0–C9. Các contract V2 dưới đây là yêu cầu đề xuất cho Claude, chưa phải API đã tồn tại. Không thay đổi mức an toàn, phạm vi xóa hay tự chọn trong lần dựng UI.

## 2. Bản đồ bằng chứng của cả 9 ảnh

Tên ảnh được rút gọn theo tiền tố duy nhất; tất cả nằm trong `anh-clean-my-mac/` cạnh tài liệu.

| ID / tiền tố | Màn hình thực sự thấy | Bố cục / thông tin quan sát được | Bài học áp dụng |
| --- | --- | --- | --- |
| A01 `1793970019233` | System Junk sau quét | Sidebar có tổng 4,72 GB; minh họa tròn hồng bên trái; trạng thái, 3,14 GB smart-selected và danh sách nhóm bên phải; Review Details; Clean ở đáy | Tách tổng tìm thấy và phần được đề xuất; xem chi tiết trước thực thi |
| A02 `1793970019234` | Chi tiết System Junk | Sidebar → danh sách loại rác → mô tả và file; search; sort; checkbox nhóm có trạng thái một phần; tổng chọn ở đáy | Ba vùng thông tin, chọn nhóm và chọn con đồng bộ qua model |
| A03 `1793970019235` | Smart Scan đang chạy | Ba cột Cleanup / Protection / Speed; từng cột có mô tả và trạng thái riêng; Cleanup đã có số trong khi hai nhóm kia còn chạy/chờ; nút Stop có vòng tiến độ | Trạng thái theo module, không dùng một dấu hoàn tất cho cả máy |
| A04 `1793970019236` | Cleanup Details dạng overlay | Lớp nền tối, Back to Summary; nhóm System Junk / Trash Bins bên trái; nhóm con bên phải | Luồng tổng quan → phân loại → chi tiết; quay lại giữ selection |
| A05 `1793970019237` | Tổng quan Trash Bins | Gradient xanh ngọc → xanh tím; biểu tượng thùng rác lớn; số 1,9 MB, tên ổ; Review Details / Empty | Trash có ngữ nghĩa khác chuyển file vào Trash; xác nhận xóa vĩnh viễn riêng |
| A06 `1793970019238` | Large & Old Files | Gradient san hô → tím; cột lọc All / Selected / Kind / Size / Access Date; danh sách tên, icon, size; Remove Immediately ở đáy | Bộ lọc tách khỏi danh sách; giữ CTA tiếp cận được; không sao chép chế độ xóa ngay |
| A07 `1793970019239` | Uninstaller danh sách | Gradient xanh lam → tím; bộ lọc All / Unused / Leftovers / Suspicious / Selected, Store, Vendor; danh sách app có size và disclosure | App và dữ liệu liên quan là cùng một luồng; metadata bộ lọc phải từ lõi |
| A08 `1793970019240` | Uninstaller mở rộng Zalo | Phân cấp Binaries / Preferences / Supporting Files / Login Items; checkbox từng phần và dung lượng; Uninstall ở đáy | Cho biết chính xác app bundle và dữ liệu riêng nào sẽ bị chuyển; loại dữ liệu dùng chung |
| A09 `1793970019241` | Chi tiết Trash theo ổ | Cột ổ đĩa bên trái, file bên phải; search, sort, chọn tất cả; có biểu tượng cloud ở một số dòng | Cần model riêng cho nhiều ổ và metadata cloud; không suy đoán ý nghĩa biểu tượng từ ảnh |

## 3. Danh mục tính năng và khoảng cách với CleanPilot

| Tính năng trong ảnh | Mức bằng chứng | CleanPilot hiện tại | V2 / việc Claude cần làm |
| --- | --- | --- | --- |
| Smart Scan | Có ảnh đang quét | `ScanStore.smart` là CachesModel quét cache ứng dụng + dev; C8/C9 đã có | UI hiện tại nói đúng phạm vi cache. V2-SCAN mới điều phối nhiều module sau khi owner chốt phạm vi |
| System Junk | Có ảnh tổng quan và chi tiết | Cache app/dev, phân loại tác động, đo size, kế hoạch và xác nhận | Dựng màn hình nhóm + danh sách; metadata chuẩn hóa user/system cache, logs chỉ khi lõi cung cấp |
| Trash Bins | Có ảnh tổng quan và file | TrashModel có tổng dung lượng và mở Finder / empty qua Finder; AppStore có batch history và undo | V2-TRASH cung cấp file theo ổ. Hiện UI chỉ hiện tổng thực đo và lịch sử, không giả danh sách file |
| Large & Old Files | Có danh sách và bộ lọc | BigFilesModel / OldFilesModel riêng, ngày sửa đổi | Liên kết hai công cụ; search/filter nội bộ dữ liệu đã trả; giữ nguyên ngưỡng quét. Không đổi “ngày sửa” thành “lần dùng” |
| Uninstaller | Có danh sách và cây app | UninstallModel có app, query, App Store, trạng thái chạy, data items, shared paths, quit/uninstall | Bộ lọc All / App Store / Running dựa dữ liệu thật; chọn app để xem dữ liệu. Unused / vendor / suspicious cần V2-APPS |
| Space Lens | Chỉ có tên trên sidebar | Overview, FolderDrill, treemap C7 đã có | Giữ biểu đồ + danh sách + breadcrumb; không khẳng định ảnh cho thấy cách vẽ Space Lens |
| Mail Attachments | Chỉ có tên trên sidebar | Chưa có module Mail | Cần phạm vi Mail client, quyền, tác động đồng bộ, phục hồi; chưa bật đường dẫn nhạy cảm |
| Malware Removal / Privacy | Chỉ có tên trên sidebar | Chưa có engine bảo mật | Cần nguồn nhận diện, định nghĩa kết quả và xử lý false positive; không dựng huy hiệu “Mac an toàn” |
| Optimization / Maintenance | Chỉ có tên trên sidebar | Có chẩn đoán, menu bar; chưa có tác vụ tối ưu tương ứng | Chốt từng tác vụ, quyền, khả năng hoàn tác; không hứa tăng tốc từ số cache |
| Updater / Extensions | Chỉ có tên trên sidebar | Chưa có nguồn cập nhật / extension inventory | Nguồn chính thức, xác thực chữ ký, quyền; quy tắc update cần owner quyết định |
| Shredder | Chỉ có tên trên sidebar | Không thuộc luồng chuyển Trash | Chờ quyết định sản phẩm; không đưa xóa ngay vào UI hiện tại |
| Assistant | Chỉ thấy nút | Có AI Agent tùy kênh phân phối | Giữ AI Agent hiện có; không suy ra năng lực Assistant của CleanMyMac |
| Dọn dẹp cho lập trình viên | Yêu cầu riêng của owner, bổ sung 07/11/2026 | Đã có NMModel, dev cache trong CachesModel và Docker Usage chỉ xem | Tạo trung tâm Dev Cleanup thống nhất, xem theo dự án/công cụ; đặc tả §6.7 và contract V2-DEV |
| File trùng / dev tools / hoạt động | Không có màn hình riêng trong bộ ảnh | CleanPilot có sẵn | Giữ khả năng truy cập trong điều hướng V2, dùng cùng hệ màu và thành phần |

## 4. Kiến trúc thông tin V2

```text
CleanPilot
  Quét thông minh
  Dọn dẹp
    Cache ứng dụng
    Thùng rác & hoạt động
  Ứng dụng
    Gỡ ứng dụng
    Dữ liệu còn sót
  File & dung lượng
    Tổng quan / bản đồ
    File lớn
    File lâu không sửa
    File trùng
  Công cụ nâng cao [thu gọn, tự mở khi đang ở trang con]
    Dọn dẹp cho lập trình viên [đích V2: một trung tâm chung]
      node_modules theo dự án / Cache công cụ / Dữ liệu build
      Docker Usage [hiện chỉ xem]
    Crash dumps / Chẩn đoán / Quan sát
    AI Agent (theo channel)
  Cài đặt / Giao diện / Phản hồi [chân sidebar]
```

Chỉ thêm nhóm Bảo mật / Hiệu năng / Mail / Updater / Extensions vào navigation khi có dữ liệu và hành động thật. Roadmap lưu đủ tính năng tham khảo. Thu gọn công cụ nâng cao là state giao diện, không làm mất model hay phiên quét. Giữ AppPanel hiện tại và API điều hướng, phím quay lại, deep link và snapshot hook.

## 5. Hệ thị giác V2

Các màu là lựa chọn thiết kế ước lượng từ ảnh chụp, không phải token trích xuất chính thức của CleanMyMac. Không dùng logo hay minh họa của đối thủ trong app.

| Token / thành phần | Quy cách |
| --- | --- |
| Họ nền | Smart tím lavender; cache hồng rose; Trash teal; app sky blue; file coral; dev tím slate |
| Nền tối | Đáy indigo `#30365D`; vùng đầu theo module có độ sáng vừa phải để chữ trắng đọc được |
| Nền sáng | Tint pastel ở đầu, giấy lavender `#F3F1FA` ở đáy; chữ đậm `#24243B` |
| Chữ tối | Chính `#FFFFFF`, phụ `#E4E7F5`; panel danh sách tối ổn định để đọc path |
| CTA | Cyan sáng `#83E0F5` với chữ indigo; light dùng xanh đậm `#165A83` với chữ trắng; nút capsule, không cắt khỏi cửa sổ như ảnh |
| Sidebar | 232–248 pt; biểu tượng 20–24 pt; dòng 36–40 pt; vùng chọn dạng viên bo góc, tương phản rõ |
| Workspace | Padding 24 pt; nhóm lọc 170–200 pt; danh sách co giãn; app picker 240–280 pt |
| Chữ | SF hệ thống; title 26–32; hero 30–36; số liệu 32–42; body 13–14; phụ 11–12; dung lượng monospacedDigit |
| Khối | Bo góc 14–20 pt; viền nhẹ; tránh nhiều lớp card lồng nhau và bóng nặng |
| Minh họa | SF Symbols trong khối tròn/ổ đĩa do CleanPilot dựng; chỉ trang mở đầu cần hình lớn |
| Motion | 180–220ms khi chuyển trạng thái; Reduce Motion tắt hiệu ứng; không dùng vòng quay trang trí để giả tiến độ |
| Accessibility | Nhãn VoiceOver, trạng thái chọn, bàn phím, thông tin không chỉ qua màu; Reduce Transparency dùng nền đặc |
| Kích thước | Tối thiểu 1000×560; thường 1080×700; nội dung dài cuộn, footer không cuộn mất |

Màu theo module chỉ áp dụng cho hai giao diện mặc định Morning Fog / Graphite. Các skin khác vẫn dùng bảng màu riêng. Light/dark phải lấy theo appearance đã chọn; thay đổi màu không tái tạo ScanStore hay tự chạy lại scan.

## 6. Đặc tả màn hình và trạng thái

### 6.1 Quét thông minh

Đầu trang ngắn + mô tả phạm vi. Ba vùng lớn trình bày cache ứng dụng, cache lập trình và khám phá dung lượng, đều là khả năng đang có. Có số thực khi model hoàn tất; chưa đo dùng dấu gạch / lời mời quét, không hiển thị 0 như kết quả. Tổng quan dung lượng là liên kết, không báo được Smart Scan quét. Minh họa xuất hiện trong từng vùng như ba cột của A03. Footer chứa Scan / Stop / Review / Clean tùy trạng thái; Clean mở xác nhận C8.

- Idle: lời mời quét cache, không nói máy có vấn đề.
- Scanning: đếm vị trí đã đo / tổng và đường dẫn; có Stop; phần không chạy không hiển thị hoạt ảnh.
- Stopped: nói quét đã dừng; không biến kết quả từng phần thành kết quả đầy đủ.
- Complete: tách số được đề xuất, số toàn danh sách và phần giữ lại do app chạy.
- Error / permission / partial: lấy ScanStatusView từ model, không thay bằng “sạch”.
- Review: đi vào danh sách cache cùng model; quay lại giữ kết quả.
- Confirm / working / result / undo: dùng contract C1/C2/C8/C9, giữ kế hoạch cố định tại xác nhận.

### 6.2 Cache

Đầu trang + phạm vi + Scan/Stop. Workspace gồm cột nhóm bên trái và danh sách bên phải; ở cửa sổ hẹp dùng menu lọc thay cột. Nhóm “tất cả” và các groupKey hiện có có số mục/dung lượng thực đo; tìm kiếm chỉ lọc cách hiển thị. Checkbox vẫn binding vào model gốc; lọc không đổi selection, không tự chọn thêm. Mỗi dòng giữ What it is / What breaks / How to recover và path. Footer thống kê toàn bộ selection trong model (kể cả ngoài bộ lọc), và mở xác nhận. Select all dùng model.selectAll, không tự chọn theo size trong View.

### 6.3 Ứng dụng

App picker bên trái; icon, app name, bundle ID, trạng thái chạy và data items bên phải. Search trên picker giữ API model.query. Bộ lọc giao diện dùng All / App Store / Running. Leftovers dẫn trang dữ liệu còn sót hiện có. Không tạo bộ lọc Unused/Suspicious khi chưa có bằng chứng từ model. Confirmation phải nêu bundle và dữ liệu, dùng luồng quit C4; không tự kill app.

### 6.4 File và dung lượng

Đổi họ màu coral, dùng header / summary / list / footer chung. File lớn và lâu không sửa có lối chuyển qua lại; giữ mô hình riêng và trạng thái từng trang. Trùng file tiếp tục làm rõ bản giữ và kiểm chứng trước thao tác. Tổng quan giữ ring/treemap và API C7; không thay dữ liệu bằng bong bóng trang trí. Bộ lọc theo kind/date/access chỉ bổ sung khi semantics có nguồn rõ ràng.

### 6.5 Thùng rác & hoạt động

Mở đầu có biểu tượng teal và tổng thực đo; các batch và khả năng undo vẫn là nội dung chính hiện tại. Không dựng file ở Trash từ batch history vì chúng không chứng minh file còn trong Trash. Empty mở xác nhận không thể hoàn tác; disable khi đang chạy thao tác khác. Chuyển vào Trash không đồng nghĩa dung lượng ổ được giải phóng ngay. Danh sách file nhiều ổ là công việc V2-TRASH sau này.

### 6.6 Các trang còn lại

Dùng hệ theme chung, header rõ, số liệu thật, nội dung cuộn và footer nhất quán. Không bỏ công cụ dev/chẩn đoán; gom dưới Advanced. Cài đặt và đổi skin vẫn hoạt động, không ép lưu đè theme cá nhân.

### 6.7 Dọn dẹp cho lập trình viên — Dev Cleanup

**Yêu cầu owner bổ sung 07/11/2026:** có tính năng riêng giúp dev tìm và dọn `node_modules`, cache và các dữ liệu phát sinh khi phát triển phần mềm. Đây là tính năng của CleanPilot, không suy ra từ bộ ảnh CleanMyMac. Trong V2, gom các công cụ dev hiện có thành một nơi dễ hiểu; các khả năng mới bên dưới là kế hoạch, chưa phải mã đã triển khai.

#### Phạm vi và nhóm dữ liệu

| Nhóm | Hạng mục | Hiện trạng / hướng triển khai |
| --- | --- | --- |
| JavaScript / Node.js | `node_modules` theo dự án; cache npm, pnpm, Yarn, Bun và nvm | Đã có NMModel và các entry cache tương ứng trong safety_db; cần trình bày chung với dự án, package manager và cách cài lại nếu xác định được |
| Build của dự án | Ví dụ `.next`, `.nuxt`, `.turbo`, `dist`, `build`, `coverage`, `.gradle`, `.build`, `target` | Đề xuất detector theo hệ sinh thái và cấu trúc dự án; tên thư mục đơn lẻ không đủ chứng minh là dữ liệu có thể tái tạo; không đưa mọi thư mục cùng tên vào danh sách dọn |
| Apple / iOS | Xcode DerivedData, SwiftPM, CocoaPods; Archives, DeviceSupport và Simulator trình bày riêng | safety_db đã có các entry; phân biệt cache có thể tạo lại với archive, simulator chứa dữ liệu và thành phần cài đặt; không gộp tất cả thành cache |
| Python | pip, uv, conda package cache; môi trường `.venv`/venv theo dự án là nhánh mở rộng | Cache đã có entry; venv cần detector và cách tái tạo từ cấu hình đã xác minh, không xem là cache thông thường |
| JVM / Android | Gradle caches/wrapper, Maven repository, IDE caches | Đã có entry; SDK/AVD trình bày thành dữ liệu cài đặt hoặc môi trường, giải thích tải lại và nguy cơ mất dữ liệu riêng |
| Go / Rust / Homebrew | Go module/build cache, Cargo registry, Homebrew download cache | Đã có entry; kiểm tra phạm vi thực tế và phân biệt cache dùng chung với output riêng của từng dự án |
| Containers | Dung lượng Docker và runtime liên quan | Hiện Docker chỉ xem; việc dọn images/build cache/containers/volumes là roadmap riêng cần owner chốt. Không nối nút prune vào UI hiện tại |
| AI / công cụ lập trình | Cache tải model, model cục bộ, runtime, logs và session records | safety_db có nhiều entry; tách model, lịch sử hội thoại và snapshot khỏi cache. Giữ nguyên mức tác động hiện hành, không coi mọi dữ liệu của công cụ dev là rác |

Danh sách “đã có entry” chỉ xác nhận cấu hình trong `Resources/safety_db.json`, không đảm bảo công cụ đã cài, đường dẫn tồn tại hay dọn không ảnh hưởng trên máy cụ thể. Dùng metadata và policy từ model tại thời điểm quét.

#### Bố cục và luồng sử dụng

- Entry **Dọn dẹp cho lập trình viên** trong Công cụ nâng cao; họ màu tím slate của V2. Trong lúc chưa có model tổng hợp, giữ các route Cache lập trình / node_modules / Docker hiện có.
- Đầu trang: tên tính năng, phạm vi thư mục dự án, lần quét và nút Quét/Dừng. Cho chọn thư mục dự án bằng API cấp quyền của model; chưa tự mở rộng quét ngoài phạm vi hiện hành.
- Tóm tắt: tổng đo được, phần đã chọn và số dự án/công cụ tìm thấy. Không cộng trùng node_modules lồng nhau hoặc cache dùng chung; không xem dung lượng chưa đo là 0.
- Cột trái: Tất cả / Theo dự án / Cache công cụ / Dữ liệu build / Môi trường & thành phần cài đặt. Các nhóm chỉ xuất hiện khi có dữ liệu thật.
- Danh sách: tên dự án hoặc công cụ, loại dữ liệu, đường dẫn, dung lượng thực đo, trạng thái chọn, tác động và trạng thái đang sử dụng nếu model xác minh được. Tìm kiếm theo tên/path, lọc theo hệ sinh thái và sắp xếp theo dung lượng; lọc giữ selection.
- Chi tiết: dữ liệu này dùng làm gì, ảnh hưởng khi dọn, nguồn nhận diện, có thể cần tải lại/build lại hay không, cấu hình tái tạo tìm thấy. Không gắn nhãn “dự án không dùng” chỉ dựa mtime.
- Footer cố định: tổng mục/dung lượng đã chọn → Xem và xác nhận → Chuyển vào Thùng rác → kết quả từng mục và hoàn tác theo C1/C2. Quét không tự dọn; UI chỉ gọi API model/store.

`node_modules` là thư mục dependency đã cài, cần phân biệt với download cache của package manager. Dọn dependency có thể khiến dự án chưa chạy/build được cho đến khi cài lại; cache dùng chung có thể ảnh hưởng lần cài của nhiều dự án. Có manifest/lockfile không đảm bảo tái tạo được khi offline hoặc dependency riêng không còn truy cập được.

#### Quy tắc cần giữ và các lựa chọn còn chờ chốt

- Giữ policy hiện tại của model; select-all chỉ lấy mục bulk-selectable. Khi scanner tổng hợp có cả mục cha và mục con, lõi chịu trách nhiệm chuẩn hóa kế hoạch và kiểm tra lại trước thao tác.
- Mã nguồn, `.git`, `.env`, secrets, manifest, lockfile, dữ liệu database và file người dùng không phải mục tiêu của Dev Cleanup. Detector mới không theo symlink ra ngoài phạm vi hoặc chuyển nhầm pnpm store dùng chung như một thư mục dependency riêng.
- Không tự chạy `npm install`, package scripts, lệnh build, `docker prune` hay lệnh shell để “khôi phục”. Chỉ hiển thị hướng dẫn khi model xác định được công cụ và ngữ cảnh; chưa hỗ trợ thì nói rõ.
- Owner cần chốt trước khi mở rộng lõi: thư mục dự án mặc định; có tiêu chí lâu không dùng hay không và dựa dữ liệu gì; các loại output được phép dọn; cách xử lý tác vụ đang chạy; có đưa venv/SDK/Simulator/AI models vào phạm vi thao tác hay chỉ thống kê; Docker được phép dọn loại nào. Chưa có quyết định thì các nhánh mở rộng ở trạng thái đề xuất, không thay đổi policy đang chạy.

#### Nghiệm thu Dev Cleanup

- Tìm được dependency/cache trong phạm vi đã cấp quyền; không báo là trống khi thiếu quyền hoặc dừng giữa chừng.
- Dự án monorepo, workspace, symlink, đường dẫn có dấu/khoảng trắng và thư mục cha/con không gây cộng lặp hoặc mở rộng phạm vi xóa.
- Mỗi mục được giải thích bằng ngôn ngữ dễ hiểu; phân biệt dependency, cache, build output và dữ liệu cần giữ.
- Tên dự án, package manager, “đang dùng” và khả năng tái tạo chỉ hiện khi có bằng chứng; trường không biết hiển thị chưa xác định.
- Kế hoạch xác nhận nêu rõ dự án/công cụ và đường dẫn; stale identity, lỗi từng phần, hủy thao tác và undo dùng contract chung.

## 7. Contract bổ sung dành cho Claude

Đây là đề nghị về trách nhiệm và dữ liệu, tên kiểu gợi ý chưa phải tên API phải triển khai. Claude cập nhật `enhance-feat.md` §11 cùng chữ ký thực tế trước khi Codex nối UI.

| ID | Dữ liệu / hành động cần có | Yêu cầu nghiệm thu |
| --- | --- | --- |
| V2-SCAN | Phiên có sessionID, scope, timestamp; từng module có trạng thái idle/queued/running/completed/cancelled/partial/permissionDenied/failed; summary bytes và issues; start/cancel/review destination | Chuyển trang giữ phiên; không scan trùng; một nhóm lỗi không thành “all clear”; tổng không đếm lặp path |
| V2-CLEANUP | Nhóm ngữ nghĩa cache/log với ID ổn định, measuredBytes optional, selectedBytes, count, eligibility/blockedReason; group tri-state toggle qua model | Phân biệt unknown và zero; tổng nhóm không trùng path; parent checkbox chỉ thao tác con đủ điều kiện; giữ C8/C9 |
| V2-DEV | Inventory thống nhất các nhóm ở §6.7: ID ổn định, project root/tool/ecosystem, loại dependency/cache/build/environment, đường dẫn và identity, size optional, evidence, impact, eligibility/blockedReason, trạng thái sử dụng optional và hướng dẫn tái tạo có nguồn; scan/cancel/filter/plan/execute qua model | Tái sử dụng NMModel/CachesModel và C1/C2; không scan trùng, không cộng lặp parent/child hoặc shared cache; kiểm tra symlink và identity; bảo vệ source/config; nhánh mới chờ owner chốt policy; Docker vẫn chỉ xem |
| V2-TRASH | Volumes + entries có stable ID, name, original path nếu biết, size optional, source volume, metadata cloud đã xác minh; refresh/cancel/open/empty plan | Không lấy batch làm inventory; ổ tháo/thiếu quyền có trạng thái; xóa vĩnh viễn cần kế hoạch xác nhận riêng, không cam kết undo |
| V2-APPS | Version, publisher có nguồn, install source, last-used optional và độ tin cậy; các nhóm data có stable IDs và selection model | Không suy “ít dùng” từ mtime; không gán “đáng ngờ” chỉ vì thiếu chữ ký; shared data loại trừ; kết quả uninstall từng mục |
| V2-FILES | Phân loại kind, modifiedAt và accessedAt phân biệt, tiêu chí lọc có semantics; API search/filter nếu scan toàn cây | UI nói rõ chỉ lọc dữ liệu trả về hay toàn phạm vi; không tự đổi giới hạn/threshold; bản giữ duplicate luôn bảo vệ |
| V2-PROTECTION | Tài liệu engine/source, scope, finding + evidence + confidence, quyền, scan/cancel/quarantine/restore đề xuất | Owner duyệt phạm vi và hành động trước; không gắn “an toàn” nếu chưa hoàn tất/thiếu engine |
| V2-PERFORMANCE | Từng maintenance task và login/background item có nguồn, tác động, quyền, execute/undo khả dụng | Owner duyệt tác vụ; không có nút “tăng tốc” chung chạy lệnh không mô tả |
| V2-MAIL | Mail client hỗ trợ, attachment identity, local/cloud semantics, quyền, preview và kế hoạch phục hồi | Owner chốt hành vi đồng bộ và xóa; giữ bảo vệ cây Mail/iCloud đến khi có thiết kế riêng |
| V2-UPDATES | Nguồn bản cập nhật và installer đáng tin, status/version, hỗ trợ cửa hàng; kiểm tra chữ ký | Không tải/chạy installer từ URL suy đoán; owner chốt chế độ thủ công/tự động |
| V2-EXTENSIONS | Inventory loại extension, app chủ, trạng thái, đường dẫn Settings và API cho phép | Owner chốt loại nào được quản lý; không sửa cây hệ thống từ View |
| V2-SHREDDER | Đề xuất semantics và giới hạn trên APFS/SSD, quyền, xác nhận | Chờ owner quyết định có làm hay không; không hứa ghi đè bảo mật trên SSD |

## 8. Quyết định sản phẩm cần owner chốt

Các mục chưa chốt chỉ thuộc roadmap, không được tự biến thành quy tắc thực thi:

**Đã chốt trong chat 07/11/2026:** ghi đầy đủ các tính năng chưa có vào roadmap; chỉ triển khai sau khi chốt quy tắc từng tính năng. Không đưa chúng vào phạm vi lõi của đợt UI này.

1. Phạm vi Smart Scan đa module mặc định, mức tự chọn và có chạy tự động hay không.
2. Mail: client, local hay cloud; dữ liệu nào được phép xử lý và khôi phục thế nào.
3. Bảo mật: engine/nguồn dữ liệu, xử lý phát hiện và quyền.
4. Hiệu năng: danh sách maintenance task và hành vi login/background item.
5. Cập nhật và extensions: nguồn, thao tác được phép, thủ công hay tự động.
6. Shredder / xóa ngay: có đưa vào sản phẩm hay không; UI hiện tại tiếp tục dùng Trash.
7. Ngưỡng file lớn/cũ và nghĩa “ít dùng”: giữ nguyên hiện tại cho đến khi quyết định riêng.
8. Dev Cleanup: phạm vi dự án, tiêu chí dự án ít dùng, danh sách build output được dọn, xử lý tác vụ đang chạy; có dọn môi trường/SDK/Simulator/model AI và Docker hay không (§6.7). Yêu cầu có tính năng đã được chốt; các policy mở rộng này chưa được chốt.

## 9. Thứ tự thực hiện và bàn giao

### Giai đoạn A — Codex, UI trên API hiện có

- [x] Theme pastel/indigo theo module, light/dark và Reduce Transparency.
- [x] Sidebar rõ nhóm, advanced thu gọn, giữ đầy đủ route.
- [x] Smart Scan ba vùng chức năng thật, luồng scan/review/confirm không đổi lõi.
- [x] Cache cột nhóm và search trình bày, không đổi kế hoạch selection.
- [x] App picker có lọc dữ liệu đã có; pane chi tiết dễ đọc.
- [x] File lớn/cũ có lối chuyển qua lại; Trash có tổng quan trực quan và lịch sử thật.
- [x] Thành phần summary / footer / list dùng chung và localization đủ 9 bảng.
- [x] Build + SelfTest ALL PASS + l10n check; kiểm tra ảnh render nếu môi trường hỗ trợ.

### Giai đoạn B — Claude, lõi khớp V2

Đọc tài liệu này cùng contract C0–C9, xác nhận trạng thái API trong mã nguồn. Làm V2-CLEANUP / DEV / SCAN / APPS / FILES / TRASH theo thứ tự phụ thuộc và quyết định owner. Định nghĩa chữ ký thực tế tại contract trước, triển khai model/core ngoài View. Các tính năng roadmap cần quyết định ở §8 trước khi triển khai. Không ghi đè các View/theme Codex vừa thay.

Dev Cleanup triển khai theo lớp:

- [x] Claude: rà soát và chuẩn hóa inventory dev cache/node_modules đang có; cung cấp contract V2-DEV và bằng chứng nhận diện, giữ nguyên policy. (`DevCleanupModel`, enhance-feat §11 mục V2)
- [ ] Codex: dựng trung tâm Dev Cleanup theo §6.7, nối model tổng hợp; giữ nguyên các route cũ cho đến khi tích hợp đạt.
- [ ] Owner chốt phạm vi/policy của build output và môi trường; Claude bổ sung detector theo từng hệ sinh thái, rồi Codex nối nhóm tương ứng.
- [ ] Kiểm chứng dự án đơn/monorepo, shared cache, quyền, hủy, xác nhận và hoàn tác; không coi checklist này là tính năng đã triển khai.

### Giai đoạn C — Codex, tích hợp API mới

Nối từng nhóm có API hoàn chỉnh; thêm màn hình và filter tương ứng; xác minh scan/cancel/partial/permission, stale selection, app running, xác nhận, kết quả từng phần và undo sau mở lại. Không gắn nhãn hoàn tất cho API dự kiến.

## 10. Tiêu chí nghiệm thu

- Vào app biết bắt đầu từ đâu; mỗi màn hình có hành động tiếp theo rõ.
- Bảng màu và cấu trúc gợi đúng ảnh mẫu; số liệu, logo và nội dung thuộc CleanPilot.
- 1000×560 và 1080×700 không che nút chính; đường dẫn dài có truncate/help hoặc copy.
- Không quét lại chỉ vì chuyển trang hay đổi theme; không mất selection vì search/filter.
- Chưa đo / không đo được / 0 bytes / quét dừng có biểu đạt khác nhau.
- Confirm gọi đúng model/store API hiện có; không FileManager/Process/AppleScript trong View mới.
- VoiceOver đọc tên và trạng thái chọn; có thể thao tác bằng bàn phím; dark/light và Reduce Motion/Transparency hoạt động.
- Không ghi đè core/model, không commit thay đổi của Claude, không đưa ảnh tham khảo vào bundle.
- `swift build`, `swift run SelfTest` (ALL PASS), `swift build_app/l10n_tool.swift check .`.

## 11. Nhật ký thực thi Codex

Đã dựng UI trên model/core hiện có: `WorkspaceTheme.swift`, navigation/sidebar, Smart Scan, cache, app picker, liên kết file lớn/cũ, tổng quan Trash và thành phần summary/footer. Preview skin mặc định dùng cùng bảng màu V2. Màu sáng/tối theo lựa chọn appearance, Reduce Transparency dùng nền đặc. Tổng dung lượng nhóm dùng `contentsUnionSize(pathSizes(of:))` hiện có để tránh cộng lặp đường dẫn lồng nhau.

Đã kiểm tra:

- Build debug thành công. Do sandbox không ghi được cache và build output hiện có, dùng `CLANG_MODULE_CACHE_PATH=/private/tmp/cleanpilot-v2-module-cache swift build --disable-sandbox --scratch-path /private/tmp/cleanpilot-v2-build --build-system native`.
- SelfTest: **ALL PASS**. Chạy `swift run` cùng scratch path và build system; cần chạy ngoài sandbox vì một bài SelfTest hiện có thử Trash macOS với file tạm. Không sửa SelfTest.
- Localization: **đủ 9 ngôn ngữ**, `swift build_app/l10n_tool.swift check .`; 5 key mới được nối cuối cả 9 bảng.
- `git diff --check`: đạt.
- Đã xem ảnh render Smart Scan/cache/Trash ở 1080×700 (tối); Smart Scan/cache/empty Uninstaller ở 1000×560 (sáng). Nút hành động giữ ở đáy; Smart Scan và sidebar dùng cuộn ở cửa sổ nhỏ; cache đổi cột nhóm thành menu. Dữ liệu ảnh QA dùng cây tạm, không phải kết quả dọn máy của người dùng.

Đã kiểm tra thêm Uninstaller với app giả Preview Notes và data cache trong cây tạm; chọn app bằng snapshot hook hiện có, không chạy gỡ app. Smart Scan có biến thể gọn ở cửa sổ thấp.

Giới hạn kiểm chứng: chưa thao tác VoiceOver thực tế hoặc kiểm thử tương tác bằng bàn phím toàn bộ màn hình; chưa thử ma trận mọi ngôn ngữ/skin.

UI phân nhóm hệ thống/log, scan đa module, inventory Trash và các tính năng roadmap vẫn chờ contract/model của Claude như §7; chưa có engine mới trong lần sửa này. Không commit/push trong lần bàn giao này.


Ảnh xem trước (dữ liệu QA, không phải dung lượng máy thật):

- [Cache — sáng, 1000×560](v2-preview/caches-light.png)
- [Ứng dụng — tối, 1000×560](v2-preview/applications-dark.png)
- [Smart Scan — tối, 1000×560](v2-preview/smart-scan-dark.png)

Bổ sung 07/11/2026 theo yêu cầu owner: đặc tả **Dev Cleanup** tại §6.7, contract **V2-DEV** tại §7 và lộ trình tại §9. Đây là cập nhật kế hoạch; không có thay đổi UI/core trong lần bổ sung này.
