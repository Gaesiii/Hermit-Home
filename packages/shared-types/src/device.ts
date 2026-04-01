import { RelayState } from './telemetry';

export type DeviceMode = 'AUTO' | 'MANUAL';

export interface DeviceStateRecord {
  deviceId: string;
  mode: DeviceMode;
  user_override: boolean;
  relays: RelayState;
  lastTelemetryAt: string | null;
  lastCommandAt: string | null;
  updatedAt: string;
}

export interface DeviceStatePatch {
  mode?: DeviceMode;
  user_override?: boolean;
  relays?: Partial<RelayState>;
}
