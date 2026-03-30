#pragma once
// ================================================================
//  RelayController.h — HAL Layer: Actuators
//  Đóng gói toàn bộ logic điều khiển 4 relay thành một class.
//  Mọi chi tiết Active-HIGH/LOW được ẩn sau các method set*().
// ================================================================

#include <Arduino.h>
#include "config.h"  // PIN_HEATER, PIN_MIST, PIN_FAN, PIN_LIGHT, RELAY_SET

// ----------------------------------------------------------------
//  Struct giữ trạng thái hiện tại của 4 relay.
//  Được khai báo ở đây để main.cpp và các module khác cùng dùng
//  một kiểu dữ liệu duy nhất (Single Source of Truth).
// ----------------------------------------------------------------
struct RelayState {
    bool heater = false;  // true = BẬT sưởi
    bool mist   = false;  // true = BẬT phun sương
    bool fan    = false;  // true = BẬT quạt
    bool light  = false;  // true = BẬT đèn
};

// ----------------------------------------------------------------
//  Class RelayController
// ----------------------------------------------------------------
class RelayController {
public:
    // Khởi tạo 4 chân OUTPUT và đặt tất cả về trạng thái TẮT.
    // Tương đương setupPins() trong sketch gốc.
    void init();

    // Ghi trạng thái của một RelayState struct ra phần cứng cùng lúc.
    // Tương đương applyRelayStates() trong sketch gốc.
    // Gọi hàm này sau mỗi lần thay đổi state để đồng bộ GPIO.
    void applyAll(const RelayState& state);

    // --- Điều khiển từng relay riêng lẻ ---
    // Các method này chỉ ghi GPIO, KHÔNG cập nhật struct RelayState.
    // Dùng khi cần can thiệp khẩn cấp (ví dụ: executeFailSafe).
    void setHeater(bool on);
    void setMist(bool on);
    void setFan(bool on);
    void setLight(bool on);

    // Tắt khẩn cấp Heater và Mist — dùng trong Fail-Safe khi DHT22 lỗi.
    // Fan và Light không bị ảnh hưởng bởi lệnh này.
    void emergencyShutdownHeatMist();
};