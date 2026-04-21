import { ObjectId } from 'mongodb';
import { getDb } from './mongoClient';

const COLLECTION_NAME = 'diagnostic_logs';
const DEVICE_KEYS = ['heater', 'mist', 'fan', 'light'] as const;

type DeviceKey = (typeof DEVICE_KEYS)[number];

type DiagnosticLogDocument = {
  _id?: ObjectId;
  deviceId: string | null;
  userId?: string | null;
  source: 'api' | 'mqtt-worker' | 'ai-agent' | 'auth' | 'system';
  category: 'COMMAND' | 'ACK' | 'TELEMETRY' | 'AI' | 'AUTH' | 'SYNC';
  status: 'PASS' | 'FAIL' | 'PENDING' | 'INFO';
  message: string;
  relay?: DeviceKey;
  expectedState?: boolean;
  acknowledgedState?: boolean;
  commandRef?: string;
  metadata?: Record<string, unknown>;
  ackDeadlineAt?: Date;
  acknowledgedAt?: Date;
  resolvedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
};

function relayLabel(relay: DeviceKey): string {
  return relay.charAt(0).toUpperCase() + relay.slice(1);
}

function stateLabel(state: boolean): 'ON' | 'OFF' {
  return state ? 'ON' : 'OFF';
}

function isDeviceKey(value: string): value is DeviceKey {
  return (DEVICE_KEYS as readonly string[]).includes(value);
}

export async function insertDiagnosticLog(
  payload: Omit<DiagnosticLogDocument, '_id' | 'createdAt' | 'updatedAt'>
): Promise<void> {
  const now = new Date();
  const document: DiagnosticLogDocument = {
    ...payload,
    createdAt: now,
    updatedAt: now,
  };

  await getDb().collection<DiagnosticLogDocument>(COLLECTION_NAME).insertOne(document);
}

export async function acknowledgePendingCommand(params: {
  deviceId: string;
  relay: string;
  acknowledgedState: boolean;
}): Promise<boolean> {
  if (!isDeviceKey(params.relay)) {
    return false;
  }

  const now = new Date();
  const relay = params.relay;
  const collection = getDb().collection<DiagnosticLogDocument>(COLLECTION_NAME);

  const pending = await collection.findOne(
    {
      deviceId: params.deviceId,
      status: 'PENDING',
      relay,
      expectedState: params.acknowledgedState,
    },
    { sort: { createdAt: -1 } }
  );

  if (!pending?._id) {
    await insertDiagnosticLog({
      deviceId: params.deviceId,
      userId: null,
      source: 'mqtt-worker',
      category: 'ACK',
      status: 'INFO',
      message: `[INFO] Edge acknowledgment received without a matching pending command (${relayLabel(relay)}=${stateLabel(params.acknowledgedState)}).`,
      relay,
      acknowledgedState: params.acknowledgedState,
      metadata: {
        unmatchedAck: true,
      },
    });
    return false;
  }

  await collection.updateOne(
    { _id: pending._id, status: 'PENDING' },
    {
      $set: {
        source: 'mqtt-worker',
        category: 'ACK',
        status: 'PASS',
        message: `[PASS] Command (${relayLabel(relay)}=${stateLabel(params.acknowledgedState)}) acknowledged by Edge Device.`,
        acknowledgedState: params.acknowledgedState,
        acknowledgedAt: now,
        resolvedAt: now,
        updatedAt: now,
      },
    }
  );

  return true;
}
