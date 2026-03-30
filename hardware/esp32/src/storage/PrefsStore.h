/**
 * ================================================================
 * @file    PrefsStore.h
 * @brief   NVS Flash persistence layer for the Smart Terrarium.
 *
 * Owns two responsibilities:
 *   1. The canonical definition of TerrariumConfig — the single
 *      source of truth for all runtime threshold values. Every
 *      other layer (Logic, MQTT, SensorManager) includes this
 *      header to access the struct, never re-defining it.
 *
 *   2. The PrefsStore class — a thin, stateless wrapper around
 *      ESP32's Preferences (NVS) library that serialises and
 *      deserialises TerrariumConfig to/from flash under the
 *      "terrarium" namespace.
 *
 * Namespace key map (all stored as float, 15-char NVS key limit):
 *   "tempMin"  →  config.tempMin
 *   "tempMax"  →  config.tempMax
 *   "humMin"   →  config.humMin
 *   "humMax"   →  config.humMax
 *   "luxMin"   →  config.luxMin
 *   "luxMax"   →  config.luxMax
 *
 * NOTE: version_ts is intentionally NOT persisted to flash.
 * It is a runtime-only field stamped by the MQTT command handler
 * when a new threshold payload arrives, and has no meaningful
 * default to restore on cold boot.
 * ================================================================
 */

#pragma once

#include <Arduino.h>
#include <Preferences.h>

// ----------------------------------------------------------------
// TerrariumConfig
//
// Aggregates all environmental thresholds used by the hysteresis
// control loop. Default member values mirror the orignal sketch
// and act as the fallback when flash has never been written.
//
// All fields are floats to match the Preferences::getFloat /
// putFloat calls and to avoid precision loss in the Logic Engine.
// ----------------------------------------------------------------
struct TerrariumConfig {
    float    tempMin    = 24.0f;   ///< Heater ON  below this °C
    float    tempMax    = 29.0f;   ///< Heater OFF above this °C
    float    humMin     = 70.0f;   ///< Mist   ON  below this %RH
    float    humMax     = 85.0f;   ///< Mist   OFF above this %RH
    float    luxMin     = 200.0f;  ///< Light  ON  below this lux
    float    luxMax     = 500.0f;  ///< Light  OFF above this lux
    uint32_t version_ts = 0;       ///< Runtime-only: MQTT config timestamp (not persisted)
};

// ----------------------------------------------------------------
// PrefsStore
//
// Stateless service class — holds no config data itself.
// Each public method opens the NVS namespace, performs its
// operation, then closes it, so the handle is never left dangling
// across calls.
// ----------------------------------------------------------------
class PrefsStore {
public:
    /**
     * @brief Load thresholds from NVS flash into `config`.
     *
     * Opens the "terrarium" namespace in read-only mode.
     * For each key, Preferences::getFloat(key, default) is called
     * with the struct's current member value as the fallback — so
     * if a key has never been written (fresh device or after a
     * namespace wipe), the struct retains its compile-time defaults
     * exactly as the original loadConfigFromFlash() did.
     *
     * @param[in,out] config  Struct to populate. Pass in a
     *                        default-constructed TerrariumConfig;
     *                        members are overwritten only when the
     *                        corresponding NVS key exists.
     */
    void loadConfig(TerrariumConfig& config);

    /**
     * @brief Persist thresholds from `config` to NVS flash.
     *
     * Opens the "terrarium" namespace in read-write mode and writes
     * all six threshold floats. version_ts is deliberately omitted
     * (see file-level note above).
     *
     * Closes the namespace handle before returning so that a
     * subsequent loadConfig() call gets a consistent view.
     *
     * @param[in] config  Struct whose values will be written.
     *                    Passed by const-ref; no mutation occurs.
     */
    void saveConfig(const TerrariumConfig& config);

private:
    // A single Preferences instance is kept as a private member so
    // that begin()/end() bookends are always symmetrical and so the
    // object is never shared between the two public methods.
    Preferences _prefs;
};