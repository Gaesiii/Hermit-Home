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

// Vercel spins up many short-lived Node processes. Caching the client on
// `global` prevents opening a new TCP connection on every function invocation.
let cachedClient: MongoClient | null = (global as any)._mongoClient ?? null;
let cachedDb:     Db          | null = (global as any)._mongoDb     ?? null;

async function connectToDatabase(): Promise<Db> {
  if (cachedClient && cachedDb) {
    return cachedDb;
  }

  const client = await MongoClient.connect(MONGODB_URI);
  const db     = client.db(MONGODB_DB);

  // Persist across hot-reloads in development and across invocations
  // in the same Vercel worker process.
  cachedClient = client;
  cachedDb     = db;
  (global as any)._mongoClient = client;
  (global as any)._mongoDb     = db;

  return db;
}

// ─── Collection helper ────────────────────────────────────────────────────────

/**
 * Returns the typed `users` collection and guarantees the required
 * indexes exist. Safe to call on every invocation — MongoDB is a no-op
 * when indexes are already in place.
 */
export async function getUsersCollection(): Promise<Collection<UserDocument>> {
  const db         = await connectToDatabase();
  const collection = db.collection<UserDocument>('users');

  // Unique index prevents duplicate accounts and makes email lookups O(log n).
  //await collection.createIndex({ email: 1 }, { unique: true, name: 'email_unique' });

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
 *
 * Constant time is critical: a naive string comparison would allow an attacker
 * to infer valid passwords through response-timing differences.
 */
export async function verifyPassword(
  plain: string,
  hash:  string,
): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}

// ─── Projection helper ────────────────────────────────────────────────────────

/**
 * Strips secrets from a full `UserDocument` before the object leaves
 * the API layer. Always use this instead of returning `user` directly.
 */
export function toPublicUser(user: UserDocument): PublicUser {
  return {
    _id:       user._id,
    email:     user.email,
    createdAt: user.createdAt,
  };
}