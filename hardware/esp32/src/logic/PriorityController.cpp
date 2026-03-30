/**
 * ================================================================
 * @file    PriorityController.cpp
 * @brief   Implementation of PriorityController.
 * ================================================================
 */

#include "PriorityController.h"

// ----------------------------------------------------------------
// Constructor
// ----------------------------------------------------------------
PriorityController::PriorityController(TerrariumConfig& config,
                                       RelayState&      relays,
                                       PrefsStore&      store)
    : _config(config),
      _relays(relays),
      _store(store),
      _userOverrideActive(false)
{
}

// ----------------------------------------------------------------
// Public: parseMqttCommand
// ----------------------------------------------------------------
void PriorityController::parseMqttCommand(const JsonDocument& doc) {

    // ── Priority 1: User Override ─────────────────────────────────
    // The mobile app has explicitly commanded specific relay states.
    // Latch the override flag and apply the device map directly,
    // bypassing the hysteresis engine entirely.
    if (doc["user_override"].as<bool>() == true) {
        _userOverrideActive = true;

        Serial.println(F("[Priority] User override ACTIVE — applying device map."));

        JsonObject devicesObj = doc["devices"].as<JsonObject>();
        _applyDeviceOverride(devicesObj);

        // Note: RelayController::applyState() is NOT called here.
        // main.cpp owns the GPIO write cycle; it reads _relays after
        // parseMqttCommand() returns and drives the hardware itself.
        // This keeps PriorityController free of HAL dependencies.
        return;
    }

    // ── Priority 2: Threshold Update (AI agent or Settings screen) ─
    // user_override == false signals that autonomous control should
    // resume and/or new threshold values have been sent.
    _userOverrideActive = false;
    Serial.println(F("[Priority] User override CLEARED — resuming hysteresis."));

    JsonObject threshObj = doc["thresholds"].as<JsonObject>();
    bool changed = _applyThresholdUpdate(threshObj);

    if (changed) {
        // Persist to NVS so thresholds survive a power cycle.
        _store.saveConfig(_config);
    }
}

// ----------------------------------------------------------------
// Public: isUserOverrideActive
// ----------------------------------------------------------------
bool PriorityController::isUserOverrideActive() const {
    return _userOverrideActive;
}

// ----------------------------------------------------------------
// Public: clearUserOverride
// ----------------------------------------------------------------
void PriorityController::clearUserOverride() {
    if (_userOverrideActive) {
        _userOverrideActive = false;
        Serial.println(F("[Priority] Override latch cleared (MQTT disconnect)."));
    }
}

// ----------------------------------------------------------------
// Private: _applyDeviceOverride
// ----------------------------------------------------------------
void PriorityController::_applyDeviceOverride(const JsonObject& devicesObj) {
    // Only overwrite a relay field if the key is actually present in
    // the payload. This enables partial override commands (e.g., the
    // app sends only "heater": true without touching mist/fan/light).
    if (devicesObj["heater"].is<bool>()) {
        _relays.heater = devicesObj["heater"].as<bool>();
        Serial.printf("[Priority]   heater → %s\n",
                      _relays.heater ? "ON" : "OFF");
    }
    if (devicesObj["mist"].is<bool>()) {
        _relays.mist = devicesObj["mist"].as<bool>();
        Serial.printf("[Priority]   mist   → %s\n",
                      _relays.mist ? "ON" : "OFF");
    }
    if (devicesObj["fan"].is<bool>()) {
        _relays.fan = devicesObj["fan"].as<bool>();
        Serial.printf("[Priority]   fan    → %s\n",
                      _relays.fan ? "ON" : "OFF");
    }
    if (devicesObj["light"].is<bool>()) {
        _relays.light = devicesObj["light"].as<bool>();
        Serial.printf("[Priority]   light  → %s\n",
                      _relays.light ? "ON" : "OFF");
    }
}

// ----------------------------------------------------------------
// Private: _applyThresholdUpdate
// ----------------------------------------------------------------
bool PriorityController::_applyThresholdUpdate(const JsonObject& threshObj) {
    bool changed = false;

    // Each field is guarded by .is<float>() before reading — this
    // preserves the original sketch's exact partial-update semantics:
    // only keys present in the payload mutate the live config.
    if (threshObj["temp_min"].is<float>()) {
        _config.tempMin = threshObj["temp_min"].as<float>();
        Serial.printf("[Priority]   tempMin → %.1f\n", _config.tempMin);
        changed = true;
    }
    if (threshObj["temp_max"].is<float>()) {
        _config.tempMax = threshObj["temp_max"].as<float>();
        Serial.printf("[Priority]   tempMax → %.1f\n", _config.tempMax);
        changed = true;
    }
    if (threshObj["hum_min"].is<float>()) {
        _config.humMin = threshObj["hum_min"].as<float>();
        Serial.printf("[Priority]   humMin  → %.1f\n", _config.humMin);
        changed = true;
    }
    if (threshObj["hum_max"].is<float>()) {
        _config.humMax = threshObj["hum_max"].as<float>();
        Serial.printf("[Priority]   humMax  → %.1f\n", _config.humMax);
        changed = true;
    }
    if (threshObj["lux_min"].is<float>()) {
        _config.luxMin = threshObj["lux_min"].as<float>();
        Serial.printf("[Priority]   luxMin  → %.0f\n", _config.luxMin);
        changed = true;
    }
    if (threshObj["lux_max"].is<float>()) {
        _config.luxMax = threshObj["lux_max"].as<float>();
        Serial.printf("[Priority]   luxMax  → %.0f\n", _config.luxMax);
        changed = true;
    }

    if (!changed) {
        Serial.println(F("[Priority]   No threshold fields found in payload."));
    }

    return changed;
}