import crypto from 'crypto';
import { Collection, MongoServerError, ObjectId } from 'mongodb';
import { connectToDatabase } from './mongoClient';

const PASSWORD_RESET_COLLECTION_NAME = 'password_reset_tokens';
const TOKEN_HASH_UNIQUE_INDEX_NAME = 'token_hash_unique';
const EXPIRES_AT_TTL_INDEX_NAME = 'expires_at_ttl';
const USER_LOOKUP_INDEX_NAME = 'user_lookup_created_at';

export interface PasswordResetTokenDocument {
  _id?: ObjectId;
  userId: ObjectId;
  email: string;
  tokenHash: string;
  createdAt: Date;
  expiresAt: Date;
  usedAt: Date | null;
  requestedIp: string | null;
  requestedUserAgent: string | null;
}

type IndexLike = {
  name?: unknown;
};

let passwordResetIndexesReadyPromise: Promise<void> | null = null;

function hasIndexNamed(indexes: IndexLike[], expectedName: string): boolean {
  return indexes.some((index) => index.name === expectedName);
}

async function ensurePasswordResetIndexes(
  collection: Collection<PasswordResetTokenDocument>,
): Promise<void> {
  let existingIndexes: IndexLike[] = [];
  try {
    existingIndexes = await collection.indexes();
  } catch (error: unknown) {
    if (!(error instanceof MongoServerError) || error.code !== 26) {
      throw error;
    }
    // NamespaceNotFound means the collection does not exist yet.
    // MongoDB will create it automatically when indexes/documents are created.
    existingIndexes = [];
  }

  if (!hasIndexNamed(existingIndexes, TOKEN_HASH_UNIQUE_INDEX_NAME)) {
    await collection.createIndex(
      { tokenHash: 1 },
      {
        name: TOKEN_HASH_UNIQUE_INDEX_NAME,
        unique: true,
      },
    );
  }

  if (!hasIndexNamed(existingIndexes, EXPIRES_AT_TTL_INDEX_NAME)) {
    await collection.createIndex(
      { expiresAt: 1 },
      {
        name: EXPIRES_AT_TTL_INDEX_NAME,
        expireAfterSeconds: 0,
      },
    );
  }

  if (!hasIndexNamed(existingIndexes, USER_LOOKUP_INDEX_NAME)) {
    await collection.createIndex(
      { userId: 1, createdAt: -1 },
      {
        name: USER_LOOKUP_INDEX_NAME,
      },
    );
  }
}

async function ensurePasswordResetIndexesOnce(
  collection: Collection<PasswordResetTokenDocument>,
): Promise<void> {
  if (!passwordResetIndexesReadyPromise) {
    passwordResetIndexesReadyPromise = ensurePasswordResetIndexes(collection);
  }

  try {
    await passwordResetIndexesReadyPromise;
  } catch (error: unknown) {
    passwordResetIndexesReadyPromise = null;
    throw error;
  }
}

async function getPasswordResetCollection(): Promise<Collection<PasswordResetTokenDocument>> {
  const { db } = await connectToDatabase();
  const collection = db.collection<PasswordResetTokenDocument>(PASSWORD_RESET_COLLECTION_NAME);
  await ensurePasswordResetIndexesOnce(collection);
  return collection;
}

export function hashPasswordResetToken(rawToken: string): string {
  return crypto.createHash('sha256').update(rawToken).digest('hex');
}

function generatePasswordResetToken(): string {
  return crypto.randomBytes(32).toString('base64url');
}

export async function createPasswordResetToken(params: {
  userId: ObjectId;
  email: string;
  tokenTtlMinutes: number;
  requestedIp: string | null;
  requestedUserAgent: string | null;
}): Promise<{ rawToken: string; expiresAt: Date }> {
  const collection = await getPasswordResetCollection();
  const rawToken = generatePasswordResetToken();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + params.tokenTtlMinutes * 60 * 1000);

  await collection.insertOne({
    userId: params.userId,
    email: params.email,
    tokenHash: hashPasswordResetToken(rawToken),
    createdAt: now,
    expiresAt,
    usedAt: null,
    requestedIp: params.requestedIp,
    requestedUserAgent: params.requestedUserAgent,
  });

  return { rawToken, expiresAt };
}

export async function consumePasswordResetToken(
  rawToken: string,
): Promise<PasswordResetTokenDocument | null> {
  const collection = await getPasswordResetCollection();
  const now = new Date();
  const tokenHash = hashPasswordResetToken(rawToken);

  const result = await collection.findOneAndUpdate(
    {
      tokenHash,
      usedAt: null,
      expiresAt: { $gt: now },
    },
    {
      $set: { usedAt: now },
    },
    {
      returnDocument: 'before',
    },
  );

  return result;
}

export async function findPasswordResetToken(
  rawToken: string,
): Promise<PasswordResetTokenDocument | null> {
  const collection = await getPasswordResetCollection();
  const tokenHash = hashPasswordResetToken(rawToken);

  return collection.findOne({ tokenHash });
}

export async function invalidateAllPasswordResetTokensForUser(userId: ObjectId): Promise<void> {
  const collection = await getPasswordResetCollection();
  await collection.updateMany(
    {
      userId,
      usedAt: null,
    },
    {
      $set: { usedAt: new Date() },
    },
  );
}
