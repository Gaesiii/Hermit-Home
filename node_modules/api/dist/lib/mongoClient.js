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
if (!MONGODB_URI) {
    throw new Error('Please define the MONGODB_URI environment variable');
}
/**
 * Global is used here to maintain a cached connection across hot reloads
 * in development and serverless function invocations in production.
 */
let cachedClient = global.mongoClient || null;
let cachedDb = global.mongoDb || null;
async function connectToDatabase() {
    if (cachedClient && cachedDb) {
        return { client: cachedClient, db: cachedDb };
    }
    const client = await mongodb_1.MongoClient.connect(MONGODB_URI);
    const db = client.db(MONGODB_DB);
    cachedClient = client;
    cachedDb = db;
    global.mongoClient = client;
    global.mongoDb = db;
    return { client, db };
}
