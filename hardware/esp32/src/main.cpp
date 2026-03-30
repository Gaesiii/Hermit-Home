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
        
        // 2. Immediately enforce any relay state changes 
        // (e.g., instant User Overrides)
        relays.applyAll(g_relayState);
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
    wifi.init();

    mqtt.setCallback(mqttCallback);
    mqtt.init();
}

// ================================================================
//  MAIN LOOP
// ================================================================
void loop() {
    uint32_t now = millis();
    bool prevConnected = g_mqttWasConnected;

    // ----------------------------------------------------------------
    // 1. MAINTAIN NETWORK (Non-blocking)
    // ----------------------------------------------------------------
    mqtt.maintainConnection(g_mqttWasConnected);

    // If the connection just dropped, clear any active user override 
    // to force the system back into local autonomous survival mode.
    if (prevConnected && !g_mqttWasConnected) {
        priority.clearUserOverride();
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
        } 
        else {
            // NORMAL OPERATION: If User is NOT overriding, let AI/Local config rule
            if (!priority.isUserOverrideActive()) {
                hysteresis.evaluate(
                    sensors.getTemperature(), 
                    sensors.getHumidity(), 
                    sensors.getLux(), 
                    g_config, 
                    g_relayState
                );
            }
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