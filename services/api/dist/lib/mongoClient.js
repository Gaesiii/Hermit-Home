"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.connectToDatabase = connectToDatabase;
const mongodb_1 = require("mongodb");
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const MONGODB_URI = process.env.MONGODB_URI || '';
const MONGODB_DB = process.env.MONGODB_DB_NAME || 'hermit-home';
const MONGODB_MAX_POOL_SIZE = Number.parseInt(process.env.MONGODB_MAX_POOL_SIZE || '10', 10);
if (!MONGODB_URI) {
    throw new Error('Please define the MONGODB_URI environment variable');
}
const clientOptions = {
    maxPoolSize: Number.isFinite(MONGODB_MAX_POOL_SIZE) ? MONGODB_MAX_POOL_SIZE : 10,
    minPoolSize: 0,
    serverSelectionTimeoutMS: 5000,
};
const globalMongo = globalThis;
if (!globalMongo.mongoClientPromise) {
    const client = new mongodb_1.MongoClient(MONGODB_URI, clientOptions);
    globalMongo.mongoClientPromise = client.connect();
}
async function connectToDatabase() {
    if (globalMongo.mongoClient && globalMongo.mongoDb) {
        return { client: globalMongo.mongoClient, db: globalMongo.mongoDb };
    }
    const client = await globalMongo.mongoClientPromise;
    const db = client.db(MONGODB_DB);
    globalMongo.mongoClient = client;
    globalMongo.mongoDb = db;
    return { client, db };
}
