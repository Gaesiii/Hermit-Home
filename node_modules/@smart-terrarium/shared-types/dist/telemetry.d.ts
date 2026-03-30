/**
 * Represents the physical state of the 4 actuators.
 */
export interface RelayState {
    heater: boolean;
    mist: boolean;
    fan: boolean;
    light: boolean;
}
/**
 * The exact JSON payload published by the ESP32 to the `terrarium/telemetry/{userId}` topic.
 */
export interface TelemetryPayload {
    temperature: number | null;
    humidity: number | null;
    lux: number;
    sensor_fault: boolean;
    user_override: boolean;
    relays: RelayState;
}
