/**
 * ================================================================
 * @file    WifiManager.cpp
 * @brief   Implementation of WifiManager.
 * ================================================================
 */

#include "WifiManager.h"
#include "config.h"

namespace {
constexpr char kPrefsNs[]          = "wifi";
constexpr char kKeySsid[]          = "wifi_ssid";
constexpr char kKeyPassword[]      = "wifi_pass";
constexpr char kKeyUserId[]        = "user_id";
constexpr uint32_t kConnectTimeout = 20000UL;
constexpr uint32_t kBootHoldMs     = 3000UL;
const IPAddress kApIp(192, 168, 4, 1);
const IPAddress kApMask(255, 255, 255, 0);

const char kPortalHtml[] PROGMEM = R"html(
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Hermit Home - WiFi Setup</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: Arial, sans-serif;
      background: linear-gradient(130deg, #1b5870, #175870 40%, #44a08d);
      color: #142022;
      padding: 20px;
    }
    .card {
      width: 100%;
      max-width: 420px;
      background: #fff;
      border-radius: 18px;
      padding: 28px;
      box-shadow: 0 18px 40px rgba(0, 0, 0, 0.18);
    }
    h1 { margin: 0 0 8px; font-size: 24px; color: #123a44; }
    p  { margin: 0 0 20px; color: #4f6468; font-size: 14px; line-height: 1.4; }
    label { display: block; margin: 14px 0 6px; font-weight: 600; color: #1f3e45; }
    input {
      width: 100%;
      border: 1px solid #c9d6d9;
      border-radius: 10px;
      padding: 12px;
      font-size: 16px;
    }
    button {
      width: 100%;
      margin-top: 18px;
      border: 0;
      border-radius: 10px;
      padding: 13px;
      font-size: 16px;
      font-weight: 700;
      color: #fff;
      background: #1d7a86;
      cursor: pointer;
    }
    .hint {
      margin-top: 14px;
      font-size: 13px;
      color: #516366;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>Hermit Home</h1>
    <p>Cau hinh WiFi va userID cho ESP32.</p>
    <form action="/connect" method="post">
      <label for="ssid">WiFi SSID</label>
      <input id="ssid" name="ssid" placeholder="Ten WiFi" required>

      <label for="pass">WiFi Password</label>
      <input id="pass" name="pass" type="password" placeholder="Mat khau" required>

      <label for="user_id">userID</label>
      <input id="user_id" name="user_id" placeholder="VD: 67c6fd..." required>

      <button type="submit">Luu va Ket Noi</button>
    </form>
    <div class="hint">Mist dang bi khoa an toan (luon OFF).</div>
  </div>
</body>
</html>
)html";

const char kSuccessHtml[] PROGMEM = R"html(
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Connected</title>
  <style>
    body { font-family: Arial, sans-serif; background:#e8fff3; margin:0; min-height:100vh; display:grid; place-items:center; }
    .box { background:#fff; border-radius:14px; padding:24px; max-width:420px; width:92%; box-shadow:0 12px 26px rgba(0,0,0,0.12); text-align:center; }
    h1 { color:#1e7b4f; margin:0 0 8px; } p { color:#2b4b36; margin:0; }
  </style>
</head>
<body>
  <div class="box">
    <h1>Ket noi thanh cong</h1>
    <p>ESP da luu WiFi va userID. AP setup se tu tat.</p>
  </div>
</body>
</html>
)html";

const char kFailedHtml[] PROGMEM = R"html(
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Failed</title>
  <style>
    body { font-family: Arial, sans-serif; background:#ffecec; margin:0; min-height:100vh; display:grid; place-items:center; }
    .box { background:#fff; border-radius:14px; padding:24px; max-width:420px; width:92%; box-shadow:0 12px 26px rgba(0,0,0,0.12); text-align:center; }
    h1 { color:#c63434; margin:0 0 8px; } p { color:#5c2323; margin:0 0 12px; }
    a { color:#0057b8; text-decoration:none; }
  </style>
</head>
<body>
  <div class="box">
    <h1>Ket noi that bai</h1>
    <p>Kiem tra lai SSID, password hoac userID.</p>
    <a href="/">Nhap lai</a>
  </div>
</body>
</html>
)html";
}  // namespace

WifiManager::WifiManager()
    : _server(80),
      _portalRoutesConfigured(false),
      _apModeActive(false),
      _bootPressStartMs(0) {}

bool WifiManager::init() {
    pinMode(BOOT_PIN, INPUT_PULLUP);

    _prefs.begin(kPrefsNs, false);
    _loadCredentials();

    WiFi.setAutoReconnect(true);

    if (!_ssid.isEmpty() && !_userId.isEmpty()) {
        Serial.printf("[WiFi] Found saved WiFi (%s), trying to connect...\n",
                      _ssid.c_str());

        if (_connectToWiFi(_ssid, _password)) {
            Serial.printf("[WiFi] Connected. IP: %s\n",
                          WiFi.localIP().toString().c_str());
            Serial.printf("[WiFi] Active userID: %s\n", _userId.c_str());
            return true;
        }

        Serial.println(F("[WiFi] Saved credentials failed. Starting AP portal."));
    } else {
        Serial.println(F("[WiFi] No saved WiFi/userID. Starting AP portal."));
    }

    _startApPortal();
    return false;
}

void WifiManager::loop() {
    if (_apModeActive) {
        _dnsServer.processNextRequest();
        _server.handleClient();
    }

    _checkBootReset();
}

bool WifiManager::isConnected() const {
    return WiFi.status() == WL_CONNECTED;
}

const String& WifiManager::getUserId() const {
    return _userId;
}

void WifiManager::_loadCredentials() {
    _ssid     = _prefs.getString(kKeySsid, "");
    _password = _prefs.getString(kKeyPassword, "");
    _userId   = _prefs.getString(kKeyUserId, "");
}

void WifiManager::_saveCredentials(const String& ssid,
                                   const String& password,
                                   const String& userId) {
    _prefs.putString(kKeySsid, ssid);
    _prefs.putString(kKeyPassword, password);
    _prefs.putString(kKeyUserId, userId);

    _ssid     = ssid;
    _password = password;
    _userId   = userId;
}

bool WifiManager::_connectToWiFi(const String& ssid, const String& password) {
    if (ssid.isEmpty()) return false;

    if (_apModeActive) {
        WiFi.mode(WIFI_AP_STA);
    } else {
        WiFi.mode(WIFI_STA);
    }

    WiFi.begin(ssid.c_str(), password.c_str());

    uint32_t startMs = millis();
    while (WiFi.status() != WL_CONNECTED &&
           (millis() - startMs) < kConnectTimeout) {
        delay(500);
        Serial.print('.');
    }
    Serial.println();

    return WiFi.status() == WL_CONNECTED;
}

void WifiManager::_startApPortal() {
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(WIFI_AP_SSID);
    WiFi.softAPConfig(kApIp, kApIp, kApMask);

    _configurePortalRoutes();
    _dnsServer.start(53, "*", kApIp);
    _server.begin();
    _apModeActive = true;

    Serial.printf("[WiFi] AP portal started: %s\n", WIFI_AP_SSID);
    Serial.printf("[WiFi] AP IP: %s\n", WiFi.softAPIP().toString().c_str());
}

void WifiManager::_stopApPortal() {
    _apModeActive = false;
    WiFi.softAPdisconnect(true);
}

void WifiManager::_configurePortalRoutes() {
    if (_portalRoutesConfigured) return;

    _server.on("/", HTTP_GET, [this]() { _handleRoot(); });
    _server.on("/connect", HTTP_POST, [this]() { _handleConnect(); });
    _server.onNotFound([this]() { _handleNotFound(); });

    _portalRoutesConfigured = true;
}

void WifiManager::_checkBootReset() {
    if (digitalRead(BOOT_PIN) == LOW) {
        if (_bootPressStartMs == 0) {
            _bootPressStartMs = millis();
        } else if ((millis() - _bootPressStartMs) >= kBootHoldMs) {
            Serial.println(F("[WiFi] BOOT held for 3s. Clearing WiFi/user config."));
            _clearCredentials();
            WiFi.disconnect(true, true);
            delay(300);
            ESP.restart();
        }
        return;
    }

    _bootPressStartMs = 0;
}

void WifiManager::_clearCredentials() {
    _prefs.remove(kKeySsid);
    _prefs.remove(kKeyPassword);
    _prefs.remove(kKeyUserId);
    _ssid = "";
    _password = "";
    _userId = "";
}

void WifiManager::_handleRoot() {
    _server.send_P(200, "text/html", kPortalHtml);
}

void WifiManager::_handleConnect() {
    String ssid = _server.arg("ssid");
    String pass = _server.arg("pass");
    String userId = _server.arg("user_id");

    ssid.trim();
    userId.trim();

    if (ssid.isEmpty() || userId.isEmpty()) {
        _server.send_P(400, "text/html", kFailedHtml);
        return;
    }

    Serial.printf("[WiFi] Portal connect request: ssid=%s, userID=%s\n",
                  ssid.c_str(), userId.c_str());

    if (_connectToWiFi(ssid, pass)) {
        _saveCredentials(ssid, pass, userId);

        Serial.printf("[WiFi] Connected from portal. IP: %s\n",
                      WiFi.localIP().toString().c_str());
        Serial.printf("[WiFi] Active userID: %s\n", _userId.c_str());

        _server.send_P(200, "text/html", kSuccessHtml);

        delay(1200);
        _stopApPortal();
        WiFi.mode(WIFI_STA);
        return;
    }

    WiFi.disconnect();
    _server.send_P(200, "text/html", kFailedHtml);
}

void WifiManager::_handleNotFound() {
    _server.sendHeader("Location", String("http://") + kApIp.toString(), true);
    _server.send(302, "text/plain", "");
}
