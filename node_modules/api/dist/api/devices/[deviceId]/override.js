"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const mqttPublisher_1 = require("../../../lib/mqttPublisher");
const mongoClient_1 = require("../../../lib/mongoClient");
const deviceRepository_1 = require("../../../lib/deviceRepository");
async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
    }
    const { deviceId } = req.query;
    const command = req.body;
    if (!deviceId || typeof deviceId !== 'string') {
        return res.status(400).json({ error: 'Device ID is required' });
    }
    try {
        // Gửi lệnh xuống ESP32 qua HiveMQ
        await (0, mqttPublisher_1.publishCommand)(deviceId, command);
        const { db } = await (0, mongoClient_1.connectToDatabase)();
        await (0, deviceRepository_1.markCommandSent)(db, deviceId, {
            mode: command.user_override ? 'MANUAL' : 'AUTO',
            user_override: command.user_override,
            relays: command.devices
        });
        return res.status(200).json({
            success: true,
            device: deviceId,
            message: 'Override command sent'
        });
    }
    catch (error) {
        return res.status(500).json({ error: 'Failed to communicate with device' });
    }
}
