import { Collection, MongoServerError, ObjectId } from 'mongodb';
import bcrypt from 'bcryptjs';
import { connectToDatabase } from './mongoClient';

export interface UserDocument {
  _id?: ObjectId;
  email: string;
  passwordHash: string;
  createdAt: Date;
  updatedAt: Date;
}

export type PublicUser = Pick<UserDocument, '_id' | 'email' | 'createdAt'>;

const USERS_COLLECTION_NAME = 'users';
const EMAIL_UNIQUE_INDEX_NAME = 'email_unique';
const SALT_ROUNDS = 12;

type IndexLike = {
  name?: unknown;
  key?: unknown;
  unique?: unknown;
};

let usersIndexReadyPromise: Promise<void> | null = null;

function isUniqueEmailIndex(index: IndexLike): boolean {
  if (index.unique !== true) {
    return false;
  }

  const key = index.key;
  if (!key || typeof key !== 'object') {
    return false;
  }

  return (key as Record<string, unknown>).email === 1;
}

async function ensureUsersIndexes(collection: Collection<UserDocument>): Promise<void> {
  const existingIndexes = await collection.indexes();

  const namedIndex = existingIndexes.find(
    (index) => index.name === EMAIL_UNIQUE_INDEX_NAME,
  );

  if (namedIndex) {
    if (isUniqueEmailIndex(namedIndex)) {
      return;
    }

    throw new Error(
      `Invalid index definition for '${EMAIL_UNIQUE_INDEX_NAME}'. Expected unique index on { email: 1 }.`,
    );
  }

  const equivalentUniqueIndex = existingIndexes.find((index) => isUniqueEmailIndex(index));
  if (equivalentUniqueIndex) {
    return;
  }

  try {
    await collection.createIndex(
      { email: 1 },
      {
        unique: true,
        name: EMAIL_UNIQUE_INDEX_NAME,
        collation: { locale: 'en', strength: 2 },
      },
    );
  } catch (error: unknown) {
    if (
      error instanceof MongoServerError &&
      (error.code === 85 || error.code === 86)
    ) {
      const refreshedIndexes = await collection.indexes();
      if (refreshedIndexes.some((index) => isUniqueEmailIndex(index))) {
        return;
      }
    }

    throw error;
  }
}

async function ensureUsersIndexesOnce(collection: Collection<UserDocument>): Promise<void> {
  if (!usersIndexReadyPromise) {
    usersIndexReadyPromise = ensureUsersIndexes(collection);
  }

  try {
    await usersIndexReadyPromise;
  } catch (error: unknown) {
    usersIndexReadyPromise = null;
    throw error;
  }
}

export async function getUsersCollection(): Promise<Collection<UserDocument>> {
  const { db } = await connectToDatabase();
  const collection = db.collection<UserDocument>(USERS_COLLECTION_NAME);
  await ensureUsersIndexesOnce(collection);
  return collection;
}

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, SALT_ROUNDS);
}

export async function verifyPassword(
  plain: string,
  hash: string,
): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}

export function toPublicUser(user: UserDocument): PublicUser {
  return {
    _id: user._id,
    email: user.email,
    createdAt: user.createdAt,
  };
}
