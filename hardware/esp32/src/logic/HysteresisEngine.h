/**
 * ================================================================
 * @file    HysteresisEngine.h
 * @brief   Threshold-based automatic control for the Smart Terrarium.
 *
 * Implements a two-point (bang-bang) hysteresis controller for all
 * three environmental variables: temperature, humidity, and lux.
 *
 * The engine is deliberately stateless — it holds no readings and
 * no config of its own.  Every evaluate() call receives the current
 * snapshot by value/const-ref and mutates only the RelayState output.
 * This makes the engine trivially unit-testable with PlatformIO's
 * native test runner (no hardware required).
 *
 * Hysteresis semantics (preserved exactly from the original sketch):
 *
 *   Heater  ON  when temp  < tempMin
 *           OFF when temp  > tempMax
 *           (unchanged when tempMin <= temp <= tempMax)
 *
 *   Mist    ON  when hum   < humMin
 *           OFF when hum   > humMax
 *           (unchanged in the dead-band)
 *
 *   Light   ON  when lux   < luxMin
 *           OFF when lux   > luxMax
 *           (unchanged in the dead-band)
 *
 *   Fan     ALWAYS ON  (unconditional — matches original sketch)
 *
 * The dead-band between Min and Max prevents rapid relay chatter
 * near the setpoint; the last committed state is preserved until
 * the reading crosses the opposite threshold.
 * ================================================================
 */

#pragma once

#include <Arduino.h>
#include "../storage/PrefsStore.h"    // TerrariumConfig
#include "../actuators/RelayController.h" // RelayState

class HysteresisEngine {
public:
    /**
     * @brief Evaluate all thresholds and update relay demand states.
     *
     * This is a pure control function: it reads sensor values and
     * config thresholds, then writes relay ON/OFF decisions into
     * `relays`.  It does NOT drive GPIO — that remains the sole
     * responsibility of RelayController::applyState().
     *
     * IMPORTANT: The caller (main.cpp / PriorityController) must
     * only invoke this method when user_override is NOT active.
     * When an override is active, relay state is dictated by the
     * last MQTT command, not by the hysteresis algorithm.
     *
     * @param temperature   Current DHT22 reading in °C.
     *                      Must NOT be NaN — the caller's FailSafe
     *                      layer is responsible for gating on NaN
     *                      before calling evaluate().
     * @param humidity      Current DHT22 reading in %RH. Same NaN
     *                      contract as temperature.
     * @param lux           Current BH1750 reading in lux.
     *                      Negative values are clamped to 0 by the
     *                      caller (SensorManager); treated as 0 here.
     * @param config        Active threshold config (read-only).
     * @param[out] relays   RelayState struct to mutate.  Only the
     *                      fields whose sensor crossed a threshold
     *                      are modified; dead-band values are left
     *                      unchanged to preserve hysteresis state.
     */
    void evaluate(float temperature,
                  float humidity,
                  float lux,
                  const TerrariumConfig& config,
                  RelayState& relays) const;
};