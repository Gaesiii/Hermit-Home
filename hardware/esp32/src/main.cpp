#include <Arduino.h>
#include "config.h"
#include "sensors/SensorManager.h"
#include "actuators/RelayController.h"
#include "comms/WifiManager.h"
#include "comms/MqttClientWrapper.h"

// --- Global Objects ---
WifiManager      wifi;
MqttClientWrapper mqtt;
SensorManager sensors;
RelayController relays;

// --- Global State Variables ---
float g_temperature = NAN;
float g_humidity    = NAN;
float g_lux         = 0.0f;
bool g_userOverride = false; // Will be set by MQTT later

// Mock state for relays (Will be managed by Priority/Hysteresis logic later)
struct RelayState {
    bool heater = false;
    bool mist   = false;
    bool fan    = false;
    bool light  = false;
} g_relayState;

// --- Timers ---
uint32_t t_lastSensor = 0;

// ================================================================
//  SETUP
// ================================================================
void setup() {
    Serial.begin(115200);
    delay(100);
    Serial.println("\n[SYSTEM] Booting Smart Terrarium Edge Controller...");

    // 1. Initialize Hardware Abstraction Layer (HAL)
    relays.init();
    sensors.init();

    Serial.println("[SYSTEM] Hardware initialized. Entering local loop.");
}

// ================================================================
//  LOCAL SURVIVAL LOOP & SENSORS
// ================================================================
void loopSensor() {
    // 1. Read all sensors
    sensors.readAll();

    // 2. Fail-Safe Check (Preserved exact logic)
    if (sensors.isSensorFault()) {
        Serial.println("[DANGER] Sensor NaN fault! Executing emergency shutdown.");
        relays.emergencyShutdownHeatMist(); 
        return; // Early return prevents applyAll() from executing
    }

    // 3. Update global state
    g_temperature = sensors.getTemperature();
    g_humidity    = sensors.getHumidity();
    g_lux         = sensors.getLux();

    Serial.printf("[SENSOR] T=%.1f°C  H=%.1f%%  Lux=%.0f\n", g_temperature, g_humidity, g_lux);

    // 4. Temporary Dummy Logic (Until HysteresisEngine is implemented)
    // If we had the hysteresis engine, it would run here if (!g_userOverride)
    if (!g_userOverride) {
        g_relayState.fan = true; // Fan always on for now
    }

    // 5. Apply states to physical relays
    relays.applyAll(
        g_relayState.heater, 
        g_relayState.mist, 
        g_relayState.fan, 
        g_relayState.light
    );
}

// ================================================================
//  MAIN LOOP
// ================================================================
void loop() {
    uint32_t now = millis();

    // 1-Second Non-Blocking Local Loop
    if (now - t_lastSensor >= INTERVAL_SENSOR_MS) {
        t_lastSensor = now;
        loopSensor();
    }

    // MQTT and WiFi logic will be added here in the next phase
}