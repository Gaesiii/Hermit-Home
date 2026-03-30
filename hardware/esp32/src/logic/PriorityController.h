/**
 * ================================================================
 * @file    PriorityController.h
 * @brief   MQTT command dispatcher with User > AI > Local priority.
 *
 * This class is the single entry point for all inbound MQTT command
 * payloads.  It decodes a JsonDocument, determines the intent of
 * the message, and dispatches to the appropriate handler branch:
 *
 *   Priority 1 — User Override  (user_override == true)
 *   ─────────────────────────────────────────────────────
 *   The user explicitly commanded specific relay states from the
 *   mobile app.  The payload's "devices" object is applied directly
 *   to RelayState, bypassing the HysteresisEngine entirely, and the
 *   override flag is latched ON.
 *
 *   Priority 2 — AI / Threshold Update  (user_override == false)
 *   ─────────────────────────────────────────────────────────────
 *   Either the backend AI agent or the settings screen sent new
 *   threshold values.  The "thresholds" object patches only the
 *   fields that are present in the payload (partial update), saves
 *   to NVS flash via PrefsStore, and clears the override latch so
 *   the HysteresisEngine resumes autonomous control.
 *
 *   Priority 3 — Local Hysteresis  (no MQTT command)
 *   ─────────────────────────────────────────────────
 *   When no override is active, main.cpp calls HysteresisEngine
 *   directly.  PriorityController does not participate but exposes
 *   isUserOverrideActive() so main.cpp can gate that call correctly.
 *
 * Override-clear on MQTT disconnect:
 *   When the MQTT connection drops, MqttClientWrapper resets the
 *   wasConnected flag.  main.cpp is responsible for calling
 *   clearUserOverride() in that path so the device falls back to
 *   local hysteresis rather than being stuck in a stale override.
 *
 * Expected JSON shapes
 * ─────────────────────
 *   User override:
 *   {
 *     "user_override": true,
 *     "devices": {
 *       "heater": true,   // all fields optional — only present
 *       "mist":   false,  // keys are applied
 *       "fan":    true,
 *       "light":  false
 *     }
 *   }
 *
 *   Threshold update (AI or settings):
 *   {
 *     "user_override": false,
 *     "thresholds": {       // all sub-fields optional
 *       "temp_min": 23.0,
 *       "temp_max": 30.0,
 *       "hum_min":  65.0,
 *       "hum_max":  88.0,
 *       "lux_min":  150.0,
 *       "lux_max":  600.0
 *     }
 *   }
 * ================================================================
 */

#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>
#include "../storage/PrefsStore.h"        // TerrariumConfig, PrefsStore
#include "../actuators/RelayController.h" // RelayState

class PriorityController {
public:
    /**
     * @brief Construct a PriorityController with injected dependencies.
     *
     * Dependencies are injected as references rather than owned so
     * that main.cpp remains the single owner of all shared state —
     * consistent with the rest of the architecture.
     *
     * @param config    Reference to the live TerrariumConfig in main.cpp.
     *                  Updated in-place when a threshold command arrives.
     * @param relays    Reference to the live RelayState in main.cpp.
     *                  Updated in-place when a user_override command arrives.
     * @param store     Reference to the PrefsStore instance in main.cpp.
     *                  Called to persist config changes to NVS flash.
     */
    PriorityController(TerrariumConfig& config,
                       RelayState&      relays,
                       PrefsStore&      store);

    // -----------------------------------------------------------------
    // Command dispatcher
    // -----------------------------------------------------------------

    /**
     * @brief Parse and dispatch an inbound MQTT command payload.
     *
     * This is the direct extraction of handleCommandPayload() from the
     * original monolithic sketch, refactored into a class method.
     *
     * Call this from the MQTT callback in main.cpp after deserialising
     * the raw bytes into a JsonDocument.
     *
     * Side effects (depending on payload content):
     *   - May latch or clear _userOverrideActive.
     *   - May mutate _relays (user override path).
     *   - May mutate _config and call _store.saveConfig() (threshold path).
     *
     * @param doc   Fully deserialised, valid JsonDocument.
     *              If deserialisation failed the caller must NOT call
     *              this method (mirrors the original sketch's guard).
     */
    void parseMqttCommand(const JsonDocument& doc);

    // -----------------------------------------------------------------
    // State queries (used by main.cpp to gate HysteresisEngine)
    // -----------------------------------------------------------------

    /**
     * @brief Returns true when an active user override is latched ON.
     *
     * While true, main.cpp must skip the HysteresisEngine evaluate()
     * call so manual relay states are not clobbered by automation.
     */
    bool isUserOverrideActive() const;

    /**
     * @brief Explicitly clear the user override latch.
     *
     * Called by main.cpp when the MQTT connection drops (mirroring
     * the g_userOverride = false in the original loopMqttReconnect()).
     * Restores full autonomous (hysteresis) control.
     */
    void clearUserOverride();

private:
    // Injected references — not owned, never null after construction.
    TerrariumConfig& _config;
    RelayState&      _relays;
    PrefsStore&      _store;

    // Latch: true while a user_override command is active.
    bool _userOverrideActive;

    // -----------------------------------------------------------------
    // Private dispatch helpers
    // -----------------------------------------------------------------

    /**
     * @brief Apply the "devices" sub-object to relay states.
     *
     * Only keys present in the payload are applied; absent keys leave
     * the current relay state unchanged (safe partial update).
     *
     * @param devicesObj  The doc["devices"] JsonObject.
     */
    void _applyDeviceOverride(const JsonObject& devicesObj);

    /**
     * @brief Patch threshold values from the "thresholds" sub-object.
     *
     * Only keys present in the payload are written; absent keys
     * preserve the current config value (safe partial update).
     *
     * @param threshObj     The doc["thresholds"] JsonObject.
     * @return true if at least one threshold field was updated
     *         (triggers a flash save); false if the object was empty.
     */
    bool _applyThresholdUpdate(const JsonObject& threshObj);
};