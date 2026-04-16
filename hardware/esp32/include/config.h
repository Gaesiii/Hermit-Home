#pragma once
// ================================================================
//  config.h — Smart Terrarium · Tập trung toàn bộ cấu hình
//  Được trích xuất nguyên vẹn từ smart_terrarium.ino
//  KHÔNG chứa logic — chỉ là hằng số và macro.
// ================================================================

// ----------------------------------------------------------------
//  CHÂN CẢM BIẾN (Sensor Pins)
// ----------------------------------------------------------------
#define PIN_DHT22       4     // DHT22 — GPIO4 (1-Wire Digital)
#define LIGHT_SDA       20    // BH1750 I2C — SDA (GPIO20, không phải mặc định)
#define LIGHT_SCL       19    // BH1750 I2C — SCL (GPIO19, không phải mặc định)

// BOOT button (GPIO0): hold for 3 seconds to clear WiFi/user config.
#define BOOT_PIN        0

// ----------------------------------------------------------------
//  CHÂN RELAY (Actuator Pins)
//  Module relay của dự án này kích mức CAO (High-Level Trigger):
//    HIGH = BẬT thiết bị
//    LOW  = TẮT thiết bị
//  Nếu đổi sang module Active-LOW, chỉ cần swap HIGH/LOW ở đây.
// ----------------------------------------------------------------
#define PIN_HEATER      15    // IN1 — Thảm sưởi
#define PIN_MIST        16    // IN2 — Máy phun sương
#define PIN_LIGHT       17    // IN3 — Đèn chiếu sáng
#define PIN_FAN         18    // IN4 — Quạt thông gió

// Temporary lock for broken mist hardware.
// Set to false after replacing the mist module/sensor.
#define MIST_SAFETY_LOCK true

// Macro điều khiển relay — Active-HIGH
#define RELAY_ON(pin)         digitalWrite(pin, HIGH)
#define RELAY_OFF(pin)        digitalWrite(pin, LOW)
#define RELAY_SET(pin, state) ((state) ? RELAY_ON(pin) : RELAY_OFF(pin))

// Captive-portal AP SSID used when device has no saved WiFi credentials.
#define WIFI_AP_SSID    "Hermit Home"

// ----------------------------------------------------------------
//  CẤU HÌNH MQTT — HiveMQ Cloud (TLS port 8883)
// ----------------------------------------------------------------
#define MQTT_BROKER     "hermit-home-798c7baa.a01.euc1.aws.hivemq.cloud"
#define MQTT_PORT       8883
#define MQTT_USER       "admin"
#define MQTT_PASS       "Admin1!@"
#define MQTT_CLIENT_ID  "ESP32_Garden_Phuc_001"
// ----------------------------------------------------------------
//  KHOẢNG THỜI GIAN VÒNG LẶP (Intervals — milliseconds)
// ----------------------------------------------------------------
#define INTERVAL_SENSOR_MS      1000U   // Vòng lặp đọc cảm biến: 1 giây
#define INTERVAL_PUBLISH_MS    10000U   // Gửi telemetry lên MQTT:  10 giây
#define INTERVAL_RECONNECT_MS   5000U   // Thử kết nối lại MQTT:    5 giây

// ----------------------------------------------------------------
//  NGƯỠNG HYSTERESIS MẶC ĐỊNH (Default Threshold Defaults)
//  Các giá trị này chỉ dùng khi Flash chưa có dữ liệu.
//  Sau khi nhận lệnh từ MQTT, chúng sẽ được ghi đè vào Flash.
// ----------------------------------------------------------------
#define DEFAULT_TEMP_MIN    24.0f   // °C — bật sưởi dưới ngưỡng này
#define DEFAULT_TEMP_MAX    29.0f   // °C — tắt sưởi trên ngưỡng này
#define DEFAULT_HUM_MIN     70.0f   // %  — bật sương dưới ngưỡng này
#define DEFAULT_HUM_MAX     85.0f   // %  — tắt sương trên ngưỡng này
#define DEFAULT_LUX_MIN    200.0f   // lux — bật đèn dưới ngưỡng này
#define DEFAULT_LUX_MAX    500.0f   // lux — tắt đèn trên ngưỡng này
