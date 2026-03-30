import { MongoClient, Db } from 'mongodb';
import { logger } from '../utils/logger';
import dotenv from 'dotenv';

dotenv.config();

const uri = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const dbName = process.env.MONGODB_DB_NAME || 'terrarium';

const client = new MongoClient(uri);

// Export the db instance so our repositories can use it
export let db: Db;

export async function connectDB(): Promise<void> {
  try {
    await client.connect();
    db = client.db(dbName);
    logger.info(`✅ Connected to MongoDB database: ${dbName}`);
  } catch (error) {
    logger.error({ err: error }, '❌ Failed to connect to MongoDB');
    process.exit(1); // Exit if we can't connect to the database
  }
}