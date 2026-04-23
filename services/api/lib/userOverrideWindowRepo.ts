import { ObjectId } from 'mongodb';
import { connectToDatabase } from './mongoClient';

const COLLECTION_NAME = 'user_override_windows';
const DEFAULT_USER_OVERRIDE_GRACE_SECONDS = 300;
const MIN_USER_OVERRIDE_GRACE_SECONDS = 30;
const MAX_USER_OVERRIDE_GRACE_SECONDS = 3600;

export type UserOverrideWindowDocument = {
  _id?: ObjectId;
  deviceId: string;
  userId: string;
  active: boolean;
  startedAt: Date;
  expiresAt: Date;
  activatedBy: 'control' | 'override';
  clearedAt?: Date;
  clearReason?: string;
  createdAt: Date;
  updatedAt: Date;
};

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function getUserOverrideGraceSeconds(): number {
  const parsed = Number.parseInt(process.env.USER_OVERRIDE_GRACE_SECONDS || '', 10);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_USER_OVERRIDE_GRACE_SECONDS;
  }

  return clamp(parsed, MIN_USER_OVERRIDE_GRACE_SECONDS, MAX_USER_OVERRIDE_GRACE_SECONDS);
}

export async function startUserOverrideWindow(params: {
  deviceId: string;
  userId: string;
  activatedBy: 'control' | 'override';
}): Promise<UserOverrideWindowDocument> {
  const { db } = await connectToDatabase();
  const now = new Date();
  const graceSeconds = getUserOverrideGraceSeconds();
  const expiresAt = new Date(now.getTime() + graceSeconds * 1000);

  await db.collection<UserOverrideWindowDocument>(COLLECTION_NAME).updateOne(
    { deviceId: params.deviceId },
    {
      $set: {
        deviceId: params.deviceId,
        userId: params.userId,
        active: true,
        startedAt: now,
        expiresAt,
        activatedBy: params.activatedBy,
        updatedAt: now,
      },
      $unset: {
        clearedAt: '',
        clearReason: '',
      },
      $setOnInsert: {
        createdAt: now,
      },
    },
    { upsert: true },
  );

  return {
    deviceId: params.deviceId,
    userId: params.userId,
    active: true,
    startedAt: now,
    expiresAt,
    activatedBy: params.activatedBy,
    createdAt: now,
    updatedAt: now,
  };
}

export async function getActiveUserOverrideWindow(
  deviceId: string,
): Promise<UserOverrideWindowDocument | null> {
  const { db } = await connectToDatabase();
  const now = new Date();

  const active = await db
    .collection<UserOverrideWindowDocument>(COLLECTION_NAME)
    .findOne({
      deviceId,
      active: true,
      expiresAt: { $gt: now },
    });

  if (active) {
    return active;
  }

  await db.collection<UserOverrideWindowDocument>(COLLECTION_NAME).updateOne(
    {
      deviceId,
      active: true,
      expiresAt: { $lte: now },
    },
    {
      $set: {
        active: false,
        clearedAt: now,
        clearReason: 'expired',
        updatedAt: now,
      },
    },
  );

  return null;
}

export async function clearUserOverrideWindow(
  deviceId: string,
  reason: string,
): Promise<boolean> {
  const { db } = await connectToDatabase();
  const now = new Date();
  const result = await db.collection<UserOverrideWindowDocument>(COLLECTION_NAME).updateOne(
    {
      deviceId,
      active: true,
    },
    {
      $set: {
        active: false,
        clearedAt: now,
        clearReason: reason.slice(0, 200),
        updatedAt: now,
      },
    },
  );

  return result.modifiedCount > 0;
}
