#pragma once
// ================================================================
//  SensorManager.h — HAL Layer: Sensors
//  Đóng gói DHT22 (nhiệt/ẩm) và BH1750 (ánh sáng) vào một class.
//  Cung cấp interface đọc dữ liệu sạch với fault detection tích hợp.
// ================================================================

#include <Arduino.h>
#include <Wire.h>
#include <DHT.h>
#include <BH1750.h>
#include "config.h"  // PIN_DHT22, LIGHT_SDA, LIGHT_SCL

class SensorManager {
public:
    // Khởi tạo Wire (I2C với chân tùy chỉnh), BH1750, và DHT22.
    // Tương đương đoạn Wire.begin() + lightMeter.begin() + dht.begin()
    // trong setup() của sketch gốc.
    void init();

    // Đọc toàn bộ cảm biến và cập nhật giá trị nội bộ.
    // Tương đương phần đọc sensor trong loopSensor() của sketch gốc.
    // Tự động cập nhật trạng thái lỗi (_sensorFault).
    void readAll();

    // ----------------------------------------------------------------
    //  Getters — truy xuất dữ liệu đã đọc
    // ----------------------------------------------------------------

    // Trả về true nếu DHT22 trả về NaN ở lần readAll() gần nhất.
    // Khi true, giá trị temperature/humidity KHÔNG đáng tin cậy.
    bool  isSensorFault() const { return _sensorFault; }

    // Nhiệt độ (°C) — có thể là NAN nếu isSensorFault() == true.
    float getTemperature() const { return _temperature; }

    // Độ ẩm tương đối (%) — có thể là NAN nếu isSensorFault() == true.
    float getHumidity()    const { return _humidity; }

    // Độ rọi ánh sáng (lux) — luôn >= 0, trả về 0.0 khi BH1750 lỗi.
    float getLux()         const { return _lux; }

private:
    DHT    _dht{PIN_DHT22, DHT22};  // Đối tượng DHT22, chân từ config.h
    BH1750 _lightMeter;              // Đối tượng BH1750 (I2C)

    // Dữ liệu nội bộ — chỉ cập nhật qua readAll()
    float _temperature = NAN;
    float _humidity    = NAN;
    float _lux         = 0.0f;
    bool  _sensorFault = false;     // true = DHT22 đang lỗi
};