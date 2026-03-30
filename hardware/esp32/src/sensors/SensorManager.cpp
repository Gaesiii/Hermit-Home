// ================================================================
//  SensorManager.cpp — Hiện thực HAL Layer: Sensors
//  Toàn bộ logic đọc cảm biến giữ nguyên 100% từ sketch gốc.
//  Thứ tự đọc, kiểm tra isnan(), clamp lux về 0 — tất cả không đổi.
// ================================================================

#include "SensorManager.h"

// ----------------------------------------------------------------
//  init()
//  Gốc: đoạn Wire.begin() / lightMeter.begin() / dht.begin()
//       trong setup() của sketch
//
//  Lưu ý quan trọng:
//    Wire.begin(SDA, SCL) — dùng chân LIGHT_SDA=20, LIGHT_SCL=19
//    thay vì chân I2C mặc định của ESP32 (SDA=21, SCL=22).
//    Giá trị này lấy từ config.h, không hardcode ở đây.
// ----------------------------------------------------------------
void SensorManager::init() {
    // Khởi tạo I2C với chân tùy chỉnh từ sketch gốc
    Wire.begin(LIGHT_SDA, LIGHT_SCL);

    // Khởi tạo BH1750 ở chế độ đọc liên tục độ phân giải cao
    if (!_lightMeter.begin(BH1750::CONTINUOUS_HIGH_RES_MODE)) {
        Serial.println(F("[SENSOR] WARN: Không tìm thấy BH1750 — kiểm tra kết nối I2C!"));
        // Không crash — tiếp tục chạy, getLux() sẽ trả về 0
    } else {
        Serial.println(F("[SENSOR] BH1750 khởi tạo OK."));
    }

    // Khởi tạo DHT22
    _dht.begin();
    Serial.println(F("[SENSOR] DHT22 khởi tạo OK."));
}

// ----------------------------------------------------------------
//  readAll()
//  Gốc: phần đầu của loopSensor() trong sketch
//
//  Luồng xử lý giữ nguyên hoàn toàn:
//    1. Đọc DHT22 (temperature + humidity)
//    2. Đọc BH1750 (lux)
//    3. Kiểm tra isnan() → set _sensorFault
//    4. Nếu không lỗi: clamp lux về 0 nếu âm, in log
//
//  Caller (main.cpp / loopSensor) phải kiểm tra isSensorFault()
//  SAU KHI gọi readAll() và xử lý tương ứng (return sớm / fail-safe).
// ----------------------------------------------------------------
void SensorManager::readAll() {
    // Đọc DHT22 — hàm này của Adafruit mất ~250ms (blocking ngắn, chấp nhận được)
    _temperature = _dht.readTemperature();
    _humidity    = _dht.readHumidity();

    // Đọc BH1750 — non-blocking, trả về giá trị cache từ lần đo trước
    _lux = _lightMeter.readLightLevel();

    // ----------------------------------------------------------------
    //  Kiểm tra lỗi DHT22 — giữ nguyên logic isnan() từ sketch gốc
    //  BH1750 lỗi KHÔNG được coi là sensor fault (chỉ clamp về 0).
    // ----------------------------------------------------------------
    if (isnan(_temperature) || isnan(_humidity)) {
        _sensorFault = true;
        // Không in thêm log ở đây — caller chịu trách nhiệm log & xử lý
        return;  // Dừng sớm — _lux có thể không hợp lệ nhưng không quan trọng
    }

    // DHT22 OK — xóa cờ lỗi
    _sensorFault = false;

    // BH1750 trả về -1 khi chưa sẵn sàng — clamp về 0 (giữ nguyên từ sketch)
    if (_lux < 0.0f) _lux = 0.0f;

    // Log dữ liệu cảm biến — giống hệt format trong sketch gốc
    Serial.printf("[SENSOR] T=%.1f°C  H=%.1f%%  Lux=%.0f\n",
                  _temperature, _humidity, _lux);
}