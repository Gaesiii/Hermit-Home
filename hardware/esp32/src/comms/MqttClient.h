/**
 * ================================================================
 * @file    MqttClient.h
 * @brief   Secure MQTT client wrapper for the Smart Terrarium.
 *
 * Encapsulates WiFiClientSecure + PubSubClient behind a clean API.
 *
 * Design decisions carried over from the original sketch:
 * - espClient.setInsecure()  →  skips TLS cert verification
 * (HiveMQ Cloud on port 8883).
 * - LWT "offline" message published on user-scoped confirm topic.
 * - Buffer size fixed at 512 bytes (matches original).
 * - Non-blocking reconnect gated by INTERVAL_RECONNECT_MS.
 *
 * Usage in main.cpp:
 * mqtt.setCallback(myCallback);
 * mqtt.init();
 * // in loop():
 * mqtt.maintainConnection();
 * mqtt.publishTelemetry(temp, hum, lux, fault, relays);
 * ================================================================
 */

#pragma once

#include <Arduino.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "config.h"   // MQTT_* constants, INTERVAL_RECONNECT_MS

// Forward-declare the RelayState struct so the header stays
// independent of the full sensor/actuator headers.
// main.cpp (which owns both) will include everything in the right order.
struct RelayState;

class MqttClient {
public:
    MqttClient();

    // -----------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------

    /**
     * @brief Inject the MQTT message callback before calling init().
     *
     * Call this from main.cpp *before* init() so the callback is
     * registered at connect time, not patched in afterwards.
     *
     * @param cb  PubSubClient-compatible callback function pointer.
     */
    void setCallback(MQTT_CALLBACK_SIGNATURE);

    /**
     * @brief Configure the secure client and MQTT server.
     *
     * Calls espClient.setInsecure(), sets the server/port from
     * config.h, registers the callback, and sets the buffer size.
     * Does NOT attempt a connection — that happens inside
     * maintainConnection() so it remains non-blocking.
     */
    void init();

    /**
     * @brief Configure runtime user ID used to build MQTT topics.
     *
     * Topics follow:
     * - terrarium/telemetry/<userId>
     * - terrarium/commands/<userId>
     * - terrarium/confirm/<userId>
     *
     * If called with a different userId while connected, the client
     * disconnects so the next maintainConnection() cycle reconnects
     * and re-subscribes using the new topic set.
     */
    void setUserId(const String& userId);

    // -----------------------------------------------------------------
    // Runtime (call every loop() iteration)
    // -----------------------------------------------------------------

    /**
     * @brief Non-blocking reconnect + keepalive pump.
     *
     * - If connected  → calls mqttClient.loop() (processes inbound
     * messages and keepalive pings).
     * - If disconnected → attempts reconnect at most once every
     * INTERVAL_RECONNECT_MS milliseconds.
     *
     * Also maintains the `wasConnected` flag so that main.cpp can
     * detect a drop and clear g_userOverride (same logic as the
     * original loopMqttReconnect()).
     *
     * @param[out] wasConnectedFlag  Reference to main.cpp's
     * g_mqttWasConnected; updated here to preserve the
     * original drop-detection behaviour.
     */
    void maintainConnection(bool& wasConnectedFlag);

    // -----------------------------------------------------------------
    // Publishing
    // -----------------------------------------------------------------

    /**
     * @brief Serialize sensor + relay data to JSON and publish.
     *
     * Handles NaN gracefully: temperature and humidity are serialized
     * as JSON `null` when the DHT22 read fails, exactly matching the
     * original publishTelemetry() implementation.
     *
     * JSON shape:
     * {
     * "temperature": <float|null>,
     * "humidity":    <float|null>,
     * "lux":         <int>,
     * "sensor_fault": <bool>,
     * "user_override": <bool>,
     * "user_id": <string>,
     * "relays": {
     * "heater": <bool>, "mist": <bool>,
     * "fan":    <bool>, "light": <bool>
     * }
     * }
     *
     * @param temperature   DHT22 reading (may be NAN).
     * @param humidity      DHT22 reading (may be NAN).
     * @param lux           BH1750 reading.
     * @param sensorFault   True when DHT22 returned NaN this cycle.
     * @param userOverride  True when a manual override command is active.
     * @param relays        Current relay states.
     */
    void publishTelemetry(float temperature,
                          float humidity,
                          float lux,
                          bool  sensorFault,
                          bool  userOverride,
                          const RelayState& relays);

    /**
     * @brief Publish a single-device override acknowledgement.
     *
     * JSON shape: { "event": "override_ack", "device": <str>, "state": <bool> }
     *
     * @param device  Device name string, e.g. "heater".
     * @param state   New state that was applied.
     */
    void publishConfirmation(const char* device, bool state);

    /**
     * @brief Convenience wrapper around PubSubClient::connected().
     */
    bool isConnected();

private:
    WiFiClientSecure  _espClient;
    PubSubClient      _mqttClient;

    MQTT_CALLBACK_SIGNATURE;          // stores the injected callback ptr

    uint32_t _lastReconnectAttemptMs; // tracks non-blocking retry cadence
    uint32_t _lastTimeSyncAttemptMs;

    char     _brokerHost[128];
    uint16_t _brokerPort;

    /**
     * @brief Internal blocking-free reconnect attempt (called by
     * maintainConnection when the cadence timer fires).
     *
     * Mirrors reconnectMqtt() from the original sketch:
     * - Guards on WiFi being up.
     * - Connects with LWT, username/password.
     * - Subscribes to commands topic on success.
     *
     * @return true on successful connect.
     */
    bool _reconnect();
    void _normalizeBrokerEndpoint();
    bool _syncClockIfNeeded();

private:
    String _userId;
    char   _runtimeClientId[96];
    char   _topicTelemetry[96];
    char   _topicCommands[96];
    char   _topicConfirm[96];
    bool   _topicsReady;
};
