# CleanPilot — bản giao diện đơn giản

CleanPilot là dự án cá nhân của huynhtrungthoai (bundle ID `com.huynhtrungthoai.cleanpilot`). Ghi công mã nguồn gốc theo giấy phép Apache-2.0: xem `NOTICE`.

## Sử dụng

1. Mở `build_app/CleanPilot.app`.
2. Ở **Quét thông minh**, chọn **Quét ngay**. Bước này chỉ đọc các vị trí cache đã biết, không tự dọn file.
3. Chọn **Xem kết quả**, đọc nhãn ảnh hưởng của từng mục.
4. **Chọn mục đề xuất** chỉ chọn những mục được cơ sở dữ liệu hiện có đánh giá là dọn không ảnh hưởng. Những mục cần tải lại hoặc có thể mất dữ liệu cần tự chọn riêng.
5. Chọn **Chuyển vào Thùng rác** và xác nhận. Dùng **Hoàn tác** hoặc trang **Thùng rác** để khôi phục khi file vẫn còn trong Thùng rác.

File chỉ được chuyển vào Thùng rác; dung lượng thực sự được giải phóng khi dọn sạch Thùng rác qua Finder. Bước dọn sạch không thể hoàn tác.

**Dung lượng ổ đĩa**, **File dung lượng lớn**, **File trùng lặp**, **Gỡ ứng dụng** có lối vào riêng. Các công cụ dành cho lập trình viên và chẩn đoán nằm trong **Công cụ nâng cao**. Cài đặt và đổi giao diện ở cuối thanh bên.

Luồng chính được Việt hóa. Một số tên cache, giải thích chi tiết và công cụ nâng cao vẫn dùng tiếng Anh. Đổi ngôn ngữ trong mục Giao diện.

## Build lại

```sh
SIGN_IDENTITY=none ARCH=arm64 bash build_app/build.sh
```

Script kiểm tra chuỗi dịch, build release, chạy toàn bộ SelfTest, đóng gói tài nguyên và xác minh chữ ký trước khi tạo `dist/CleanPilot-1.0.dmg`. Bản build cục bộ dùng chữ ký ad-hoc.

Thay đổi nằm ở giao diện và điều hướng. Giữ các quy tắc bảo vệ đường dẫn, không xóa vĩnh viễn trong ứng dụng, Docker chỉ xem, và hệ thống hoàn tác của dự án gốc.
