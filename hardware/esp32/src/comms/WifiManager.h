/**
 * ================================================================
 * @file    WifiManager.h
 * @brief   WiFi connection management for the Smart Terrarium.
 *
 * Wraps the ESP32 WiFi stack into a clean interface.
 * init() performs a blocking connect with a 15-second timeout —
 * acceptable at boot time; all subsequent status checks via
 * isConnected() are non-blocking.
 * ================================================================
 */

#pragma once

#include <WiFi.h>

class WifiManager {
public:
    /**
     * @brief Initialise WiFi in STA mode and attempt to connect.
     *
     * Reads WIFI_SSID and WIFI_PASSWORD from config.h (must be
     * defined before this header is included via main.cpp).
     * Blocks for up to 15 s waiting for an IP address, then
     * returns whether the connection succeeded.
     *
     * @return true  — connected and IP assigned.
     * @return false — timed out; the sketch will retry via MQTT
     *                 reconnect logic which guards on isConnected().
     */
    bool init();

    /**
     * @brief Non-blocking connection check.
     * @return true if WiFi.status() == WL_CONNECTED.
     */
    bool isConnected() const;
};