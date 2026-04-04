import { MongoClient, Db, Collection, ObjectId } from 'mongodb';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';

dotenv.config();

// ─── Types ────────────────────────────────────────────────────────────────────

/**
 * The shape of a document stored in the `users` collection.
 * `passwordHash` is NEVER returned to the client.
 */
export interface UserDocument {
  _id?: ObjectId;
  email: string;
  passwordHash: string;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Safe subset returned to API callers — secrets are stripped.
 */
export type PublicUser = Pick<UserDocument, '_id' | 'email' | 'createdAt'>;

// ─── Connection (module-level singleton) ──────────────────────────────────────

const MONGODB_URI = process.env.MONGODB_URI ?? '';
const MONGODB_DB  = process.env.MONGODB_DB_NAME ?? 'hermit-home';

if (!MONGODB_URI) {
  throw new Error('Missing required environment variable: MONGODB_URI');
}

let cachedClient: MongoClient | null = (global as any)._mongoClient ?? null;
let cachedDb:     Db          | null = (global as any)._mongoDb     ?? null;

async function connectToDatabase(): Promise<Db> {
  if (cachedClient && cachedDb) {
    return cachedDb;
  }

  const client = await MongoClient.connect(MONGODB_URI);
  const db     = client.db(MONGODB_DB);

  cachedClient = client;
  cachedDb     = db;
  (global as any)._mongoClient = client;
  (global as any)._mongoDb     = db;

  return db;
}

// ─── Collection helper ────────────────────────────────────────────────────────

/**
 * Returns the typed `users` collection and guarantees the unique email index
 * exists on every invocation.
 *
 * createIndex is idempotent — MongoDB silently skips the operation when the
 * index already exists, so calling this on every request is safe and costs
 * only ~1 ms on warm connections.
 *
 * WHY THIS MUST NOT BE COMMENTED OUT:
 * The application-level duplicate check (findOne → insertOne) has an inherent
 * race condition. Two concurrent registrations with the same email can both
 * pass findOne before either insertOne runs, resulting in duplicate accounts.
 * The unique index is the only reliable, atomic guard against this scenario —
 * when the second insertOne fires, MongoDB rejects it with error code 11000,
 * which register.ts catches and maps to a 409 response.
 */
export async function getUsersCollection(): Promise<Collection<UserDocument>> {
  const db         = await connectToDatabase();
  const collection = db.collection<UserDocument>('users');

  // This is intentionally NOT commented out. See the comment above.
  await collection.createIndex(
    { email: 1 },
    { unique: true, name: 'email_unique' },
  );

  return collection;
}

// ─── Password helpers ─────────────────────────────────────────────────────────

const SALT_ROUNDS = 12; // ~250 ms on a modern CPU — good brute-force resistance

/**
 * Returns the bcrypt hash of a plain-text password.
 * Always call this before persisting any credential.
 */
export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, SALT_ROUNDS);
}

/**
 * Constant-time comparison of a plain-text password against a stored hash.
 * Returns `true` only when they match.
 */
export async function verifyPassword(
  plain: string,
  hash:  string,
): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}

// ─── Projection helper ────────────────────────────────────────────────────────

/**
 * Strips secrets from a full UserDocument before the object leaves the API layer.
 * Always use this instead of returning the raw document.
 */
export function toPublicUser(user: UserDocument): PublicUser {
  return {
    _id:       user._id,
    email:     user.email,
    createdAt: user.createdAt,
  };
}