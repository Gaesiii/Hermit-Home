/**
 * ================================================================
 * @file    main.cpp
 * @brief   Main entry point for the Smart Terrarium Edge Controller.
 * * This file ties together the modular PlatformIO architecture:
 * - HAL: Sensors and Relays
 * - Comms: WiFi and secure MQTT
 * - Storage: NVS flash memory for configuration
 * - Logic: Hysteresis automation and User/AI priority queue
 * ================================================================
 */

#include <Arduino.h>
#include "config.h"

// --- Layer Includes ---
#include "sensors/SensorManager.h"
#include "actuators/RelayController.h"
#include "comms/WifiManager.h"
#include "comms/MqttClient.h"
#include "storage/PrefsStore.h"
#include "logic/HysteresisEngine.h"
#include "logic/PriorityController.h"

// ================================================================
//  GLOBAL SERVICE OBJECTS
// ================================================================
SensorManager    sensors;
RelayController  relays;
WifiManager      wifi;
MqttClient       mqtt;
PrefsStore       store;
HysteresisEngine hysteresis;

// ================================================================
//  GLOBAL STATE DATA
// ================================================================
TerrariumConfig g_config;
RelayState      g_relayState;

// Inject dependencies into the Priority Controller
PriorityController priority(g_config, g_relayState, store);

// ================================================================
//  STATE TRACKERS & TIMERS
// ================================================================
bool g_mqttWasConnected = false;
uint32_t t_lastSensor   = 0;
uint32_t t_lastPublish  = 0;
String g_activeUserId;
uint32_t g_remoteOfflineSinceMs = 0;
bool g_localFallbackActive = false;

static inline void enforceMistSafetyLock() {
#if MIST_SAFETY_LOCK
    g_relayState.mist = false;
#endif
}

// ================================================================
//  MQTT CALLBACK
// ================================================================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
    // ArduinoJson 7 automatically sizes the document
    JsonDocument doc; 
    DeserializationError error = deserializeJson(doc, payload, length);

    if (!error) {
        // 1. Dispatch the payload to the Priority logic
        priority.parseMqttCommand(doc);

        enforceMistSafetyLock();

        // 2. Immediately enforce any relay state changes 
        // (e.g., instant User Overrides)
        relays.applyAll(g_relayState);

        // 3. Publish per-device acknowledgements whenever a payload contains
        // a "devices" object (user override or AI direct control).
        JsonObjectConst devicesObj = doc["devices"].as<JsonObjectConst>();
        if (!devicesObj.isNull()) {
            if (devicesObj["heater"].is<bool>()) {
                mqtt.publishConfirmation("heater", g_relayState.heater);
            }
            if (devicesObj["mist"].is<bool>()) {
                mqtt.publishConfirmation("mist", g_relayState.mist);
            }
            if (devicesObj["fan"].is<bool>()) {
                mqtt.publishConfirmation("fan", g_relayState.fan);
            }
            if (devicesObj["light"].is<bool>()) {
                mqtt.publishConfirmation("light", g_relayState.light);
            }
        }
    } else {
        Serial.print(F("[MQTT] JSON parse failed: "));
        Serial.println(error.c_str());
    }
}

// ================================================================
//  SETUP
// ================================================================
void setup() {
    Serial.begin(115200);
    // Thay vì while(!Serial), hãy dùng delay để chip tự chạy
    delay(3000); 
    Serial.println(F("\n[SYSTEM] Booting Smart Terrarium..."));

    relays.init();
    sensors.init();
    store.loadConfig(g_config);
    mqtt.setCallback(mqttCallback);
    mqtt.init();

    wifi.init();
    g_activeUserId = wifi.getUserId();
    mqtt.setUserId(g_activeUserId);
}

// ================================================================
//  MAIN LOOP
// ================================================================
void loop() {
    uint32_t now = millis();

    wifi.loop();
    const String& currentUserId = wifi.getUserId();
    if (currentUserId != g_activeUserId) {
        g_activeUserId = currentUserId;
        mqtt.setUserId(g_activeUserId);
    }

    // ----------------------------------------------------------------
    // 1. MAINTAIN NETWORK (Non-blocking)
    // ----------------------------------------------------------------
    mqtt.maintainConnection(g_mqttWasConnected);

    const bool remoteControlOnline =
        wifi.isConnected() && mqtt.isConnected() && !g_activeUserId.isEmpty();

    if (remoteControlOnline) {
        if (g_localFallbackActive) {
            g_localFallbackActive = false;
            Serial.println(F("[Control] Cloud/Agent link restored. Leaving ESP local fallback mode."));
        }
        g_remoteOfflineSinceMs = 0;
    } else {
        if (g_remoteOfflineSinceMs == 0) {
            g_remoteOfflineSinceMs = now;
            Serial.println(F("[Control] Cloud/Agent link offline. Waiting before ESP local fallback..."));
        }

        if (!g_localFallbackActive &&
            (now - g_remoteOfflineSinceMs) >= LOCAL_FALLBACK_DELAY_MS) {
            g_localFallbackActive = true;
            priority.clearUserOverride();
            Serial.printf(
                "[Control] Offline >= %lu ms. ESP local hardcoded hysteresis ENABLED.\n",
                static_cast<unsigned long>(LOCAL_FALLBACK_DELAY_MS)
            );
        }
    }

    // ----------------------------------------------------------------
    // 2. SENSOR & LOGIC LOOP (1-Second Cadence)
    // ----------------------------------------------------------------
    if (now - t_lastSensor >= INTERVAL_SENSOR_MS) {
        t_lastSensor = now;

        // Read environmental data
        sensors.readAll();

        // FAIL-SAFE: If DHT22 returns NaN, cut critical actuators
        if (sensors.isSensorFault()) {
            relays.emergencyShutdownHeatMist();
            g_relayState.mist = false;
        } 
        else {
            // Local hardcoded fallback is only enabled when cloud control has
            // been offline long enough. Otherwise keep current Agent/User state.
            if (g_localFallbackActive) {
                if (priority.isUserOverrideActive()) {
                    priority.clearUserOverride();
                }
                hysteresis.evaluate(
                    sensors.getTemperature(), 
                    sensors.getHumidity(), 
                    sensors.getLux(), 
                    g_config, 
                    g_relayState
                );
            }
            enforceMistSafetyLock();
            // Apply the evaluated or overridden states to the physical GPIOs
            relays.applyAll(g_relayState);
        }
    }

    // ----------------------------------------------------------------
    // 3. TELEMETRY PUBLISH LOOP (10-Second Cadence)
    // ----------------------------------------------------------------
    if (now - t_lastPublish >= INTERVAL_PUBLISH_MS) {
        t_lastPublish = now;

        if (mqtt.isConnected()) {
            enforceMistSafetyLock();
            mqtt.publishTelemetry(
                sensors.getTemperature(),
                sensors.getHumidity(),
                sensors.getLux(),
                sensors.isSensorFault(),
                priority.isUserOverrideActive(),
                g_relayState
            );
        }
    }
}
