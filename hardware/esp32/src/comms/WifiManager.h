/**
 * ================================================================
 * @file    WifiManager.h
 * @brief   WiFi connection management for the Smart Terrarium.
 * ================================================================
 */

#pragma once

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>

class WifiManager {
public:
    WifiManager();

    // Initialise WiFi flow:
    // - load saved SSID/password/user_id from NVS
    // - connect in STA mode if present
    // - otherwise start captive portal AP for phone-based setup
    bool init();

    // Pump captive portal and BOOT-button reset logic.
    void loop();

    // Non-blocking connection check.
    bool isConnected() const;

    // user_id configured from captive portal and stored in NVS.
    const String& getUserId() const;

private:
    void _loadCredentials();
    void _saveCredentials(const String& ssid,
                          const String& password,
                          const String& userId);
    bool _connectToWiFi(const String& ssid, const String& password);
    void _startApPortal();
    void _stopApPortal();
    void _configurePortalRoutes();
    void _checkBootReset();
    void _clearCredentials();

    // Web handlers
    void _handleRoot();
    void _handleConnect();
    void _handleNotFound();

private:
    Preferences _prefs;
    WebServer   _server;
    DNSServer   _dnsServer;

    bool _portalRoutesConfigured;
    bool _apModeActive;

    String _ssid;
    String _password;
    String _userId;

    uint32_t _bootPressStartMs;
};
