/**
 * ================================================================
 * @file    MqttClient.cpp
 * @brief   Implementation of MqttClient.
 * ================================================================
 */

#include "MqttClient.h"
#include <WiFi.h>        // WiFi.status()
#include <math.h>        // isnan(), round()
#include <stdio.h>
#include <string.h>
#include <time.h>

// Pull in the RelayState definition. Adjust the path to match your
// project's include structure (it lives in config.h or a shared
// types header in the original sketch).
#include "config.h"
#include "../actuators/RelayController.h"

namespace {
bool isAsciiWhitespace(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}
}

// ----------------------------------------------------------------
// Constructor
// ----------------------------------------------------------------
MqttClient::MqttClient()
    : _mqttClient(_espClient),
      callback(nullptr),
      _lastReconnectAttemptMs(0),
      _lastTimeSyncAttemptMs(0),
      _brokerPort(MQTT_PORT),
      _topicsReady(false)
{
    _brokerHost[0] = '\0';
    _runtimeClientId[0] = '\0';
    _topicTelemetry[0] = '\0';
    _topicCommands[0] = '\0';
    _topicConfirm[0] = '\0';
}

// ----------------------------------------------------------------
// Public: setCallback
// ----------------------------------------------------------------
void MqttClient::setCallback(MQTT_CALLBACK_SIGNATURE) {
    // Store the pointer so we can register it in init() and
    // re-register it after any future reconnect if needed.
    this->callback = callback;
}

// ----------------------------------------------------------------
// Public: init
// ----------------------------------------------------------------
void MqttClient::init() {
    // Skip TLS certificate verification — required for HiveMQ Cloud
    // on port 8883 without provisioning a CA bundle on the ESP32.
    _espClient.setInsecure();

    // Normalize MQTT_BROKER so accidental URL input still works:
    // e.g. https://cluster.hivemq.cloud:8883 -> cluster.hivemq.cloud + 8883
    _normalizeBrokerEndpoint();
    _mqttClient.setServer(_brokerHost, _brokerPort);

    // Register whatever callback was injected via setCallback().
    // If none was set, this is a no-op (PubSubClient accepts nullptr).
    if (callback != nullptr) {
        _mqttClient.setCallback(callback);
    }

    // 512 bytes matches the original sketch's explicit setBufferSize call.
    // Increase if you add larger JSON payloads in future.
    _mqttClient.setBufferSize(512);
    _mqttClient.setKeepAlive(30);

    const uint64_t chipId = ESP.getEfuseMac();
    snprintf(
        _runtimeClientId,
        sizeof(_runtimeClientId),
        "%s-%06lX",
        MQTT_CLIENT_ID,
        static_cast<unsigned long>(chipId & 0xFFFFFFULL)
    );

    Serial.printf(
        "[MQTT] Client configured - broker raw='%s' normalized='%s:%u' clientId='%s'\n",
        MQTT_BROKER,
        _brokerHost,
        static_cast<unsigned>(_brokerPort),
        _runtimeClientId
    );
}

void MqttClient::setUserId(const String& userId) {
    String trimmed = userId;
    trimmed.trim();

    if (trimmed.isEmpty()) {
        _userId = "";
        _topicsReady = false;
        _topicTelemetry[0] = '\0';
        _topicCommands[0] = '\0';
        _topicConfirm[0] = '\0';
        if (_mqttClient.connected()) {
            _mqttClient.disconnect();
        }
        Serial.println(F("[MQTT] userID is empty. Waiting for portal configuration."));
        return;
    }

    if (_userId == trimmed && _topicsReady) {
        return;
    }

    _userId = trimmed;
    snprintf(_topicTelemetry, sizeof(_topicTelemetry), "terrarium/telemetry/%s", _userId.c_str());
    snprintf(_topicCommands,  sizeof(_topicCommands),  "terrarium/commands/%s",  _userId.c_str());
    snprintf(_topicConfirm,   sizeof(_topicConfirm),   "terrarium/confirm/%s",   _userId.c_str());
    _topicsReady = true;

    if (_mqttClient.connected()) {
        _mqttClient.disconnect();
    }

    Serial.printf("[MQTT] Runtime topics set for userID=%s\n", _userId.c_str());
    Serial.printf("[MQTT] Topic commands: %s\n", _topicCommands);
}

// ----------------------------------------------------------------
// Public: maintainConnection
// ----------------------------------------------------------------
void MqttClient::maintainConnection(bool& wasConnectedFlag) {
    if (!_topicsReady) {
        return;
    }

    if (_mqttClient.connected()) {
        // Happy path: pump the client so it handles inbound messages
        // and sends keepalive PINGREQs on time.
        _mqttClient.loop();
        wasConnectedFlag = true;
        return;
    }

    // --- Disconnected path ---
    // Non-blocking cadence gate: only attempt a reconnect once every
    // INTERVAL_RECONNECT_MS milliseconds (default 5 s from config.h).
    uint32_t now = millis();
    if ((now - _lastReconnectAttemptMs) < INTERVAL_RECONNECT_MS) {
        return; // Too soon — skip and return to the main loop.
    }

    _lastReconnectAttemptMs = now;

    // If the client was previously connected, clear the override flag
    // in main.cpp by resetting wasConnectedFlag. The caller (main.cpp)
    // is responsible for also clearing g_userOverride when it sees
    // wasConnectedFlag transition from true → false here.
    if (wasConnectedFlag) {
        wasConnectedFlag = false;
        Serial.println(F("[MQTT] Connection lost — clearing user override flag."));
    }

    _reconnect();
}

// ----------------------------------------------------------------
// Public: publishTelemetry
// ----------------------------------------------------------------
void MqttClient::publishTelemetry(float temperature,
                                         float humidity,
                                         float lux,
                                         bool  sensorFault,
                                         bool  userOverride,
                                         const RelayState& relays) {
    if (!_topicsReady || !_mqttClient.connected()) {
        Serial.println(F("[MQTT] publishTelemetry skipped — not connected."));
        return;
    }

    JsonDocument doc;

    // --- NaN-safe temperature ---
    // DHT22 returns NaN on a bad read; JSON has no NaN literal so we
    // map it to null, exactly as the original sketch does.
    if (isnan(temperature)) {
        doc["temperature"] = nullptr;
    } else {
        // Round to one decimal place (e.g. 25.67 → 25.7)
        doc["temperature"] = roundf(temperature * 10.0f) / 10.0f;
    }

    // --- NaN-safe humidity ---
    if (isnan(humidity)) {
        doc["humidity"] = nullptr;
    } else {
        doc["humidity"] = roundf(humidity * 10.0f) / 10.0f;
    }

    // --- Scalar fields ---
    doc["lux"]           = static_cast<int>(lux);
    doc["sensor_fault"]  = sensorFault;
    doc["user_override"] = userOverride;
    doc["user_id"]       = _userId;

    // --- Relay sub-object ---
    JsonObject relayObj = doc["relays"].to<JsonObject>();
    relayObj["heater"]  = relays.heater;
    relayObj["mist"]    = relays.mist;
    relayObj["fan"]     = relays.fan;
    relayObj["light"]   = relays.light;

    // Serialise into a stack buffer (256 bytes is sufficient for this
    // payload; bump up if you add more fields in future).
    char buf[256];
    size_t len = serializeJson(doc, buf, sizeof(buf));

    Serial.print(F("[MQTT] Publishing telemetry: "));
    Serial.println(buf);

    if (_mqttClient.publish(
            _topicTelemetry,
            reinterpret_cast<const uint8_t*>(buf),
            static_cast<unsigned int>(len),
            false)) {
        Serial.println(F("[MQTT] Telemetry published OK."));
    } else {
        Serial.println(F("[MQTT] Telemetry publish FAILED."));
    }
}

// ----------------------------------------------------------------
// Public: publishConfirmation
// ----------------------------------------------------------------
void MqttClient::publishConfirmation(const char* device, bool state) {
    if (!_topicsReady || !_mqttClient.connected()) return;

    JsonDocument doc;
    doc["event"]  = "override_ack";
    doc["device"] = device;
    doc["state"]  = state;
    doc["user_id"] = _userId;

    char buf[128];
    size_t len = serializeJson(doc, buf, sizeof(buf));
    _mqttClient.publish(
        _topicConfirm,
        reinterpret_cast<const uint8_t*>(buf),
        static_cast<unsigned int>(len),
        false
    );

    Serial.printf("[MQTT] Confirmation sent → device: %s  state: %s\n",
                  device, state ? "ON" : "OFF");
}

// ----------------------------------------------------------------
// Public: isConnected
// ----------------------------------------------------------------
bool MqttClient::isConnected() {
    return _mqttClient.connected();
}

// ----------------------------------------------------------------
// Private: _reconnect
// ----------------------------------------------------------------
bool MqttClient::_reconnect() {
    if (!_topicsReady) {
        Serial.println(F("[MQTT] Reconnect skipped — userID/topic not configured."));
        return false;
    }

    // Guard: don't bother trying if WiFi is down.
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println(F("[MQTT] Reconnect skipped — WiFi not connected."));
        return false;
    }

    // For TLS MQTT, sync clock before handshake (needed on many brokers).
    if (_brokerPort == 8883U && !_syncClockIfNeeded()) {
        Serial.println(F("[MQTT] Reconnect delayed - clock not synced yet."));
        return false;
    }

    Serial.printf("[MQTT] Attempting connection to %s:%u ...\n",
                  _brokerHost, static_cast<unsigned>(_brokerPort));

    // Last-Will-and-Testament — broker publishes this automatically
    // if the ESP32 disconnects ungracefully (power loss, crash, etc.).
    const char* willTopic   = _topicConfirm;
    const char* willPayload = "{\"status\":\"offline\"}";
    const uint8_t willQos   = 1;
    const bool    willRetain = true;

    const char* clientId =
        (_runtimeClientId[0] != '\0') ? _runtimeClientId : MQTT_CLIENT_ID;

    bool connected = _mqttClient.connect(
        clientId,         // Runtime-unique client ID
        MQTT_USER,        // HiveMQ username
        MQTT_PASS,        // HiveMQ password
        willTopic,        // LWT topic
        willQos,          // LWT QoS
        willRetain,       // LWT retained flag
        willPayload       // LWT payload
    );

    if (connected) {
        Serial.println(F("[MQTT] Connected successfully!"));

        // Subscribe to the command topic (QoS 1 = at-least-once delivery).
        _mqttClient.subscribe(_topicCommands, 1);
        Serial.printf("[MQTT] Subscribed to: %s\n", _topicCommands);

        // Replace any stale retained "offline" LWT state once the device is online.
        const char* onlinePayload = "{\"status\":\"online\"}";
        _mqttClient.publish(
            _topicConfirm,
            reinterpret_cast<const uint8_t*>(onlinePayload),
            static_cast<unsigned int>(strlen(onlinePayload)),
            true
        );
        Serial.println(F("[MQTT] Online status retained on confirm topic."));
        return true;
    }

    // Log the PubSubClient numeric state code for easier debugging.
    // Codes: https://pubsubclient.knolleary.net/api#state
    Serial.printf("[MQTT] Connect failed, rc = %d. Will retry in %lu ms.\n",
                  _mqttClient.state(),
                  static_cast<unsigned long>(INTERVAL_RECONNECT_MS));
    return false;
}

void MqttClient::_normalizeBrokerEndpoint() {
    const char* raw = MQTT_BROKER;
    while (*raw != '\0' && isAsciiWhitespace(*raw)) {
        ++raw;
    }

    const char* start = raw;
    const char* scheme = strstr(start, "://");
    if (scheme != nullptr) {
        start = scheme + 3;
    }

    const char* end = start;
    while (*end != '\0' && *end != '/' && *end != '?' && *end != '#') {
        ++end;
    }
    while (end > start && isAsciiWhitespace(*(end - 1))) {
        --end;
    }

    const char* colon = nullptr;
    for (const char* p = start; p < end; ++p) {
        if (*p == ':') {
            colon = p;
        }
    }

    uint16_t port = MQTT_PORT;
    const char* hostEnd = end;
    if (colon != nullptr && (colon + 1) < end) {
        uint32_t parsedPort = 0;
        bool validPort = true;
        for (const char* p = colon + 1; p < end; ++p) {
            if (*p < '0' || *p > '9') {
                validPort = false;
                break;
            }
            parsedPort = parsedPort * 10U + static_cast<uint32_t>(*p - '0');
            if (parsedPort > 65535U) {
                validPort = false;
                break;
            }
        }
        if (validPort && parsedPort > 0U) {
            port = static_cast<uint16_t>(parsedPort);
            hostEnd = colon;
        }
    }

    while (hostEnd > start && isAsciiWhitespace(*(hostEnd - 1))) {
        --hostEnd;
    }

    size_t hostLen = static_cast<size_t>(hostEnd - start);
    if (hostLen == 0U) {
        strncpy(_brokerHost, MQTT_BROKER, sizeof(_brokerHost) - 1U);
        _brokerHost[sizeof(_brokerHost) - 1U] = '\0';
        _brokerPort = MQTT_PORT;
        Serial.println(F("[MQTT] WARN: Invalid MQTT_BROKER format; using raw value."));
        return;
    }

    if (hostLen >= sizeof(_brokerHost)) {
        hostLen = sizeof(_brokerHost) - 1U;
        Serial.println(F("[MQTT] WARN: Broker host too long; truncating."));
    }

    memcpy(_brokerHost, start, hostLen);
    _brokerHost[hostLen] = '\0';
    _brokerPort = port;
}

bool MqttClient::_syncClockIfNeeded() {
    const time_t minEpoch = static_cast<time_t>(NTP_MIN_VALID_EPOCH);
    time_t now = time(nullptr);
    if (now >= minEpoch) {
        return true;
    }

    uint32_t nowMs = millis();
    if ((nowMs - _lastTimeSyncAttemptMs) < INTERVAL_RECONNECT_MS) {
        return false;
    }
    _lastTimeSyncAttemptMs = nowMs;

    Serial.println(F("[TIME] Syncing NTP clock before TLS MQTT..."));
    configTime(
        NTP_GMT_OFFSET_SEC,
        NTP_DAYLIGHT_OFFSET_SEC,
        NTP_SERVER_1,
        NTP_SERVER_2
    );

    uint32_t startMs = millis();
    while ((millis() - startMs) < NTP_SYNC_TIMEOUT_MS) {
        now = time(nullptr);
        if (now >= minEpoch) {
            Serial.printf("[TIME] NTP synced. Epoch=%lu\n",
                          static_cast<unsigned long>(now));
            return true;
        }
        delay(200);
    }

    Serial.println(F("[TIME] NTP sync timeout. Will retry on next cycle."));
    return false;
}
