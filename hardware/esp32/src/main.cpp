#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <Wire.h>
#include <BH1750.h>

// ================== CẤU HÌNH ==================
const char* apSSID = "Hermit Home";     
IPAddress apIP(192, 168, 4, 1);

#define BOOT_PIN 0   // Nút BOOT (GPIO 0) dùng để RESET WiFi (giữ 3 giây)

// ====================== KHỞI TẠO ĐỐI TƯỢNG ======================
WebServer server(80);
DNSServer dnsServer;
Preferences prefs;
Preferences terrariumPrefs;

bool daKetNoi = false;
bool apModeActive = false;

String savedSSID;
String savedPass;

// ====================== HTML GIAO DIỆN ĐẸP (GIỮ NGUYÊN) ======================
const char formHTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hermit Home</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap');
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: 'Inter', system-ui, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #333;
        }
        .container {
            background: white;
            max-width: 420px;
            width: 90%;
            border-radius: 24px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.15);
            overflow: hidden;
            animation: fadeIn 0.6s ease forwards;
        }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(30px); } to { opacity: 1; transform: translateY(0); } }
        .header { background: linear-gradient(135deg, #4facfe, #00f2fe); color: white; padding: 30px 20px; text-align: center; }
        .header h1 { font-size: 26px; margin-bottom: 8px; }
        .wifi-icon { font-size: 52px; margin-bottom: 10px; display: block; }
        .content { padding: 35px 30px; }
        .input-group { position: relative; margin-bottom: 22px; }
        input {
            width: 100%;
            padding: 16px 20px 16px 50px;
            border: 2px solid #e1e5e9;
            border-radius: 14px;
            font-size: 17px;
            transition: all 0.3s;
        }
        input:focus { outline: none; border-color: #667eea; box-shadow: 0 0 0 4px rgba(102, 126, 234, 0.15); }
        .icon { position: absolute; left: 18px; top: 50%; transform: translateY(-50%); font-size: 20px; color: #888; }
        button {
            width: 100%;
            padding: 16px;
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            border: none;
            border-radius: 14px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            position: relative;
            overflow: hidden;
        }
        button:hover { transform: translateY(-2px); box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3); }
        button:active { transform: scale(0.98); }
        .ripple { position: absolute; border-radius: 50%; background: rgba(255,255,255,0.4); transform: scale(0); animation: rippleAnim 0.6s linear; pointer-events: none; }
        @keyframes rippleAnim { to { transform: scale(4); opacity: 0; } }
        p { text-align: center; color: #666; font-size: 14.5px; margin-top: 25px; line-height: 1.5; }
        .note { font-size: 13px; color: #999; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <span class="wifi-icon">📶</span>
            <h1>Cấu hình WiFi</h1>
            <p>Hermit Home</p>
        </div>
        <div class="content">
            <form action="/connect" method="POST" id="wifiForm">
                <div class="input-group"><span class="icon">📡</span><input type="text" name="ssid" placeholder="Tên WiFi (SSID)" required autocomplete="off"></div>
                <div class="input-group"><span class="icon">🔑</span><input type="password" name="pass" placeholder="Mật khẩu WiFi" required></div>
                <button type="submit" id="submitBtn">KẾT NỐI NGAY</button>
            </form>
            <p class="note">Kết nối thành công Wifi tự động tắt<br>và hệ thống sẽ bắt đầu hoạt động.<br>Nhấn RST để reboot bình thường.<br>Giữ nút BOOT 3 giây để đặt lại WiFi!</p>
        </div>
    </div>

    <script>
        const btn = document.getElementById('submitBtn');
        btn.addEventListener('click', function(e) {
            let ripple = document.createElement('span');
            ripple.classList.add('ripple');
            let rect = btn.getBoundingClientRect();
            let size = Math.max(rect.width, rect.height);
            ripple.style.width = ripple.style.height = size + 'px';
            ripple.style.left = (e.clientX - rect.left - size/2) + 'px';
            ripple.style.top = (e.clientY - rect.top - size/2) + 'px';
            btn.appendChild(ripple);
            setTimeout(() => { ripple.remove(); }, 600);
        });

        document.getElementById('wifiForm').addEventListener('submit', function() {
            btn.innerHTML = 'Đang kết nối...';
            btn.disabled = true;
        });
    </script>
</body>
</html>
)rawliteral";

const char successHTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Thành công!</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap');
        body { font-family: 'Inter', sans-serif; background: linear-gradient(135deg, #4facfe, #00f2fe); min-height:100vh; display:flex; align-items:center; justify-content:center; margin:0; }
        .card { background:white; padding:40px 30px; border-radius:24px; text-align:center; max-width:380px; width:90%; box-shadow:0 20px 40px rgba(0,0,0,0.15); }
        .success-icon { font-size:80px; margin-bottom:20px; }
        h1 { color:#155724; font-size:28px; margin-bottom:15px; }
        p { color:#333; line-height:1.6; }
    </style>
</head>
<body>
    <div class="card">
        <div class="success-icon">✅</div>
        <h1>Kết nối thành công!</h1>
        <p>ESP32-S3 đã kết nối WiFi.<br>
           <strong style="color:#28a745;">kết nối thành công</strong><br><br>
           WiFi phát đã được tắt.
        </p>
    </div>
</body>
</html>
)rawliteral";

// ====================== WEB HANDLERS ======================
void handleRoot() { server.send(200, "text/html", formHTML); }

void handleConnect() {
  String ssid = server.arg("ssid");
  String pass = server.arg("pass");

  Serial.println("\nĐang thử kết nối: " + ssid);
  WiFi.begin(ssid.c_str(), pass.c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    prefs.putString("wifi_ssid", ssid);
    prefs.putString("wifi_pass", pass);

    daKetNoi = true;
    Serial.println("\n=== KẾT NỐI WIFI THÀNH CÔNG ===");
    Serial.print("IP: "); Serial.println(WiFi.localIP());

    server.send(200, "text/html", successHTML);

    delay(1500);
    WiFi.softAPdisconnect(true);
    apModeActive = false;
    Serial.println("Đã tắt SoftAP.");
  } else {
    WiFi.disconnect();
    String errorHTML = R"rawliteral(
<!DOCTYPE html><html lang="vi"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Lỗi</title>
<style>body{font-family:Arial;background:#ffebee;min-height:100vh;display:flex;align-items:center;justify-content:center;}
.card{background:white;padding:40px;border-radius:20px;text-align:center;max-width:360px;box-shadow:0 10px 30px rgba(0,0,0,0.1);}
h1{color:#d32f2f;} a{color:#1976d2;text-decoration:none;font-size:18px;}</style>
</head><body><div class="card"><h1>❌ Kết nối thất bại</h1><p>Sai tên WiFi hoặc mật khẩu.</p><p><a href="/">← Nhập lại</a></p></div></body></html>
)rawliteral";
    server.send(200, "text/html", errorHTML);
  }
}

void handleNotFound() {
  server.sendHeader("Location", String("http://") + apIP.toString(), true);
  server.send(302, "text/plain", "");
}

// ====================== SMART TERRARIUM VARIABLES ======================
#define PIN_DHT22       4
#define LIGHT_SCL       19
#define LIGHT_SDA       20
#define PIN_HEATER      15
#define PIN_MIST        16
#define PIN_LIGHT       17
#define PIN_FAN         18

#define RELAY_ON(pin)   digitalWrite(pin, HIGH) 
#define RELAY_OFF(pin)  digitalWrite(pin, LOW)
#define RELAY_SET(pin, state) ((state) ? RELAY_ON(pin) : RELAY_OFF(pin))

const char* MQTT_BROKER    = "pinkmason-9beefcd2.a02.usw2.aws.hivemq.cloud";
const int   MQTT_PORT      = 8883;
const char* MQTT_USER      = "admin"; 
const char* MQTT_PASS      = "Admin1!@";

const char* MQTT_CLIENT_ID = "ESP32_Garden_Phuc_001";
const char* USER_ID        = "67c6fd9a9acfdbc1d05c22b1";

char TOPIC_TELEMETRY[64];
char TOPIC_COMMANDS[64];
char TOPIC_CONFIRM[64];

const uint32_t INTERVAL_SENSOR_MS    = 1000;
const uint32_t INTERVAL_PUBLISH_MS   = 10000;
const uint32_t INTERVAL_RECONNECT_MS = 5000;

struct TerrariumConfig {
  float tempMin  = 24.0f; 
  float tempMax  = 29.0f; 
  float humMin   = 70.0f; 
  float humMax   = 85.0f; 
  float luxMin   = 200.0f; 
  float luxMax   = 500.0f; 
};

struct RelayState {
  bool heater = false;
  bool mist   = false;
  bool fan    = false;
  bool light  = false;
};

DHT                  dht(PIN_DHT22, DHT22);
BH1750               lightMeter;
WiFiClientSecure     espClient;
PubSubClient         mqttClient(espClient);

float g_temperature = NAN;
float g_humidity    = NAN;
float g_lux         = 0.0f;

TerrariumConfig g_config;
RelayState      g_relayState;

bool g_userOverride      = false;
bool g_sensorFault       = false;
bool g_mqttWasConnected  = false;

uint32_t t_lastSensor    = 0;
uint32_t t_lastPublish   = 0;
uint32_t t_lastReconnect = 0;

// ====================== PROTOTYPES ======================
void setupPins();
void setupMqtt();
bool reconnectMqtt();
void loopSensor();
void loopPublish();
void loopMqttReconnect();
void applyHysteresis();
void applyRelayStates();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void handleCommandPayload(const JsonDocument& doc);
void publishTelemetry();
void publishConfirmation(const char* device, bool state);
void saveConfigToFlash();
void loadConfigFromFlash();
void startAPMode();
void connectSavedWiFi();

// ====================== SETUP ======================
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n\n=== SMART TERRARIUM - Hermit Home ===");

  pinMode(BOOT_PIN, INPUT_PULLUP);

  prefs.begin("wifi", false);
  terrariumPrefs.begin("terrarium", false);

  savedSSID = prefs.getString("wifi_ssid", "");
  savedPass = prefs.getString("wifi_pass", "");

  snprintf(TOPIC_TELEMETRY, sizeof(TOPIC_TELEMETRY), "terrarium/telemetry/%s", USER_ID);
  snprintf(TOPIC_COMMANDS,  sizeof(TOPIC_COMMANDS),  "terrarium/commands/%s",  USER_ID);
  snprintf(TOPIC_CONFIRM,   sizeof(TOPIC_CONFIRM),   "terrarium/confirm/%s",   USER_ID);

  setupPins();
  Wire.begin(LIGHT_SDA, LIGHT_SCL);
  if (!lightMeter.begin()) Serial.println(F("[WARN] Lỗi BH1750!"));
  dht.begin();
  loadConfigFromFlash();
  espClient.setInsecure();

  if (savedSSID == "") {
    startAPMode();
  } else {
    connectSavedWiFi();
  }
}

void startAPMode() {
  Serial.println("👉 Khởi động chế độ AP + Portal");
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(apSSID);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255,255,255,0));

  Serial.print("AP: "); Serial.println(apSSID);
  Serial.print("IP: "); Serial.println(WiFi.softAPIP());

  dnsServer.start(53, "*", apIP);
  server.on("/", HTTP_GET, handleRoot);
  server.on("/connect", HTTP_POST, handleConnect);
  server.onNotFound(handleNotFound);
  server.begin();

  apModeActive = true;
}

void connectSavedWiFi() {
  Serial.println("📡 Đang kết nối WiFi đã lưu: " + savedSSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(savedSSID.c_str(), savedPass.c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  Serial.println();

  if (WiFi.status() == WL_CONNECTED) {
    daKetNoi = true;
    Serial.println("\n=== KẾT NỐI WIFI THÀNH CÔNG TỪ LƯU TRỮ ===");
    Serial.print("IP: "); Serial.println(WiFi.localIP());
    setupMqtt();
  } else {
    Serial.println("❌ Kết nối thất bại → xóa dữ liệu");
    prefs.clear();
    ESP.restart();
  }
}

// ====================== LOOP ======================
void loop() {
  if (apModeActive) {
    dnsServer.processNextRequest();
    server.handleClient();
  }

  if (daKetNoi) {
    Serial.println("kết nối thành công");

    uint32_t now = millis();

    if (now - t_lastSensor >= INTERVAL_SENSOR_MS) {
      t_lastSensor = now;
      loopSensor();
    }

    if (now - t_lastPublish >= INTERVAL_PUBLISH_MS) {
      t_lastPublish = now;
      loopPublish();
    }

    if (!mqttClient.connected()) {
      if (now - t_lastReconnect >= INTERVAL_RECONNECT_MS) {
        t_lastReconnect = now;
        loopMqttReconnect();
      }
    } else {
      mqttClient.loop();
      g_mqttWasConnected = true;
    }

    delay(1800);
  }

  // ================== GIỮ NÚT BOOT 3 GIÂY ĐỂ RESET WIFI ==================
  if (digitalRead(BOOT_PIN) == LOW) {
    unsigned long startPress = millis();
    while (digitalRead(BOOT_PIN) == LOW) {
      if (millis() - startPress > 3000) {
        Serial.println("\n⚠️ Phát hiện giữ nút BOOT 3 giây → RESET WIFI");
        prefs.clear();
        WiFi.disconnect(true, true);
        delay(1000);
        ESP.restart();
      }
      delay(50);
    }
  }
}

// ====================== CÁC HÀM TERRARIUM ======================
void setupPins() {
  pinMode(PIN_HEATER, OUTPUT);
  pinMode(PIN_MIST, OUTPUT);
  pinMode(PIN_LIGHT, OUTPUT);
  pinMode(PIN_FAN, OUTPUT);
  RELAY_OFF(PIN_HEATER);
  RELAY_OFF(PIN_MIST);
  RELAY_OFF(PIN_FAN);
  RELAY_OFF(PIN_LIGHT);
}

void setupMqtt() {
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(512);
}

bool reconnectMqtt() {
  if (WiFi.status() != WL_CONNECTED) return false;
  Serial.printf("[MQTT] Đang kết nối %s:%d ...\n", MQTT_BROKER, MQTT_PORT);

  const char* willTopic   = TOPIC_CONFIRM;
  const char* willPayload = "{\"status\":\"offline\"}";

  if (mqttClient.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASS, willTopic, 1, true, willPayload)) {
    Serial.println(F("[MQTT] Kết nối thành công!"));
    mqttClient.subscribe(TOPIC_COMMANDS, 1);
    return true;
  }
  Serial.printf("[MQTT] Thất bại, rc=%d\n", mqttClient.state());
  return false;
}

void loopSensor() {
  g_temperature = dht.readTemperature();
  g_humidity    = dht.readHumidity();
  g_lux         = lightMeter.readLightLevel();

  if (isnan(g_temperature) || isnan(g_humidity)) {
    g_sensorFault = true;
    return; 
  }
  g_sensorFault = false;
  if (g_lux < 0) g_lux = 0; 

  Serial.printf("[SENSOR] T=%.1f°C  H=%.1f%%  Lux=%.0f\n", g_temperature, g_humidity, g_lux);

  if (!g_userOverride) applyHysteresis();
  applyRelayStates();
}

void loopPublish() {
  if (!mqttClient.connected()) return;
  publishTelemetry();
}

void loopMqttReconnect() {
  if (g_mqttWasConnected) {
    g_mqttWasConnected = false;
    g_userOverride = false; 
  }
  reconnectMqtt();
}

void applyHysteresis() {
  if (g_temperature < g_config.tempMin) g_relayState.heater = true;
  else if (g_temperature > g_config.tempMax) g_relayState.heater = false;

  if (g_humidity < g_config.humMin) g_relayState.mist = true;
  else if (g_humidity > g_config.humMax) g_relayState.mist = false;

  if (g_lux < g_config.luxMin) g_relayState.light = true;
  else if (g_lux > g_config.luxMax) g_relayState.light = false;

  g_relayState.fan = true; 
}

void applyRelayStates() {
  RELAY_SET(PIN_HEATER, g_relayState.heater);
  RELAY_SET(PIN_MIST,   g_relayState.mist);
  RELAY_SET(PIN_FAN,    g_relayState.fan);
  RELAY_SET(PIN_LIGHT,  g_relayState.light);
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  JsonDocument doc;
  if (deserializeJson(doc, payload, length)) return;
  handleCommandPayload(doc);
}

void handleCommandPayload(const JsonDocument& doc) {
  if (doc["user_override"].as<bool>() == true) {
    g_userOverride = true;
    if (doc["devices"]["heater"].is<bool>()) g_relayState.heater = doc["devices"]["heater"].as<bool>();
    if (doc["devices"]["mist"].is<bool>()) g_relayState.mist = doc["devices"]["mist"].as<bool>();
    if (doc["devices"]["fan"].is<bool>()) g_relayState.fan = doc["devices"]["fan"].as<bool>();
    if (doc["devices"]["light"].is<bool>()) g_relayState.light = doc["devices"]["light"].as<bool>();
    applyRelayStates();
    return;
  }

  g_userOverride = false;
  bool configChanged = false;

  if (doc["thresholds"]["temp_min"].is<float>()) { g_config.tempMin = doc["thresholds"]["temp_min"].as<float>(); configChanged = true; }
  if (doc["thresholds"]["temp_max"].is<float>()) { g_config.tempMax = doc["thresholds"]["temp_max"].as<float>(); configChanged = true; }
  if (doc["thresholds"]["hum_min"].is<float>())  { g_config.humMin = doc["thresholds"]["hum_min"].as<float>(); configChanged = true; }
  if (doc["thresholds"]["hum_max"].is<float>())  { g_config.humMax = doc["thresholds"]["hum_max"].as<float>(); configChanged = true; }
  if (doc["thresholds"]["lux_min"].is<float>())  { g_config.luxMin = doc["thresholds"]["lux_min"].as<float>(); configChanged = true; }
  if (doc["thresholds"]["lux_max"].is<float>())  { g_config.luxMax = doc["thresholds"]["lux_max"].as<float>(); configChanged = true; }

  if (configChanged) saveConfigToFlash();
}

void publishTelemetry() {
  JsonDocument doc;
  if (isnan(g_temperature)) doc["temperature"] = nullptr;
  else doc["temperature"] = round(g_temperature * 10) / 10.0f;

  if (isnan(g_humidity)) doc["humidity"] = nullptr;
  else doc["humidity"] = round(g_humidity * 10) / 10.0f;

  doc["lux"]           = (int)g_lux;
  doc["sensor_fault"]  = g_sensorFault;
  doc["user_override"] = g_userOverride;

  JsonObject relays = doc["relays"].to<JsonObject>();
  relays["heater"] = g_relayState.heater;
  relays["mist"]   = g_relayState.mist;
  relays["fan"]    = g_relayState.fan;
  relays["light"]  = g_relayState.light;

  char buf[256];
  size_t len = serializeJson(doc, buf, sizeof(buf));

  Serial.print("📡 Đang gửi: "); Serial.println(buf);

  if (mqttClient.publish(TOPIC_TELEMETRY, buf, len)) {
    Serial.println("✅ [MQTT] ĐẨY DỮ LIỆU THÀNH CÔNG!");
  } else {
    Serial.println("❌ [MQTT] ĐẨY DỮ LIỆU THẤT BẠI!");
  }
}

void publishConfirmation(const char* device, bool state) {
  if (!mqttClient.connected()) return;
  JsonDocument doc;
  doc["event"]  = "override_ack";
  doc["device"] = device;
  doc["state"]  = state;
  char buf[128];
  size_t len = serializeJson(doc, buf, sizeof(buf));
  mqttClient.publish(TOPIC_CONFIRM, buf, len);
}

void saveConfigToFlash() {
  terrariumPrefs.putFloat("tempMin", g_config.tempMin);
  terrariumPrefs.putFloat("tempMax", g_config.tempMax);
  terrariumPrefs.putFloat("humMin",  g_config.humMin);
  terrariumPrefs.putFloat("humMax",  g_config.humMax);
  terrariumPrefs.putFloat("luxMin",  g_config.luxMin);
  terrariumPrefs.putFloat("luxMax",  g_config.luxMax);
}

void loadConfigFromFlash() {
  g_config.tempMin = terrariumPrefs.getFloat("tempMin", g_config.tempMin);
  g_config.tempMax = terrariumPrefs.getFloat("tempMax", g_config.tempMax);
  g_config.humMin  = terrariumPrefs.getFloat("humMin",  g_config.humMin);
  g_config.humMax  = terrariumPrefs.getFloat("humMax",  g_config.humMax);
  g_config.luxMin  = terrariumPrefs.getFloat("luxMin",  g_config.luxMin);
  g_config.luxMax  = terrariumPrefs.getFloat("luxMax",  g_config.luxMax);
}