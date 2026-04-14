// ================================================================
//  RelayController.cpp — Hiện thực HAL Layer: Actuators
//  Logic RELAY_SET được giữ nguyên 100% từ sketch gốc.
//  Relay module kích mức CAO (Active-HIGH):
//    HIGH = BẬT  |  LOW = TẮT
// ================================================================

#include "RelayController.h"

// ----------------------------------------------------------------
//  init()
//  Gốc: setupPins() trong sketch
//  Cấu hình 4 chân relay là OUTPUT và khởi tạo tất cả ở mức TẮT.
//  Gọi một lần duy nhất trong setup().
// ----------------------------------------------------------------
void RelayController::init() {
    // Cấu hình hướng chân
    pinMode(PIN_HEATER, OUTPUT);
    pinMode(PIN_MIST,   OUTPUT);
    pinMode(PIN_FAN,    OUTPUT);
    pinMode(PIN_LIGHT,  OUTPUT);

    // Đặt tất cả relay về trạng thái TẮT an toàn khi khởi động
    RELAY_OFF(PIN_HEATER);
    RELAY_OFF(PIN_MIST);
    RELAY_OFF(PIN_FAN);
    RELAY_OFF(PIN_LIGHT);

    Serial.println(F("[RELAY] Khởi tạo 4 relay thành công — tất cả đang TẮT."));
}

// ----------------------------------------------------------------
//  applyAll()
//  Gốc: applyRelayStates() trong sketch
//  Nhận một RelayState và đồng bộ toàn bộ 4 GPIO cùng lúc.
//  Đây là điểm ghi hardware duy nhất trong luồng tự động.
// ----------------------------------------------------------------
void RelayController::applyAll(const RelayState& state) {
    RELAY_SET(PIN_HEATER, state.heater);
#if MIST_SAFETY_LOCK
    RELAY_SET(PIN_MIST,   false);
#else
    RELAY_SET(PIN_MIST,   state.mist);
#endif
    RELAY_SET(PIN_FAN,    state.fan);
    RELAY_SET(PIN_LIGHT,  state.light);
}

// ----------------------------------------------------------------
//  setHeater() / setMist() / setFan() / setLight()
//  Điều khiển từng relay riêng lẻ, trực tiếp ra GPIO.
//  Dùng cho Manual Override hoặc các trường hợp khẩn cấp.
// ----------------------------------------------------------------
void RelayController::setHeater(bool on) {
    RELAY_SET(PIN_HEATER, on);
}

void RelayController::setMist(bool on) {
#if MIST_SAFETY_LOCK
    RELAY_SET(PIN_MIST, false);
#else
    RELAY_SET(PIN_MIST, on);
#endif
}

void RelayController::setFan(bool on) {
    RELAY_SET(PIN_FAN, on);
}

void RelayController::setLight(bool on) {
    RELAY_SET(PIN_LIGHT, on);
}

// ----------------------------------------------------------------
//  emergencyShutdownHeatMist()
//  Ngắt ngay Heater và Mist khi cảm biến DHT22 lỗi (NaN).
//  Fan và Light KHÔNG bị tắt — hành vi này giữ nguyên từ sketch gốc
//  (loopSensor() return sớm không gọi applyRelayStates nên fan/light
//  giữ nguyên trạng thái cuối cùng trước khi fault xảy ra).
// ----------------------------------------------------------------
void RelayController::emergencyShutdownHeatMist() {
    RELAY_OFF(PIN_HEATER);
    RELAY_OFF(PIN_MIST);
    Serial.println(F("[RELAY] FAIL-SAFE: Heater & Mist đã bị ngắt khẩn cấp!"));
}
