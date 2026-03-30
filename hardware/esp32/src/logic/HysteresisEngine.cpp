/**
 * ================================================================
 * @file    HysteresisEngine.cpp
 * @brief   Implementation of HysteresisEngine.
 * ================================================================
 */

#include "HysteresisEngine.h"

// ----------------------------------------------------------------
// evaluate
// ----------------------------------------------------------------
void HysteresisEngine::evaluate(float temperature,
                                float humidity,
                                float lux,
                                const TerrariumConfig& config,
                                RelayState& relays) const {

    // ---- Heater (temperature control) --------------------------
    // Crossed below the lower threshold → heat is needed.
    if      (temperature < config.tempMin) relays.heater = true;
    // Crossed above the upper threshold → too hot, cut heat.
    else if (temperature > config.tempMax) relays.heater = false;
    // Inside dead-band [tempMin, tempMax] → preserve last state.

    // ---- Mist (humidity control) --------------------------------
    if      (humidity < config.humMin) relays.mist = true;
    else if (humidity > config.humMax) relays.mist = false;

    // ---- Light (lux control) ------------------------------------
    if      (lux < config.luxMin) relays.light = true;
    else if (lux > config.luxMax) relays.light = false;

    // ---- Fan (unconditional) ------------------------------------
    // The original sketch always sets fan = true inside
    // applyHysteresis().  This is preserved verbatim.
    // A future PriorityController command can still override it.
    relays.fan = true;

    Serial.printf(
        "[Hysteresis] T=%.1f°C(%.1f-%.1f) H=%.1f%%(%.1f-%.1f) "
        "Lux=%.0f(%.0f-%.0f) → Heater:%d Mist:%d Fan:%d Light:%d\n",
        temperature, config.tempMin, config.tempMax,
        humidity,    config.humMin,  config.humMax,
        lux,         config.luxMin,  config.luxMax,
        relays.heater, relays.mist, relays.fan, relays.light
    );
}