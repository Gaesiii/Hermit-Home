/**
 * ================================================================
 * @file    PrefsStore.cpp
 * @brief   Implementation of PrefsStore.
 * ================================================================
 */

#include "PrefsStore.h"

// NVS namespace shared by both methods.
// 15-character limit imposed by the ESP-IDF NVS subsystem.
static constexpr char kNamespace[] = "terrarium";

// NVS key strings — defined once here so a future rename touches
// exactly one place. Each string must stay ≤ 15 characters.
static constexpr char kKeyTempMin[] = "tempMin";
static constexpr char kKeyTempMax[] = "tempMax";
static constexpr char kKeyHumMin[]  = "humMin";
static constexpr char kKeyHumMax[]  = "humMax";
static constexpr char kKeyLuxMin[]  = "luxMin";
static constexpr char kKeyLuxMax[]  = "luxMax";

// ----------------------------------------------------------------
// loadConfig
// ----------------------------------------------------------------
void PrefsStore::loadConfig(TerrariumConfig& config) {
    // readOnly = true  →  no wear on flash; fails gracefully if the
    // namespace doesn't exist yet (getFloat returns the default arg).
    _prefs.begin(kNamespace, /*readOnly=*/true);

    // Each getFloat call uses the struct's current member as the
    // second argument (the fallback default). This preserves the
    // compile-time defaults on a virgin device while restoring
    // previously saved values on warm reboots — identical behaviour
    // to the original loadConfigFromFlash().
    config.tempMin = _prefs.getFloat(kKeyTempMin, config.tempMin);
    config.tempMax = _prefs.getFloat(kKeyTempMax, config.tempMax);
    config.humMin  = _prefs.getFloat(kKeyHumMin,  config.humMin);
    config.humMax  = _prefs.getFloat(kKeyHumMax,  config.humMax);
    config.luxMin  = _prefs.getFloat(kKeyLuxMin,  config.luxMin);
    config.luxMax  = _prefs.getFloat(kKeyLuxMax,  config.luxMax);

    // version_ts is intentionally not loaded — it is a runtime
    // field stamped by the MQTT command handler, not a persisted one.

    _prefs.end();

    Serial.printf(
        "[PrefsStore] Config loaded — "
        "T[%.1f–%.1f°C]  H[%.1f–%.1f%%]  Lux[%.0f–%.0f]\n",
        config.tempMin, config.tempMax,
        config.humMin,  config.humMax,
        config.luxMin,  config.luxMax
    );
}

// ----------------------------------------------------------------
// saveConfig
// ----------------------------------------------------------------
void PrefsStore::saveConfig(const TerrariumConfig& config) {
    // readOnly = false  →  opens (or creates) the namespace for writing.
    _prefs.begin(kNamespace, /*readOnly=*/false);

    _prefs.putFloat(kKeyTempMin, config.tempMin);
    _prefs.putFloat(kKeyTempMax, config.tempMax);
    _prefs.putFloat(kKeyHumMin,  config.humMin);
    _prefs.putFloat(kKeyHumMax,  config.humMax);
    _prefs.putFloat(kKeyLuxMin,  config.luxMin);
    _prefs.putFloat(kKeyLuxMax,  config.luxMax);

    // version_ts intentionally omitted — see header note.

    _prefs.end();

    Serial.printf(
        "[PrefsStore] Config saved  — "
        "T[%.1f–%.1f°C]  H[%.1f–%.1f%%]  Lux[%.0f–%.0f]\n",
        config.tempMin, config.tempMax,
        config.humMin,  config.humMax,
        config.luxMin,  config.luxMax
    );
}