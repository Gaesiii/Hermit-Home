/**
 * ================================================================
 * @file    WifiManager.cpp
 * @brief   Implementation of WifiManager.
 * ================================================================
 */

#include "WifiManager.h"
#include "config.h"   // WIFI_SSID, WIFI_PASSWORD

// ----------------------------------------------------------------
// Public: init
// ----------------------------------------------------------------
bool WifiManager::init() {
    Serial.printf("[WiFi] Connecting to SSID: %s\n", WIFI_SSID);

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    // Block for up to 15 s — mirrors the original setupWifi() exactly.
    // This is the only intentional blocking call in the codebase and
    // is acceptable because it only runs once during setup().
    const uint32_t kTimeoutMs = 15000UL;
    uint32_t start = millis();

    while (WiFi.status() != WL_CONNECTED && (millis() - start) < kTimeoutMs) {
        delay(500);
        Serial.print('.');
    }
    Serial.println(); // newline after the progress dots

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("[WiFi] Connected — IP: %s\n",
                      WiFi.localIP().toString().c_str());
        return true;
    }

    Serial.println(F("[WiFi] Connection timed out. Will retry via MQTT loop."));
    return false;
}

// ----------------------------------------------------------------
// Public: isConnected
// ----------------------------------------------------------------
bool WifiManager::isConnected() const {
    return (WiFi.status() == WL_CONNECTED);
}