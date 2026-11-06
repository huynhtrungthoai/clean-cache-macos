# CleanPilot — Nâng cấp tính năng và UI tham khảo CleanMyMac

Ngày khảo sát: **05/11/2026**. Phạm vi: website CleanMyMac, các trang tính năng và ba ảnh giao diện ứng dụng được website công bố; đối chiếu với mã nguồn CleanPilot trong working tree hiện tại.

Đây là **tài liệu phân tích và đề xuất triển khai**. Các mục chưa hoàn thành bên dưới chưa phải tính năng đã có trong ứng dụng. Chưa cài/chạy CleanMyMac để kiểm thử hành vi; ảnh quảng bá chỉ chứng minh bố cục được thể hiện, không xác nhận mọi trạng thái tương tác hoặc khác biệt giữa các bản phân phối.

## 1. Hướng nâng cấp

CleanPilot nên phát triển từ công cụ dọn cache thành trung tâm quản lý dung lượng dễ hiểu: **quét → giải thích kết quả → xem và chọn → xác nhận → chuyển vào Thùng rác → kiểm tra/hoàn tác**.

Điểm đáng học từ CleanMyMac là gom công cụ theo nhu cầu, trình bày kết quả bằng thẻ dễ đọc, làm rõ bước tiếp theo và cho phép đi sâu vào từng nhóm. CleanPilot đã có nền tảng dọn file, gỡ app và xem ổ đĩa; ưu tiên kết nối các phần này thành trải nghiệm thống nhất trước khi mở rộng sang dịch vụ cloud hoặc bảo mật.

Định hướng kỹ thuật đề xuất:

- Tái sử dụng SwiftUI, `ScanStore`, mô hình quét và hệ thống theme hiện có.
- Giữ bản sắc CleanPilot: tiếng Việt, giải thích tác động của từng mục, dữ liệu thực đo và khả năng hoàn tác có điều kiện.
- Mượn cách tổ chức thông tin; tự thiết kế hình minh họa, biểu tượng và nội dung cho CleanPilot.
- Giữ các quy tắc bảo vệ đường dẫn hiện hành. Mọi thay đổi về phạm vi xóa, tự chọn, tự chạy hoặc quyền truy cập cần chủ sản phẩm chốt trước khi lập trình.
- Các mức ưu tiên P0–P3 trong tài liệu là đề xuất thứ tự kỹ thuật, chưa phải cam kết phát hành.

## 2. CleanMyMac hiện giới thiệu những gì?

| Nhóm | Khả năng được website giới thiệu | Ý nghĩa với CleanPilot |
| --- | --- | --- |
| Smart Care | Quét tổng hợp năm tác vụ chính | Một điểm bắt đầu, kết quả chia theo nhu cầu; cần định nghĩa riêng phạm vi quét của CleanPilot |
| Cleanup | Cache, log, dữ liệu thừa; thêm công cụ xử lý binary/ngôn ngữ thừa | Mở rộng phân nhóm trên nền scanner hiện tại; các thao tác sửa nội dung app cần đánh giá riêng |
| Clutter | File lớn, file trùng, ảnh tương tự, quản lý Downloads | Gom công cụ tìm file vào một nơi; tách trùng nội dung và ảnh gần giống |
| Space Lens | Bản đồ dung lượng tương tác, đi sâu vào thư mục | Bổ sung chế độ trực quan cho Tổng quan dung lượng |
| Applications | Gỡ app, dữ liệu còn sót, app ít dùng, cập nhật app | Tạo trung tâm quản lý app thống nhất |
| Performance | Mục đăng nhập, tiến trình nền, tác vụ bảo trì | Một nhánh mới; không đồng nhất với bật CleanPilot lúc đăng nhập |
| Menu và My Activity | CPU, bộ nhớ, dung lượng; lịch sử hoạt động | Nâng cấp menu bar và lịch sử dựa trên số liệu đo được |
| Protection và Privacy | Quét malware, kiểm tra file tải về, quyền app, dấu vết trình duyệt | Phạm vi mới, cần xác định khả năng và nguồn dữ liệu trước |
| Cloud Cleanup | iCloud, Google Drive, OneDrive, Dropbox; file lớn và bản sao cục bộ | Tách dung lượng trên máy với quota cloud và hậu quả đồng bộ |
| Mail | Gom nguồn email đăng ký, dọn thư quảng cáo, hủy đăng ký | Nhánh mở rộng độc lập, phụ thuộc tích hợp tài khoản |

Nguồn: [Smart Care và tổng quan](https://cleanmymac.com/), [Cleanup/Clutter/Space Lens](https://cleanmymac.com/mac-cleaner), [Applications](https://cleanmymac.com/mac-app-uninstaller), [Performance/Menu/My Activity](https://cleanmymac.com/mac-optimizer), [Protection/Privacy](https://cleanmymac.com/mac-malware-removal), [Cloud/Mail](https://cleanmymac.com/mac-cloud-cleanup).

Các số liệu tốc độ, tỷ lệ phát hiện malware, dung lượng tiết kiệm và chứng nhận trên website là công bố của nhà cung cấp. Không dùng chúng làm cam kết của CleanPilot hoặc tiêu chí nghiệm thu.

## 3. Đối chiếu với CleanPilot hiện tại

“Đã có” dưới đây là có mã nguồn tương ứng; không thay thế kiểm thử trên máy thật. Các đường dẫn tính từ gốc repository.

| Hạng mục | Hiện trạng trong mã nguồn | Khoảng trống / nâng cấp đề xuất | Ưu tiên |
| --- | --- | --- | --- |
| Quét thông minh | `SmartScanView.swift`: dùng `CachesModel` cho cache ứng dụng và lập trình; có tiến độ, dừng, xem kết quả | Điều phối nhiều nhóm quét; không mô tả hiện tại là quét sức khỏe toàn máy | P1 |
| Cache và log | `CachesView.swift`, `Categories.swift`, `Scanner.swift`, `safety_db.json` | Gom nhóm dễ hiểu; giải thích nguồn, tác động và lý do không chọn được | P0/P1 |
| Tổng quan ổ đĩa | `OverviewView.swift`, `FolderDrillView.swift`, `RingGeometry.swift` | Thêm bản đồ treemap đi cùng danh sách, breadcrumb và chọn đồng bộ | P2 |
| File lớn / lâu không sửa | `BigOldViews.swift` | Gom trong Dọn file; lọc và xem trước nhất quán. Ngày sửa file không chứng minh file không còn dùng | P1 |
| File trùng | `DupOrphansViews.swift`, `findDupGroups`, `duplicateStillMatches` | Làm rõ bản giữ; kiểm chứng nội dung trước thao tác. File lớn hiện có bước dùng hash một phần, chưa thể hứa mọi file được so toàn bộ byte | P0/P1 |
| Ảnh tương tự | Chưa thấy bộ phân tích ảnh gần giống trong các model quét đã đọc | Nhóm gợi ý riêng; xem ảnh cạnh nhau; không dùng kết quả gần giống như bằng chứng trùng tuyệt đối | P3 |
| Downloads | Có thể tìm file qua quét file lớn/cũ và thư mục | Trang tập trung cho bộ cài, file tải về; chưa có workflow chuyên biệt | P2 |
| Gỡ ứng dụng | `UninstallView.swift`, `Uninstall.swift`: từng app, bản thân app và dữ liệu liên quan; có loại trừ dữ liệu dùng chung | Gom với dữ liệu còn sót; thêm thông tin phiên bản, trạng thái đang chạy và kết quả từng phần | P0/P1 |
| Dữ liệu app còn sót | `OrphansModel`, `scanOrphans` | Hiện căn cứ nhận diện và độ chắc chắn; nhận diện yếu không trở thành khuyến nghị xóa chắc chắn | P1 |
| Cập nhật app / app ít dùng | `InstalledApp` hiện chưa chứa phiên bản và lần sử dụng cuối | Bổ sung metadata, nguồn cập nhật và trạng thái không xác định; cần chốt phạm vi | P3 |
| Login/background items | `Prefs.swift` quản lý khởi động của chính CleanPilot | Chưa có trình quản lý mục đăng nhập và tiến trình nền của các app khác | P2/P3 |
| Menu bar | `MenuBar.swift`: số liệu dung lượng, làm mới mỗi 5 giây, mở app | Thêm CPU/memory pressure sau khi có bộ đo; không mặc định thêm nút “tăng tốc” | P2 |
| Lịch sử / hoàn tác | `AppStore.trashHistory` trong RAM; có `undoLast`, `undoBatch` và `TrashView` | Lưu bền vững theo lô; phục hồi sau mở lại app; giải thích khi file không còn trong Thùng rác | P0/P1 |
| Malware / quyền app / privacy | Chưa có module sản phẩm tương ứng trong điều hướng và scanner đã đọc | Phân biệt hướng dẫn hệ thống, kiểm tra cấu hình và engine chống malware | P3 |
| Cloud / Mail | Chưa có module kết nối tài khoản; lõi hiện bảo vệ cây iCloud/Mail nhạy cảm | Cần thiết kế tích hợp, quyền và phục hồi riêng; không mở khóa cây nhạy cảm để tái sử dụng thao tác xóa thông thường | P3 |
| Công cụ lập trình | Đã có dev cache, node_modules, thống kê Docker, chẩn đoán và Agent | Giữ trong Công cụ nâng cao; Docker hiện chỉ xem | Duy trì |

Tham chiếu nền tảng: [luồng sử dụng hiện hành](../README.md), [audit và lỗi cần xử lý](TODO.md), [quyền riêng tư](PRIVACY.md). Nếu README, TODO và implementation khác nhau, kiểm tra mã nguồn và bản build trước khi kết luận.

## 4. Phân tích UI tham khảo

### 4.1 Những gì đã quan sát trực tiếp

**Website:** hero lớn, nền hồng/tím, logo nổi bật, thanh điều hướng dạng viên thuốc, nút hành động rõ, nội dung chia theo lợi ích rồi đến hình ảnh minh họa và FAQ. Đây là bố cục marketing, không phải cấu trúc nên bê nguyên vào màn hình làm việc. Nguồn: [trang chủ](https://cleanmymac.com/).

**Ảnh ứng dụng được trang chủ liên kết:**

| Màn hình | Quan sát từ ảnh | Áp dụng cho CleanPilot |
| --- | --- | --- |
| Cleanup | Sidebar biểu tượng; nền xanh; tổng dung lượng ở đầu; các thẻ System Junk, Trash Bins, Extra Binaries; hành động xem/xử lý trong từng thẻ | Thẻ kết quả theo nhóm, số liệu lớn và nút xem chi tiết. Thùng rác vẫn có luồng xác nhận riêng theo quy tắc hiện hành |
| Applications — kết quả | Nền xanh/tím; panel lớn; trạng thái hoàn tất, số bản cập nhật, liên kết log và nút hoàn thành | Trang kết quả rõ số thành công/thất bại và liên kết lịch sử |
| Space Lens | Sidebar, danh sách chọn bên trái, breadcrumb và bong bóng dung lượng bên phải; tổng mục/GB đã chọn cạnh CTA | Danh sách và biểu đồ cùng một selection; luôn biết phạm vi đang xem và tổng đang chọn |

Ảnh tham chiếu: [Cleanup](https://macpaw.com/cdn-cgi/image/format%3Dauto%2Cformat%3Dpng%2Cquality%3D60%2Cwidth%3D872%2Cdpr%3D2/https%3A//cdn3.macpaw.com/images/content/image_1779975649.png), [Applications](https://macpaw.com/cdn-cgi/image/format%3Dauto%2Cformat%3Dpng%2Cquality%3D60%2Cwidth%3D640%2Cdpr%3D2/https%3A//cdn3.macpaw.com/images/content/image_1779977922.png), [Space Lens](https://macpaw.com/cdn-cgi/image/format%3Dauto%2Cformat%3Dpng%2Cquality%3D60%2Cwidth%3D640%2Cdpr%3D2/https%3A//cdn3.macpaw.com/images/content/image_1779980466.png). Ảnh phục vụ tham khảo, không đưa vào tài nguyên phát hành CleanPilot.

### 4.2 Kiến trúc điều hướng đề xuất

Triển khai trước các nhóm đã có chức năng:

```text
CleanPilot
├── Quét thông minh
├── Dọn dẹp
│   ├── Cache ứng dụng
│   └── Thùng rác
├── Ứng dụng
│   ├── Gỡ ứng dụng
│   └── Dữ liệu còn sót
├── File và dung lượng
│   ├── Tổng quan dung lượng
│   ├── File lớn
│   ├── File lâu không sửa
│   └── File trùng
├── Công cụ nâng cao
│   ├── Cache lập trình / node_modules
│   ├── Docker / Chẩn đoán
│   └── AI Agent (theo kênh phân phối hiện hành)
└── Cài đặt / Giao diện / Trợ giúp
```

Khi có chức năng thật và phạm vi được chốt mới bổ sung Downloads, Hiệu năng, Bảo mật, Cloud và Hoạt động. Không tạo các trang rỗng mang thông điệp máy đã được tối ưu hoặc bảo vệ.

Giữ icon kèm nhãn tiếng Việt để dễ tìm công cụ; sidebar có thể cuộn. Điều hướng mới phải ánh xạ được các `Panel` hiện hành, giữ lịch sử quay lại và không làm mất tác vụ đang quét.

### 4.3 Bố cục màn hình chung

1. **Đầu trang:** tên tính năng, mô tả một câu, phạm vi và thời điểm quét.
2. **Vùng tóm tắt:** một số liệu chính; các thẻ phụ trình bày từng nhóm kết quả.
3. **Vùng làm việc:** danh sách hoặc bảng, bộ lọc, tìm kiếm, khung chi tiết/xem trước.
4. **Thanh hành động cố định:** số mục và dung lượng đã chọn, hành động tiếp theo, giải thích ngắn về hậu quả.
5. **Kết quả thao tác:** thành công, bỏ qua, thất bại; xem chi tiết và hoàn tác nếu còn khả dụng.

Wireframe quét tổng hợp đề xuất, chỉ hiển thị các module đã triển khai:

```text
┌──────────────────┬──────────────────────────────────────────────┐
│ CleanPilot       │ Quét thông minh          Phạm vi: ...        │
│                  │                                              │
│ Quét thông minh  │ [Biểu tượng]   Tìm dung lượng có thể dọn      │
│ Dọn dẹp          │                [Quét ngay]                   │
│ Ứng dụng         │                                              │
│ File và dung lượng│ [Cache] [File cần xem] [Dữ liệu app]         │
│ Công cụ nâng cao │ Mỗi nhóm có kết quả và nút Xem chi tiết      │
│                  │                                              │
│                  │ Đã quét ... / Bỏ qua ... / Thiếu quyền ...   │
│ Cài đặt          ├──────────────────────────────────────────────┤
│ Trợ giúp         │ Đã chọn: ... mục · ... GB   [Xem và xác nhận]│
└──────────────────┴──────────────────────────────────────────────┘
```

### 4.4 Hệ thống thị giác đề xuất cho CleanPilot

Các thông số sau là lựa chọn thiết kế mới, không phải số đo trích xuất từ CleanMyMac:

| Thành phần | Quy cách đề xuất |
| --- | --- |
| Màu | Dùng `ThemePalette`: `paper`, `surface`, `surfaceAlt`, `ink`, `tint`, `danger`; mỗi module có màu nhấn nhẹ, nội dung chính giữ tương phản rõ |
| Nền | Gradient nhẹ ở vùng minh họa/tóm tắt; nền bảng ổn định để đọc đường dẫn dài |
| Chữ | Font hệ thống; tiêu đề trang 26–34 pt, số liệu chính 32–40 pt, nội dung 13–15 pt; số dung lượng dùng chữ số cố định |
| Khoảng cách | Lưới 4/8 pt; đệm trang 24–32 pt; khoảng giữa nhóm 24 pt; giữa thẻ 12–16 pt |
| Thẻ | Bo góc 16–20 pt, một cấp viền/bóng nhẹ; tái sử dụng `ThemedCard` và `ThemeMetric` |
| CTA | Một hành động chính theo giai đoạn; dùng động từ cụ thể: Quét, Xem chi tiết, Xem và xác nhận, Chuyển vào Thùng rác |
| Icon | SF Symbols và biểu tượng CleanPilot tự thiết kế; cùng kích thước và độ đậm |
| Chuyển động | 150–250 ms cho chuyển trạng thái; tôn trọng Reduce Motion; không dùng hoạt ảnh giả tiến độ |
| Cửa sổ | Kiểm tra ở tối thiểu hiện hành 1000×560 và kích thước thông thường 1080×700; nội dung cuộn, thanh thao tác luôn tiếp cận được |

Tiêu chí khả dụng: thao tác bằng bàn phím; thứ tự focus hợp lý; VoiceOver đọc được tiêu đề, checkbox, dung lượng và lỗi; không chỉ dùng màu để phân loại tác động; hỗ trợ sáng/tối và Reduce Transparency. Khi thu hẹp cửa sổ, thẻ xếp lại theo chiều dọc và panel chi tiết có thể mở riêng.

## 5. Đặc tả nâng cấp theo nhóm

### F01 — Quét thông minh nhiều module

**Hiện tại:** quét cache. **Đích đề xuất:** một phiên quét tổng hợp có thể nhận kết quả từ cache, dữ liệu app còn sót và công cụ file đã có, sau khi chủ sản phẩm chọn phạm vi mặc định.

- Mỗi module báo trạng thái riêng: chờ, đang quét, hoàn tất, bị hủy, thiếu quyền, lỗi hoặc chỉ có kết quả một phần.
- Tác vụ sống trong store; đổi trang không tạo phiên quét trùng hoặc mất tiến độ.
- Một module lỗi không khiến toàn phiên hiển thị “mọi thứ đều ổn”.
- Kết quả tổng hợp dẫn đến đúng nhóm và giữ lựa chọn khi quay lại.
- Phân biệt dung lượng phát hiện, dung lượng được đề xuất và dung lượng người dùng đã chọn.
- Trùng đường dẫn giữa các module chỉ tính một lần; chọn cha/con không cộng hai lần.
- Khi chưa biết tổng khối lượng công việc, dùng tiến độ không xác định hoặc tên giai đoạn thay vì phần trăm giả.

**Nghiệm thu:** rời/quay lại trang vẫn cùng phiên quét; thiếu quyền một root được ghi rõ; tổng không đếm lặp; quét không tự thực thi cleanup.

### F02 — Dọn dẹp có giải thích

- Thẻ nhóm hiển thị dung lượng, số mục, tác động và nút xem danh sách.
- Mỗi hàng có tên, vị trí, app liên quan nếu xác định được, dung lượng thực đo và lý do phân loại.
- Phân biệt “không ảnh hưởng theo cơ sở tri thức”, “cần tải lại”, “có thể mất dữ liệu”, “chưa xác định”; giữ nguyên gate bảo vệ hiện hành.
- Mục bị khóa có lời giải thích tại chỗ; chọn tất cả không vượt qua giới hạn bảo vệ.
- Xem trong Finder và xem trước có thể dùng trước khi quyết định.
- Dọn Thùng rác tách khỏi chuyển file vào Thùng rác; không gộp thành một nút làm cả hai.
- Sửa sai số kích thước và cập nhật kết quả sau thao tác theo [TODO mục 2.10](TODO.md#210--sai-kế-toán-dung-lượng-ở-trang-caches).

**Nghiệm thu:** số liệu trước xác nhận khớp kế hoạch thực thi; mục không đo được không bị trình bày là 0 B; lỗi từng file được phản ánh đúng vào tổng kết.

### F03 — Dọn file: lớn, cũ, trùng, Downloads

- Một bộ lọc và layout thống nhất cho loại file, vị trí, kích thước, ngày sửa và phạm vi quét; giá trị mặc định của các bộ lọc cần được chốt.
- Giữ nhãn “lâu không sửa” đúng dữ liệu hiện có; chỉ dùng nhãn “ít sử dụng” khi có nguồn đo phù hợp.
- File trùng có hàng “Bản giữ lại”; hiển thị tiêu chí chọn bản giữ và cho xem trước.
- Trước thao tác phải kiểm tra lại bản giữ và bản định chuyển; dữ liệu thay đổi thì bỏ qua nhóm và yêu cầu quét lại.
- Chuyển sang xác minh đầy đủ nội dung cho kết luận trùng tuyệt đối, chạy ngoài main thread và có thể hủy; không chỉ dựa vào hash đầu/cuối file lớn.
- Ảnh gần giống là nhánh riêng nếu được chọn triển khai: ảnh cạnh nhau, độ phân giải, kích thước, ngày và độ tương đồng; không tự chọn xóa từ độ tương đồng.
- Downloads là góc nhìn chuyên biệt trên file người dùng, không suy ra “rác” chỉ vì file có đuôi `.dmg`, `.pkg` hoặc `.zip`.

**Nghiệm thu:** file lớn có nội dung giữa khác nhau không bị kết luận trùng tuyệt đối; bản giữ đã mất khiến thao tác bị chặn; thay bộ lọc không để lại lựa chọn ẩn khó nhận biết.

### F04 — Bản đồ dung lượng

- Dùng **treemap** làm lựa chọn kỹ thuật ban đầu: SwiftUI/Canvas, diện tích tỷ lệ theo dung lượng; vẫn có danh sách tương đương để đọc và dùng VoiceOver.
- Tái sử dụng số liệu Overview/Folder Drill thay vì tạo một scanner độc lập có cách tính khác.
- Breadcrumb, nút lên thư mục cha, sắp theo dung lượng; chọn trong biểu đồ phản ánh ở danh sách và ngược lại.
- Ghi rõ dung lượng logic và dung lượng chiếm trên đĩa nếu có cả hai; thống nhất đơn vị giữa biểu đồ, bảng và thanh hành động.
- Không cộng riêng “khoảng trống chưa đo” vào dung lượng có thể dọn; APFS clone/hard link/purgeable có thể làm tổng file khác mức dung lượng ổ đĩa.
- Biểu đồ là cách khám phá; khả năng thao tác vẫn theo các gate bảo vệ hiện có.

**Nghiệm thu:** đi sâu/quay lại đúng thư mục; nhãn và tổng chọn khớp danh sách; thư mục không đọc được có trạng thái riêng; render biểu đồ không chặn giao diện.

### F05 — Trung tâm ứng dụng

- Giữ bố cục danh sách app và panel chi tiết; thêm các lối chuyển rõ giữa Gỡ ứng dụng và Dữ liệu còn sót.
- Chi tiết trình bày app, dữ liệu riêng, dữ liệu dùng chung bị loại trừ và tổng kế hoạch.
- Kiểm tra app đang chạy trước khi gỡ; hành vi từ chối hay đề nghị thoát cần chủ sản phẩm quyết định.
- Chuẩn hóa kết quả gỡ một phần: app đã chuyển nhưng một số dữ liệu chưa chuyển; có log và khả năng phục hồi theo lô.
- Có thể bổ sung phiên bản và nguồn cài. Khi chưa biết lần mở gần nhất thì hiện “Chưa xác định”.
- App Updater là dự án riêng: đọc nguồn đáng tin, kiểm tra chữ ký, tách app App Store và app tải trực tiếp; chưa mặc định cập nhật hàng loạt.

**Nghiệm thu:** không gỡ chính CleanPilot; không chọn dữ liệu dùng chung; app bản thân chuyển thất bại thì không tiếp tục chuyển dữ liệu liên quan; kết quả và hoàn tác bao quát cùng một lô.

### F06 — Hoạt động và hoàn tác

- Mỗi lần thao tác có batch ID, thời điểm, module nguồn, các mục thành công/thất bại và đường dẫn khôi phục.
- Tách ba khái niệm: dung lượng đã chuyển vào Thùng rác, đã khôi phục và thay đổi dung lượng trống đo được. Không gọi toàn bộ dung lượng chuyển vào Thùng rác là đã giải phóng.
- Tái sử dụng `undoBatch`; bổ sung lưu bền vững với quyền file hạn chế và ghi atomic.
- Trước khôi phục kiểm tra bản ghi, vị trí trong Thùng rác và xung đột đường dẫn; không ghi đè file mới.
- Khi không còn file để khôi phục, hiện lý do và vô hiệu hóa thao tác tương ứng.
- Chỉ thống kê số đo thực; không tạo chỉ số “thời gian tiết kiệm”, “tăng tốc” hoặc “mối đe dọa đã chặn” nếu chưa có cách đo.

**Nghiệm thu:** mở lại app vẫn xem được lô đã lưu; batch khôi phục một phần có kết quả chính xác; dữ liệu lịch sử bị sửa không trở thành quyền di chuyển file tùy ý.

### F07 — Hiệu năng và menu bar

Triển khai đề xuất ban đầu ở chế độ quan sát: CPU, memory pressure và dung lượng, kèm thời điểm cập nhật và trạng thái không đo được. Dùng một service đo dùng chung cho menu và cửa sổ; không chạy quét ổ đĩa chỉ để mở popover.

Mục đăng nhập/tiến trình nền cần khảo sát API macOS và quyền theo từng kênh trước khi thiết kế nút bật/tắt. Việc CleanPilot đăng ký chính nó qua `SMAppService.mainApp` không chứng minh có thể điều khiển mọi app khác. Không ghi trực tiếp cơ sở dữ liệu TCC hoặc tệp hệ thống để vượt qua giao diện cấp quyền.

**Nghiệm thu:** trạng thái cũ hoặc không đọc được không thành 0; menu và màn hình dùng cùng nguồn số liệu; tần suất đo/tiêu thụ tài nguyên được kiểm tra trước phát hành. Nút thoát app khác, dọn RAM hoặc chạy bảo trì chỉ đưa vào khi phạm vi được chốt.

### F08 — Các nhánh cần nghiên cứu và quyết định riêng

| Nhánh | Phương án để đánh giá | Điều kiện trước khi triển khai |
| --- | --- | --- |
| Bảo mật | Hướng dẫn kiểm tra cấu hình hệ thống, hoặc tích hợp engine malware có nguồn rõ | Chọn mức cam kết sản phẩm, nguồn engine/rule, cơ chế cập nhật và xử lý false positive; không suy ra an toàn chỉ từ chữ ký hợp lệ |
| Quyền ứng dụng | Hướng dẫn/mở đúng trang Privacy & Security; chỉ liệt kê dữ liệu quyền thực sự đọc được | Xác minh API hỗ trợ, giới hạn sandbox và lựa chọn cách thu hồi quyền |
| Dữ liệu trình duyệt | Tách cache với cookie/lịch sử/autofill, mô tả tác động từng loại | Chốt loại dữ liệu được phép xử lý, yêu cầu đóng trình duyệt và cách phục hồi; giữ gate hiện tại đến khi có thiết kế được duyệt |
| Cloud | Giai đoạn khảo sát có thể chỉ xem metadata; tách xóa từ cloud và giải phóng bản sao cục bộ | Chọn nhà cung cấp, quyền/OAuth, giới hạn thao tác, tác động đồng bộ và cơ chế khôi phục; không tái dùng local Trash như bảo đảm hoàn tác cloud |
| Mail | Khảo sát API tài khoản, danh sách đăng ký và khả năng khôi phục thư | Chủ sản phẩm quyết định có thuộc CleanPilot hay không; không coi link hủy đăng ký là luôn đáng tin hoặc tự mở link trong thư |
| Binary/ngôn ngữ thừa | Chỉ nghiên cứu chi phí/lợi ích, tương thích và chữ ký app | Quyết định có cho phép sửa app bundle; không thực thi trong luồng cleanup hiện hành |

Các nhánh này thay đổi đáng kể mô hình hiện tại ưu tiên xử lý cục bộ. Cần cập nhật tài liệu quyền riêng tư, quyền hệ thống và kiểm thử cho từng tích hợp sau khi xác định phạm vi.

## 6. Trạng thái và câu chữ bắt buộc nhất quán

| Trạng thái | Hiển thị / hành động |
| --- | --- |
| Chưa quét | Mô tả phạm vi; Quét ngay; chưa có số liệu thì không tạo số minh họa |
| Đang quét | Giai đoạn hiện tại, tiến độ có căn cứ; Dừng quét |
| Đã dừng | Ghi rõ kết quả chưa đầy đủ; Quét lại |
| Thiếu quyền | Vị trí bị bỏ qua và hướng dẫn cấp quyền; phân biệt với không tìm thấy file |
| Quét lỗi/một phần | Phần thành công và phần chưa kiểm tra; thử lại đúng phần lỗi |
| Không có kết quả | “Không tìm thấy mục phù hợp trong phạm vi đã quét”; không suy rộng thành máy hoàn toàn sạch/an toàn |
| Có kết quả | Tổng phát hiện, tổng đề xuất, tổng đã chọn; Xem chi tiết |
| Xác nhận | Danh sách/tổng thực tế, tác động, nơi chuyển đến; Chuyển vào Thùng rác |
| Đang thực hiện | Số mục đã xử lý; không cho bấm chạy lặp. Nếu hỗ trợ dừng thì giải thích các mục đã chuyển vẫn giữ nguyên trạng thái |
| Hoàn tất / một phần | Đã chuyển / bỏ qua / thất bại; Xem chi tiết; Hoàn tác lô nếu khả dụng |
| Không thể hoàn tác | Lý do cụ thể; không hứa “luôn có thể khôi phục” |

Ví dụ câu chữ: “Tìm thấy 4,2 GB trong các mục đã quét”, “Đã chọn 1,6 GB để chuyển vào Thùng rác”, “Đã chuyển 12 mục; 2 mục chưa xử lý”, “Dung lượng trống có thể chưa tăng khi file còn trong Thùng rác”. Các con số này chỉ là ví dụ trong tài liệu.

## 7. Kế hoạch thực hiện đề xuất

### P0 — Nền tảng số liệu và phục hồi

Đối chiếu lại [TODO](TODO.md) trước khi thay UI; không đánh dấu lỗi đã sửa chỉ từ tài liệu audit.

- [ ] Kiểm tra và sửa cách tính kích thước cache, loại trùng cha/con, làm mới kết quả sau thao tác.
- [ ] Chuẩn hóa kiểm tra lại file trước thao tác và xác minh bản giữ của file trùng.
- [ ] Thiết kế lưu lịch sử theo lô, kiểm tra tính hợp lệ khi khôi phục và trạng thái khôi phục một phần.
- [ ] Xử lý dữ liệu quét cũ, app đang chạy và lỗi cấp quyền theo các quy tắc được chốt.
- [ ] Hoàn tất các lỗi bảo mật còn mở trong TODO phù hợp với luồng được sửa trước khi phát hành.

### P1 — Trải nghiệm cốt lõi

- [x] Chuẩn hóa header, thẻ, thanh hành động và trang kết quả cho các công cụ hiện có.
- [ ] Thống nhất tiếng Việt, số liệu và trạng thái theo mục 6.
- [ ] Kết nối quét tổng hợp với các module/phạm vi đã được chủ sản phẩm chọn.
- [x] Gom quản lý app và dữ liệu còn sót; liên kết lịch sử và hoàn tác.
- [ ] Nghiệm thu bàn phím, VoiceOver, sáng/tối và cửa sổ tối thiểu.

### P2 — Khám phá dung lượng và giám sát

- [ ] Bổ sung treemap dùng chung dữ liệu với Overview/Folder Drill — đã có Canvas + danh sách + lựa chọn đồng bộ từ FolderDrillModel; nghiệm thu thuật toán còn chờ C7 `merged`.
- [ ] Thêm góc nhìn Downloads sau khi chốt bộ lọc.
- [ ] Nâng menu bar với CPU/memory pressure sau khi đo được chi phí tài nguyên.
- [ ] Làm thử nghiệm chỉ đọc cho login/background items bằng API được hỗ trợ.

### P3 — Tích hợp mở rộng

- [ ] Chọn và đặc tả từng nhánh: ảnh tương tự, cập nhật app, quyền/privacy, malware, cloud hoặc mail.
- [ ] Kiểm tra quyền/API, nguồn dữ liệu, trường hợp lỗi và khả năng phục hồi trước khi dựng UI hứa hẹn thao tác.
- [ ] Cập nhật tài liệu quyền riêng tư và kiểm thử theo kênh phân phối cho nhánh được chọn.

## 8. Điểm sửa mã dự kiến và kiểm chứng

Đây là bản đồ triển khai, chưa yêu cầu tạo ngay tất cả file mới:

| Khu vực | Điểm tích hợp |
| --- | --- |
| Điều hướng và state | `Sources/DiskCleaner/DiskCleanerApp.swift`: `Panel`, `ContentView`, `ScanStore`, `AppStore` |
| Quét tổng hợp | `Sources/DiskCleaner/Views/SmartScanView.swift`; bổ sung coordinator/model riêng nếu đã chốt nhiều module |
| Dọn và kết quả | `Sources/DiskCleaner/Views/CachesView.swift`, `SharedViews.swift`, `TrashView.swift` |
| File và bản đồ | `BigOldViews.swift`, `DupOrphansViews.swift`, `OverviewView.swift`, `FolderDrillView.swift`; view treemap tách riêng để tránh tiếp tục phình Overview |
| Ứng dụng | `Sources/DiskCleaner/Views/UninstallView.swift`, `Sources/DiskCleanerCore/Uninstall.swift` |
| Design tokens | `Sources/DiskCleaner/Theme/Theme.swift`, `Components.swift`, `Resources/skins.json` |
| Menu và quyền | `Sources/DiskCleaner/MenuBar.swift`, `Prefs.swift`, `HomeGrant.swift`, `Sources/DiskCleanerCore/HomeAccess.swift` |
| Lõi thao tác | `Models.swift`, `Scanner.swift`, `ScanJobs.swift`; mọi luồng mới tiếp tục đi qua gate chung |
| Ngôn ngữ / kiểm thử | `Sources/DiskCleaner/Resources/*.lproj/Localizable.strings`, `Sources/SelfTest/main.swift`, `build_app/build.sh` |

Kiểm chứng khi triển khai: `swift build`, `swift run SelfTest` và build đóng gói bằng quy trình hiện có. Thêm kiểm thử hành vi cho thay đổi lõi: đường dẫn được bảo vệ, cha/con trùng, file đổi sau quét, bản giữ bị mất, lịch sử sai, khôi phục xung đột và thao tác thất bại một phần. Kiểm tra UI trực tiếp với thư mục fixture dùng riêng: thiếu quyền, không có kết quả, lỗi một phần, tên file dài, nhiều kết quả và đổi trang khi đang quét.

Chỉ thay đổi tài liệu này chưa cần chạy build/test của ứng dụng; không diễn giải việc rà soát tài liệu thành bằng chứng tính năng đã hoạt động.

## 9. Các quyết định sản phẩm còn mở

Ghi nhận để chủ sản phẩm chốt ở giai đoạn triển khai; tài liệu này không tự thay đổi quy tắc đang có:

1. Quét thông minh gồm những nhóm và thư mục nào? Giữ mặc định quét cache hay thêm app/file người dùng?
2. Có thay đổi quy tắc đề xuất/tự chọn hiện tại không? Có thao tác tự động hoặc lịch chạy không?
3. Các ngưỡng kích thước, số ngày, độ tương đồng và tiêu chí app “ít dùng” là gì?
4. ~~App đang chạy: từ chối gỡ hay cho phép đề nghị thoát rồi tiếp tục?~~ **Đã chốt:** đề nghị thoát rồi gỡ tiếp; người dùng có thể từ chối (xem C4).
5. Login items/tiến trình nền: chỉ xem, mở System Settings hay cho thao tác trong CleanPilot?
6. Thời gian lưu lịch sử, dữ liệu cần lưu và quyền xóa lịch sử là gì?
7. Có mở rộng sang cập nhật app, bảo mật, cloud và mail không? Nếu có, ưu tiên nhánh nào, nhà cung cấp nào và phạm vi quyền nào?
8. Có mô hình miễn phí/trả phí, giới hạn tính năng hoặc hỗ trợ khác nhau giữa các kênh không? Không suy ra từ mô hình kinh doanh CleanMyMac.

## 10. Nguồn khảo sát

Tất cả được truy cập ngày 05/11/2026:

- [Trang chủ CleanMyMac](https://cleanmymac.com/): định vị, nhóm tính năng, Smart Care và ảnh UI tham chiếu.
- [Junk Cleanup](https://cleanmymac.com/mac-cleaner): cleanup, file lớn/trùng/ảnh tương tự và Space Lens.
- [Mac Optimization](https://cleanmymac.com/mac-optimizer): hiệu năng, menu bar và My Activity.
- [App Uninstaller](https://cleanmymac.com/mac-app-uninstaller): gỡ app, dữ liệu còn sót và cập nhật.
- [Malware Protection](https://cleanmymac.com/mac-malware-removal): malware, quyền app và dấu vết riêng tư.
- [Cloud Cleanup](https://cleanmymac.com/mac-cloud-cleanup): cloud và công cụ email được giới thiệu.

Các đặc tả CleanPilot, lựa chọn kỹ thuật, mức ưu tiên và tiêu chí nghiệm thu trong tài liệu là đề xuất dựa trên đối chiếu mã nguồn, không phải mô tả hành vi nội bộ đã kiểm chứng của CleanMyMac.

## 11. Contract — giao diện giữa phần lõi (Claude) và UI (Codex)

Ranh giới sở hữu: xem `CLAUDE.md` và `AGENTS.md`. Claude cung cấp model/API dưới đây; Codex chỉ dùng chúng trong View. Muốn đổi chữ ký API thì sửa mục này trước (qua PR), rồi mới sửa code. Trạng thái: `draft` → `agreed` (chủ dự án duyệt) → `merged` (đã vào `main`).

### C0 — Tách model khỏi file View · P0 · Claude · `merged` (6221347)

- Di chuyển nguyên trạng các lớp `ObservableObject` từ `Views/*.swift` sang `Sources/DiskCleaner/Models/`: `CachesModel`, `BigFilesModel`, `OldFilesModel`, `FolderDrillModel`, `DupModel`, `OrphansModel`, `UninstallModel`, `NMModel`, `DockerModel`, `OverviewModel`.
- Chỉ di chuyển, không đổi hành vi hay tên. Merge sớm nhất có thể; Codex rebase lên trước khi sửa View tương ứng.

### C1 + C2 — Thực thi kế hoạch, kiểm tra lại, lịch sử theo lô, hoàn tác · P0 · Claude · `merged` (f703250)

Một đường thực thi chung cho mọi trang. Core: `Sources/DiskCleanerCore/TrashBatches.swift` (có SelfTest). App: `AppStore` + từng model.

**Luồng chuẩn trong View:**

```swift
let plan = model.trashPlan()                 // [TrashPlanItem]: path, name, bytes — sheet hiển thị đúng danh sách này
// TrashReviewSheet(items: plan.map { TrashReviewItem(name: $0.name, path: $0.path, size: human($0.bytes)) }, …)
// confirm:
Task { if let batch = await model.trash(using: store) { /* OperationResultView từ batch */ } }
```

- `model.trash(using: store)` có ở `CachesModel`, `BigFilesModel`, `OldFilesModel`, `DupModel`, `OrphansModel`; trả `nil` khi đang có lượt khác chạy hoặc kế hoạch rỗng; tự cập nhật model (bỏ chọn, gỡ hàng đã chuyển, đo lại). Gỡ ứng dụng: `UninstallModel.uninstall(using:)` (C4).
- Chạy ngoài main thread; `store.isTrashing == true` trong lúc chạy → View vô hiệu nút chuyển/hoàn tác.
- Mỗi mục được kiểm tra lại ngay trước khi chuyển (`preflight`): không còn / file đổi size-mtime so với lúc quét / bản giữ của file trùng mất hoặc đổi nội dung / vị trí bảo vệ / nằm trong thư mục đã chuyển cùng lô → **bỏ qua** (không tính lỗi).

**Kết quả (`TrashBatch`)** cho `OperationResultView`:

```swift
batch.moved / batch.skipped / batch.failed      // [TrashBatchEntry]: entry.item.name / .path / .bytes
batch.movedBytes                                  // đã chuyển vào Thùng rác (KHÔNG phải "đã giải phóng")
switch entry.outcome {                            // lý do hiển thị
case .skipped(let r):              L(r.reasonKey)
case .failed(let key, let detail): detail.isEmpty ? L(key) : LF("%@: %@", L(key), detail)
case .moved:                       break
}
```

**Lịch sử và hoàn tác** (lưu bền vững `~/Library/Application Support/CleanPilot/trash-batches.json`, quyền 0600, ghi atomic):

```swift
store.batches                              // [TrashBatch], mới nhất trước; còn sau khi mở lại app
store.canUndo(batchID:)                    // còn mục đã chuyển chưa khôi phục
await store.undo(batchID:) -> TrashBatch?  // entry.restore: .restored(at:) | .goneFromTrash | .changedInTrash | .refused | .failed
                                           // lý do: L(restore.reasonKey); .restored(at:) có thể là "tên (1)" — không ghi đè file mới
store.lastTrashAt                          // cho isStale
```

- Chỉ khôi phục từ thư mục Thùng rác, đúng inode đã chuyển, đích trong phạm vi cho phép — bản ghi lịch sử bị sửa không dùng để di chuyển file tùy ý được.
- `store.trashHistory`, `undoLast()`, `undoBatch()` giữ cho các trang chưa chuyển (Tổng quan, Folder Drill, Chẩn đoán, node_modules); `runTrash` cũng ghi vào `trashHistory`.

**Trạng thái quét (C2 + C5)** — mọi model quét tuân theo `ScanStatusReporting` (`Models/ScanStatus.swift`):

```swift
model.scanState      // .idle | .scanning | .completed | .stopped (người dùng dừng → kết quả chưa đầy đủ)
model.scannedAt      // Date? — thời điểm của kết quả đang hiển thị
model.issues         // [ScanIssue]: root + .noPermission | .notFound | .error(String)
model.isPartial      // stopped, hoặc completed nhưng có issues
model.isStale(lastTrashAt: store.lastTrashAt)   // có chuyển/khôi phục sau lần quét, hoặc quá 10 phút → hiện "Quét lại", không tự quét
```

- `issues` hiện có dữ liệu thật ở trang Cache; trang file lớn/cũ/trùng/còn sót trả `[]` cho tới khi bộ duyệt file báo được thư mục bị từ chối (việc tiếp theo của Claude).

**Chính sách chọn:** hàng chọn được khi `isReclaimableWhole(url)`; `selectAll` của mọi model chỉ lấy `isBulkSelectable(url)`; `trashPlan()` tự lọc lại.

**File trùng:** `DupModel.dates[path]` — ngày sửa từng bản; bản đầu mỗi nhóm là bản mới nhất, là bản được giữ.

**Thùng rác:** `scanStore.trash: TrashModel`

```swift
trash.summary                       // Summary(items:, bytes:)? — nil: chưa đo / không đọc được (bản sandbox)
trash.measuring; trash.refresh(); trash.openInFinder()
trash.canAskFinderToEmpty           // false ở bản sandbox → chỉ mở Finder
await trash.emptyInFinder() -> Bool // CHỈ gọi sau hộp xác nhận "không thể hoàn tác"; trash.emptying, trash.lastError
```

### C3 — Kế toán dung lượng trang Cache · P0 · Claude · `merged` (6014fb9)

Đã có trong `CachesModel` (+ hàm thuần trong Core, có SelfTest):

```swift
func rowState(_ id: UUID) -> CacheRowState      // .measuring | .measured(Int64) | .unmeasurable
func trash(using: AppStore) async -> TrashBatch?  // xem C1 + C2 (thay cho trashSelected())
var selectedBytes: Int64                          // đã loại trùng cha/con (có từ trước)
```

- Kế hoạch (`trashPlan()` / `trash(using:)`) chỉ chuyển đường dẫn ngoài cùng khi chọn cả cha lẫn con, ghi dung lượng đã đo của từng đường dẫn, rồi đo lại mọi hàng bị ảnh hưởng (kể cả hàng con không được chọn), nên không còn hàng kẹt ở "đang thống kê".
- Hàng không đọc được (thiếu quyền) giờ được giữ lại với `.unmeasurable`, không còn bị coi là trống rồi bị xoá khỏi danh sách.

**Việc của Codex trong `CachesView.swift`:** nối nút xác nhận theo luồng chuẩn ở C1 + C2 (`model.trash(using: store)`); ô dung lượng theo `model.rowState(item.id)` (`.unmeasurable` → "Không đo được (cần quyền truy cập)", không hiện 0 B).

### C4 — App đang chạy khi gỡ · P0/F05 · Claude · `merged` (f703250)

Quyết định của chủ dự án (05/11/2026): **đề nghị thoát app rồi gỡ tiếp; người dùng có thể từ chối.**

```swift
switch await uninstall.uninstall(using: store) {
case .done(let batch):   // OperationResultView(batch); bundle đã chuyển → app biến khỏi danh sách
case .appRunning:        // hỏi "<App> đang chạy. Thoát app rồi gỡ?"  [Thoát và gỡ] [Huỷ]
    switch await uninstall.requestQuit(app) {   // thoát bình thường như Cmd-Q, chờ tối đa 10 s, không force quit
    case .quit:     break  // gọi lại uninstall(using:)
    case .refused:  break  // "App từ chối thoát" — không gỡ
    case .timedOut: break  // "App chưa thoát (có thể đang hỏi lưu tài liệu)" — không gỡ
    }
case .busy:              // đang có lượt khác chạy
case .nothingToDo:       // chưa chọn app / đang lập kế hoạch / chính CleanPilot
}
uninstall.runState(of: app)   // .notRunning | .running(pids:) — nhãn "Đang chạy" trước khi bấm
uninstall.trashPlan()         // cho sheet xác nhận: bundle (critical) + dữ liệu đã chọn
```

- Bundle là mục `critical`: không chuyển được bundle thì không chuyển dữ liệu của app ("Không chuyển vì bản thân ứng dụng chưa được chuyển"). Không bao giờ gỡ chính CleanPilot.

### C5 — Vấn đề khi quét · Claude · `merged` (f703250) — gộp vào phần "Trạng thái quét" của C1 + C2

### C6 — Phiên quét tổng hợp · F01 · Claude · `later`

Phác thảo: `ScanSession` trong `ScanStore`, `modules: [ModuleState]` (waiting/scanning/done/cancelled/noPermission/partial/failed), `found/suggested/selected` bytes đã loại trùng. Chốt sau khi trả lời §9 câu 1.

### C7 — Dữ liệu treemap · F04 · Claude · `later`

Phác thảo: hàm thuần trong Core `squarifiedLayout(nodes: [(id, bytes)], in: CGRect) -> [(id, CGRect)]` có SelfTest; dữ liệu lấy từ `FolderDrillModel`. Codex vẽ bằng Canvas.

### Requests — yêu cầu từ UI

- ✅ **Đã có (P0/F03, File trùng)** — `duplicateContentCheck(kept:extra:) -> ContentMatch` (.same/.different/.cancelled) so **toàn bộ nội dung từng byte** mọi kích thước (bỏ giới hạn 64 MiB); `preflight` dùng nó. Huỷ: `AppStore.cancelTrash()` dừng lô giữa các mục và giữa lúc so file lớn — mục đã chuyển giữ nguyên trong batch, phần còn lại là `.skipped(.cancelled)` (reasonKey "Stopped before it was moved", đã có ở 9 bảng). UI: nút "Dừng" khi `store.isTrashing`, gọi `store.cancelTrash()`.

- **P2/F04, Folder Drill** — Đã dựng Canvas với hàng đã đo, dùng cùng selection/breadcrumb/danh sách; chờ C7 `merged` để thay bố cục chia ô tỷ lệ tạm bằng `squarifiedLayout`, giữ ID và số byte từ model. Cần metadata phần chưa liệt kê/không đọc được nếu muốn biểu diễn thành nhóm riêng, không tự cộng phần chưa đo vào diện tích có thể dọn.

- ✅ **Đã có (P1, ScanStatusReporting cho Tổng quan/Folder Drill/node_modules/Docker/Chẩn đoán)** — Cả 5 model có `scanState`/`scannedAt`/`issues` (+ `isPartial`, `isStale(lastTrashAt:)`). Tổng quan: issues từ `needFDA`/`needAdmin`, cả khi dừng. Folder Drill: trạng thái của **cấp đang xem** (cấp lấy từ cache giữ thời điểm đo cũ nên có thể stale); `DirLevel.rootErrno` ≠ 0 nghĩa là chính thư mục không đọc được (issue `.noPermission`/`.notFound`, không hiển thị là "trống"), `DirLevel.unreadableChildren` = thư mục con chỉ đo được một phần. node_modules/Docker/Chẩn đoán: `issues` luôn rỗng (Core không báo phần không đọc được), chỉ có vòng đời + thời điểm.
- **P1, công cụ dùng lịch sử cũ** — Cần `trashPlan`/executor/receipt theo lô cho Folder Drill, node_modules và Chẩn đoán (gồm trim), `FolderDrillModel.selectAll` và policy bulk-selectable cho NMModel; hiện UI chỉ chuẩn hóa hiển thị, giữ nguyên đường thao tác cũ theo phạm vi Giai đoạn B. Lịch sử cũ được tách riêng, không gán batch ID giả.

- ✅ **Đã có (P0, QA chuyển/hoàn tác)** — Bản dev (`swift run`/`DEV_HOOKS=1`) có `DISKWISE_HOME_SHIM`: `trashItem` thật chuyển vào `<home giả>/.Trash` (tên không ghi đè), khớp `trashRoots()`, nên luồng chuyển → `store.undo` chạy trọn trong cây tạm; Thùng rác thật không bị đụng. `devShimTrashDir()` cho biết đường dẫn (nil ở bản release). SelfTest "QA:" chạy trọn vòng không tiêm executor.
- ✅ **Đã có (P1, issues thật cho File lớn/cũ/trùng/còn sót)** — `walkFiles` trả `needFullDiskAccess` (EPERM), `needAdmin` (EACCES), `missingRoots`; `scanOrphansReport` trả `OrphanScan` có hai danh sách quyền (vị trí Library không đọc được + thư mục con của một mục còn sót; mục đó vẫn được liệt kê, dung lượng là cận dưới). Bốn model điền `issues` khi quét xong (`.noPermission` rồi `.notFound`). Phạm vi toàn ổ có thể ra nhiều dòng: UI nên hiện vài dòng đầu + tổng số.

Codex ghi yêu cầu API còn thiếu ở đây (một dòng mỗi yêu cầu: màn hình, dữ liệu/hành động cần, ưu tiên).

- ✅ **Đã có (C1 + C2, C4)** — Cache, File lớn, File lâu không sửa, File trùng, Dữ liệu còn sót, Gỡ ứng dụng: cần API model/store thực hiện kế hoạch đã xác nhận, chạy ngoài main thread, chặn thao tác lặp, kiểm tra lại file/bản giữ, cập nhật model và trả kết quả từng mục (đã chuyển/bỏ qua/thất bại); P0, trước khi nối nút chuyển vào Thùng rác. C0 hiện chỉ tách model, các thao tác cũ vẫn nằm trong View.
- ✅ **Đã có (C2 + C5)** — Các trang quét: cần trạng thái kết thúc phân biệt hoàn tất/đã dừng/lỗi/một phần cùng `scannedAt` và `issues` (C2/C5), giữ trong model khi đổi trang; P1. UI hiện không tự suy ra thời điểm quét hoặc tình trạng thiếu quyền.
- ✅ **Đã có (`ScanStore.trash`, `store.batches`/`undo`)** — Thùng rác: cần model đo nội dung, làm mới, trạng thái đang thực hiện và kết quả khôi phục từng mục; P1. Lịch sử theo lô/khả năng hoàn tác tiếp tục chờ C1 `merged`.
- ✅ **Đã có (`selectAll` dùng `isBulkSelectable`)** — File lớn, File lâu không sửa, File trùng, Dữ liệu còn sót: cần model công bố rõ policy bulk-selectable dùng chung với `isBulkSelectable`/`isReclaimableWhole`; P0. UI P1 chỉ gọi `model.selectAll`, không tự nới quy tắc chọn.
- ✅ **Đã có (`DupModel.dates`)** — File trùng: cần metadata ngày sửa từng bản từ model để hiển thị tiêu chí giữ bản mới nhất mà View không đọc filesystem; P1.
