import { Db, MongoClient } from 'mongodb';
import dotenv from 'dotenv';
import { logger } from '../utils/logger';

dotenv.config();

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const dbName = process.env.MONGODB_DB_NAME || 'terrarium';
const maxPoolSize = Number.parseInt(process.env.MONGODB_MAX_POOL_SIZE || '10', 10);

const client = new MongoClient(uri, {
  maxPoolSize: Number.isFinite(maxPoolSize) ? maxPoolSize : 10,
  minPoolSize: 0,
  serverSelectionTimeoutMS: 5000,
});

let dbInstance: Db | null = null;
let connectionPromise: Promise<Db> | null = null;

export async function connectDB(): Promise<Db> {
  if (dbInstance) {
    return dbInstance;
  }

  if (!connectionPromise) {
    connectionPromise = client
      .connect()
      .then(() => {
        dbInstance = client.db(dbName);
        logger.info(`Connected to MongoDB database: ${dbName}`);
        return dbInstance;
      })
      .catch((error: unknown) => {
        connectionPromise = null;
        logger.error({ err: error }, 'Failed to connect to MongoDB');
        throw error;
      });
  }

  return connectionPromise;
}

export function getDb(): Db {
  if (!dbInstance) {
    throw new Error('MongoDB is not initialized. Call connectDB() before database access.');
  }
  return dbInstance;
}
