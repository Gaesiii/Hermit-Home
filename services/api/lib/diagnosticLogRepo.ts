import { ObjectId } from 'mongodb';
import { connectToDatabase } from './mongoClient';

const COLLECTION_NAME = 'diagnostic_logs';
const DEFAULT_ACK_TIMEOUT_MS = 12_000;
const DEVICE_KEYS = ['heater', 'mist', 'fan', 'light'] as const;

type DeviceKey = (typeof DEVICE_KEYS)[number];
type DiagnosticStatus = 'PASS' | 'FAIL' | 'PENDING' | 'INFO';
type DiagnosticCategory = 'COMMAND' | 'ACK' | 'TELEMETRY' | 'AI' | 'AUTH' | 'SYNC';
type DiagnosticSource = 'api' | 'mqtt-worker' | 'ai-agent' | 'auth' | 'system';

export type DiagnosticLogDocument = {
  _id?: ObjectId;
  deviceId: string | null;
  userId?: string | null;
  source: DiagnosticSource;
  category: DiagnosticCategory;
  status: DiagnosticStatus;
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

function getAckTimeoutMs(): number {
  const raw = process.env.EDGE_ACK_TIMEOUT_MS || '';
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed < 1_000) {
    return DEFAULT_ACK_TIMEOUT_MS;
  }
  return parsed;
}

export async function insertDiagnosticLog(
  payload: Omit<DiagnosticLogDocument, '_id' | 'createdAt' | 'updatedAt'>,
): Promise<void> {
  const { db } = await connectToDatabase();
  const now = new Date();
  const doc: DiagnosticLogDocument = {
    ...payload,
    createdAt: now,
    updatedAt: now,
  };
  await db.collection<DiagnosticLogDocument>(COLLECTION_NAME).insertOne(doc);
}

export async function insertCommandPendingLogs(params: {
  deviceId: string;
  userId: string | null;
  source: DiagnosticSource;
  stateUpdate: Record<string, boolean>;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  const entries = Object.entries(params.stateUpdate).filter(
    (entry): entry is [DeviceKey, boolean] => isDeviceKey(entry[0]),
  );
  if (entries.length === 0) {
    return;
  }

  const { db } = await connectToDatabase();
  const now = new Date();
  const ackDeadlineAt = new Date(now.getTime() + getAckTimeoutMs());
  const commandRef = `cmd-${now.getTime()}-${Math.random().toString(16).slice(2, 8)}`;

  const docs: DiagnosticLogDocument[] = entries.map(([relay, expectedState]) => ({
    deviceId: params.deviceId,
    userId: params.userId,
    source: params.source,
    category: 'COMMAND',
    status: 'PENDING',
    message: `[PENDING] Command (${relayLabel(relay)}=${stateLabel(expectedState)}) sent to API, awaiting Edge acknowledgment.`,
    relay,
    expectedState,
    commandRef,
    metadata: params.metadata,
    ackDeadlineAt,
    createdAt: now,
    updatedAt: now,
  }));

  if (docs.length > 0) {
    await db.collection<DiagnosticLogDocument>(COLLECTION_NAME).insertMany(docs);
  }
}

export async function expireTimedOutPendingCommands(): Promise<number> {
  const { db } = await connectToDatabase();
  const now = new Date();
  const collection = db.collection<DiagnosticLogDocument>(COLLECTION_NAME);

  const pending = await collection
    .find({
      status: 'PENDING',
      ackDeadlineAt: { $lte: now },
      relay: { $in: [...DEVICE_KEYS] },
      expectedState: { $in: [true, false] },
    })
    .limit(300)
    .toArray();

  if (pending.length === 0) {
    return 0;
  }

  const operations = pending
    .filter((entry) => entry._id && entry.relay !== undefined && typeof entry.expectedState === 'boolean')
    .map((entry) => ({
      updateOne: {
        filter: { _id: entry._id, status: 'PENDING' as const },
        update: {
          $set: {
            status: 'FAIL' as const,
            message: `[FAIL] Timeout: Command (${relayLabel(entry.relay!)}=${stateLabel(entry.expectedState!)}) reached API but was not acknowledged by Edge Device.`,
            resolvedAt: now,
            updatedAt: now,
          },
        },
      },
    }));

  if (operations.length === 0) {
    return 0;
  }

  const result = await collection.bulkWrite(operations, { ordered: false });
  return result.modifiedCount;
}

export async function listDiagnosticLogs(params: {
  limit: number;
  deviceId?: string;
}): Promise<DiagnosticLogDocument[]> {
  const { db } = await connectToDatabase();
  const collection = db.collection<DiagnosticLogDocument>(COLLECTION_NAME);

  const safeLimit = Math.min(Math.max(1, params.limit), 300);
  const filter: Record<string, unknown> = {};
  if (params.deviceId) {
    filter.deviceId = params.deviceId;
  }

  return collection.find(filter).sort({ createdAt: -1 }).limit(safeLimit).toArray();
}
