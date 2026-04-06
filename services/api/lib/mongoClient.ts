import { Db, MongoClient, MongoClientOptions } from 'mongodb';
import dotenv from 'dotenv';

dotenv.config();

const MONGODB_URI = process.env.MONGODB_URI || '';
const MONGODB_DB = process.env.MONGODB_DB_NAME || 'hermit-home';
const MONGODB_MAX_POOL_SIZE = Number.parseInt(process.env.MONGODB_MAX_POOL_SIZE || '10', 10);

if (!MONGODB_URI) {
  throw new Error('Please define the MONGODB_URI environment variable');
}

const clientOptions: MongoClientOptions = {
  maxPoolSize: Number.isFinite(MONGODB_MAX_POOL_SIZE) ? MONGODB_MAX_POOL_SIZE : 10,
  minPoolSize: 0,
  serverSelectionTimeoutMS: 5000,
};

declare global {
  // eslint-disable-next-line no-var
  var mongoClientPromise: Promise<MongoClient> | undefined;
  // eslint-disable-next-line no-var
  var mongoClient: MongoClient | undefined;
  // eslint-disable-next-line no-var
  var mongoDb: Db | undefined;
}

const globalMongo = globalThis as typeof globalThis & {
  mongoClientPromise?: Promise<MongoClient>;
  mongoClient?: MongoClient;
  mongoDb?: Db;
};

if (!globalMongo.mongoClientPromise) {
  const client = new MongoClient(MONGODB_URI, clientOptions);
  globalMongo.mongoClientPromise = client.connect();
}

export async function connectToDatabase(): Promise<{ client: MongoClient; db: Db }> {
  if (globalMongo.mongoClient && globalMongo.mongoDb) {
    return { client: globalMongo.mongoClient, db: globalMongo.mongoDb };
  }

  const client = await globalMongo.mongoClientPromise!;
  const db = client.db(MONGODB_DB);

  globalMongo.mongoClient = client;
  globalMongo.mongoDb = db;

  return { client, db };
}
