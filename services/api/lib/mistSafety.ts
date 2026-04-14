import { CommandPayload, DeviceStatePatch, RelayState } from '@smart-terrarium/shared-types';

// Temporary safety lock while mist hardware is faulty.
// Set to false after hardware replacement.
export const MIST_SAFETY_LOCK_ENABLED = true;

export function sanitizeRelayMap<T extends Partial<RelayState> | undefined>(relays: T): T {
  if (!MIST_SAFETY_LOCK_ENABLED || !relays) {
    return relays;
  }

  return {
    ...relays,
    mist: false,
  } as T;
}

export function sanitizeCommandPayload(payload: CommandPayload): CommandPayload {
  if (!MIST_SAFETY_LOCK_ENABLED) {
    return payload;
  }

  return {
    ...payload,
    devices: sanitizeRelayMap(payload.devices),
  };
}

export function sanitizeDeviceStatePatch(patch: DeviceStatePatch): DeviceStatePatch {
  if (!MIST_SAFETY_LOCK_ENABLED) {
    return patch;
  }

  return {
    ...patch,
    relays: sanitizeRelayMap(patch.relays),
  };
}
