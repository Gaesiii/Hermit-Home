import { MongoClient } from 'mongodb';
import dotenv from 'dotenv';
import path from 'path';

// Load biến môi trường từ file .env ở thư mục gốc
dotenv.config({ path: path.join(__dirname, '../.env') });

const MONGODB_URI = process.env.MONGODB_URI as string;
const MONGODB_DB_NAME = process.env.MONGODB_DB_NAME || 'hermit-home';

if (!MONGODB_URI) {
    console.error("❌ Lỗi: Chưa cấu hình MONGODB_URI trong file .env");
    process.exit(1);
}

const USER_JSON_SCHEMA = {
    bsonType: "object",
    required: ["email", "passwordHash", "createdAt", "updatedAt"],
    additionalProperties: false,
    properties: {
        _id: { bsonType: "objectId" },
        email: { bsonType: "string", description: "Bắt buộc là chuỗi" },
        passwordHash: { bsonType: "string", description: "Bắt buộc là chuỗi" },
        resetToken: { bsonType: "string" },
        tokenExpiry: { bsonType: "date" },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" }
    }
};

async function run() {
    console.log(`⏳ Đang kết nối tới MongoDB...`);
    const client = new MongoClient(MONGODB_URI);

    try {
        await client.connect();
        const db = client.db(MONGODB_DB_NAME);
        console.log(`✅ Đã kết nối tới DB: ${MONGODB_DB_NAME}`);

        const collections = await db.listCollections({ name: 'users' }).toArray();
        
        if (collections.length === 0) {
            console.log(`📁 Đang tạo collection "users"...`);
            await db.createCollection('users', {
                validator: { $jsonSchema: USER_JSON_SCHEMA },
                validationLevel: "strict",
                validationAction: "error"
            });
            console.log(`✅ Đã tạo collection.`);
        } else {
            console.log(`📁 Collection "users" đã tồn tại. Cập nhật schema...`);
            await db.command({
                collMod: "users",
                validator: { $jsonSchema: USER_JSON_SCHEMA },
                validationLevel: "strict",
                validationAction: "error"
            });
            console.log(`✅ Schema đã cập nhật.`);
        }

        console.log(`🔑 Đang tạo unique index cho "email"...`);
        await db.collection('users').createIndex(
            { email: 1 }, 
            { unique: true, name: "email_unique", collation: { locale: 'en', strength: 2 } }
        );
        console.log(`✅ Index hoàn tất.`);

        console.log(`🎉 Khởi tạo hoàn tất!`);
    } catch (error) {
        console.error(`❌ Lỗi:`, error);
    } finally {
        await client.close();
    }
}

run();