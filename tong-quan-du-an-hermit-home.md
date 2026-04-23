# Tổng Quan Dự Án Hermit Home

**Phiên bản tài liệu:** 1.0  
**Ngày cập nhật:** 15/04/2026  
**Mục đích:** Tài liệu mô tả tổng quan dự án để dùng trong báo cáo/đồ án và chuyển đổi sang Word.

## 1. Giới thiệu dự án

Hermit Home là hệ thống IoT giám sát và điều khiển môi trường sống cho bể nuôi cua ẩn sĩ (hermit crab).  
Dự án áp dụng kiến trúc nhiều lớp (edge + cloud + mobile), kết hợp:

- Thiết bị biên ESP32 để đọc cảm biến và điều khiển relay theo thời gian thực.
- Giao tiếp MQTT để truyền telemetry và nhận lệnh điều khiển.
- API serverless để cung cấp cổng truy cập cho ứng dụng người dùng và tác vụ tự động.
- AI Agent hỗ trợ tự động điều chỉnh ngưỡng môi trường.
- Ứng dụng Flutter cho xác thực người dùng và kiểm thử/điều khiển thiết bị.

## 2. Mục tiêu chính

- Theo dõi liên tục các chỉ số nhiệt độ, độ ẩm, ánh sáng trong terrarium.
- Điều khiển các thiết bị chấp hành gồm `heater`, `mist`, `fan`, `light`.
- Cho phép người dùng can thiệp thủ công (manual override) khi cần.
- Vận hành tự động theo ngưỡng hysteresis khi không có lệnh thủ công.
- Lưu lịch sử telemetry và điều khiển để truy vết.
- Tăng mức an toàn vận hành với cơ chế khóa thiết bị phun sương khi phần cứng chưa ổn định.

## 3. Mô hình điều khiển ưu tiên

Hệ thống sử dụng cơ chế ưu tiên theo tầng:

1. **User Override (Ưu tiên cao nhất):** Lệnh người dùng từ app/API được áp dụng trực tiếp.
2. **AI/Threshold Update:** AI Agent gửi ngưỡng mới để thiết bị tự điều khiển.
3. **Local Hysteresis (Fallback):** ESP32 tự vận hành theo ngưỡng lưu cục bộ khi không có override.

Cơ chế này giúp hệ thống vừa linh hoạt cho người dùng, vừa duy trì tính tự chủ khi mạng không ổn định.

## 4. Kiến trúc tổng thể

```text
[Flutter Mobile App]
        |
        | HTTPS (JWT / X-API-Key)
        v
[Vercel Serverless API] -----> [MongoDB]
        |                           |
        | MQTT Command Publish      | Telemetry Storage
        v                           ^
      [HiveMQ Broker] <----- [MQTT Worker - Node.js]
        ^
        | MQTT Telemetry/Confirm
        |
      [ESP32 Edge Controller]
```

## 5. Thành phần hệ thống

### 5.1. Edge Controller (ESP32)

- Đọc cảm biến DHT22 (nhiệt độ, độ ẩm) và BH1750 (ánh sáng).
- Vòng lặp cảm biến mỗi `1 giây`, gửi telemetry mỗi `10 giây`.
- Điều khiển relay cho `heater`, `mist`, `fan`, `light`.
- Tự động fallback an toàn khi lỗi cảm biến (`sensor_fault`) và ngắt kết nối MQTT.
- Có captive portal để cấu hình WiFi và `user_id/device_id`.
- Đang bật khóa an toàn `mist` (luôn OFF) để tránh rủi ro phần cứng.

### 5.2. MQTT Worker (Node.js/TypeScript)

- Subscribe các topic telemetry/confirm từ broker.
- Kiểm tra chặt chẽ định dạng `deviceId` (ObjectId), schema payload và biên giá trị.
- Ghi telemetry hợp lệ vào MongoDB (`telemetry` collection).
- Ghi log ack điều khiển và trạng thái offline từ LWT.
- Cung cấp endpoint `/ping` và cơ chế self-keepalive cho môi trường Render.

### 5.3. REST API Serverless (Vercel)

- Cung cấp endpoint cho đăng ký/đăng nhập và thao tác thiết bị.
- Hỗ trợ 2 lớp xác thực:
  - `Authorization: Bearer <token>` (JWT nội bộ, có thể mở rộng Firebase).
  - `X-API-Key` cho service-to-service (AI Agent).
- Áp dụng kiểm tra ownership (`userId` phải khớp `deviceId`) trước khi đọc/ghi dữ liệu.
- Publish lệnh điều khiển qua MQTT tới `terrarium/commands/{deviceId}`.
- Lưu lịch sử điều khiển vào `device_states`.
- Bật CORS cho nhóm endpoint API.

### 5.4. AI Agent (Python)

- Chạy định kỳ mỗi `60 giây`.
- Gọi API `/api/devices/{deviceId}/status` để lấy trạng thái mới nhất.
- Logic hiện tại tập trung vào độ ẩm:
  - Độ ẩm thấp: đề xuất tăng ngưỡng.
  - Độ ẩm cao: đề xuất hạ ngưỡng.
- Gửi cập nhật ngưỡng qua endpoint override (chế độ `user_override = false`).

### 5.5. Mobile App (Flutter)

- Có flow đăng ký/đăng nhập, lưu token bằng secure storage.
- Có màn hình kiểm thử API tổng hợp (User + Device API Test).
- Hỗ trợ gọi trực tiếp các endpoint thiết bị: status, control, override, telemetry, schedules.

## 6. Luồng dữ liệu vận hành (Sense - Think - Act)

1. ESP32 đọc cảm biến và phát telemetry lên topic `terrarium/telemetry/{deviceId}`.
2. MQTT Worker nhận message, kiểm tra schema, rồi lưu vào MongoDB.
3. API đọc dữ liệu từ MongoDB để trả về cho mobile app hoặc AI Agent.
4. Người dùng hoặc AI Agent gửi lệnh điều khiển/cập nhật ngưỡng qua API.
5. API publish command lên `terrarium/commands/{deviceId}`.
6. ESP32 nhận lệnh, áp dụng relay/ngưỡng và gửi ack qua `terrarium/confirm/{deviceId}`.

## 7. Công nghệ sử dụng

| Nhóm | Công nghệ |
|---|---|
| Firmware | C++ (PlatformIO), ESP32, Arduino framework |
| Giao tiếp thiết bị | MQTT over TLS (HiveMQ Cloud) |
| Backend API | Node.js + TypeScript + Vercel Serverless |
| Worker nền | Node.js + TypeScript |
| AI Service | Python (`requests`, `schedule`, `python-dotenv`) |
| Mobile | Flutter (Dart) |
| Cơ sở dữ liệu | MongoDB |
| Monorepo | NPM Workspaces + Turbo |

## 8. Mô hình dữ liệu chính

- `users`: thông tin tài khoản (email, password hash, thời gian tạo/cập nhật).
- `devices`: trạng thái tổng hợp của thiết bị (mode, relay, timestamps).
- `telemetry`: dữ liệu cảm biến theo thời gian và trạng thái relay.
- `device_states`: lịch sử các lệnh/trạng thái điều khiển theo nguồn (`user`, `ai`, `local`).

## 9. API tiêu biểu

- `POST /api/users/register`
- `POST /api/users/login`
- `GET /api/devices/{deviceId}`
- `PATCH /api/devices/{deviceId}`
- `GET /api/devices/{deviceId}/status`
- `GET /api/devices/{deviceId}/telemetry`
- `GET /api/devices/{deviceId}/control`
- `POST /api/devices/{deviceId}/control`
- `POST /api/devices/{deviceId}/override`

## 10. Điểm mạnh hiện tại

- Kiến trúc tách lớp rõ ràng, dễ mở rộng từng service độc lập.
- Có cơ chế ưu tiên điều khiển phù hợp bài toán IoT thực tế.
- Có các lớp kiểm tra dữ liệu đầu vào giúp giảm lỗi/khai thác injection.
- Có cơ chế an toàn vật lý cho relay phun sương trong giai đoạn phần cứng chưa ổn định.
- Có sẵn mobile test tool giúp QA API nhanh.

## 11. Hạn chế và hướng phát triển

- Một số endpoint vẫn ở trạng thái placeholder (`/devices`, `/schedules`, `/auth`).
- Tài liệu kiến trúc trong thư mục `docs/` chưa được điền đầy đủ.
- Cần bổ sung dashboard mobile hoàn chỉnh cho người dùng cuối.
- Nên tăng test tự động end-to-end cho luồng API -> MQTT -> ESP32 -> Confirm.
- Nên chuẩn hóa CI/CD và quản lý secrets tập trung hơn cho production.

## 12. Kết luận

Hermit Home đã có nền tảng kỹ thuật tốt cho một hệ thống IoT thông minh: thu thập dữ liệu tại edge, xử lý cloud, điều khiển thời gian thực và hỗ trợ tự động hóa. Với việc hoàn thiện thêm phần tài liệu, endpoint còn thiếu và giao diện người dùng cuối, dự án có thể tiến tới triển khai ổn định ở môi trường thực tế.
