"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const mongoClient_1 = require("../../../lib/mongoClient");
async function handler(req, res) {
    if (req.method !== 'GET')
        return res.status(405).end();
    // Vercel tự động bóc tách [deviceId] từ URL
    const { deviceId } = req.query;
    if (!deviceId || typeof deviceId !== 'string') {
        return res.status(400).json({ error: 'Device ID is required' });
    }
    try {
        const { db } = await (0, mongoClient_1.connectToDatabase)();
        // Tìm bản ghi telemetry mới nhất của thiết bị này
        // Lưu ý: userId trong DB chính là deviceId của ESP32
        const latest = await db.collection('telemetry')
            .find({ userId: deviceId })
            .sort({ timestamp: -1 })
            .limit(1)
            .toArray();
        if (latest.length === 0) {
            return res.status(404).json({ error: 'No data found for this device' });
        }
        return res.status(200).json(latest[0]);
    }
    catch (error) {
        return res.status(500).json({ error: 'Database connection failed' });
    }
}
