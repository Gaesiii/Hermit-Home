"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const mqttPublisher_1 = require("../../../lib/mqttPublisher");
async function handler(req, res) {
    if (req.method !== 'POST')
        return res.status(405).end();
    const { deviceId } = req.query;
    const command = req.body;
    if (!deviceId || typeof deviceId !== 'string') {
        return res.status(400).json({ error: 'Device ID is required' });
    }
    try {
        // Gửi lệnh xuống ESP32 qua HiveMQ
        await (0, mqttPublisher_1.publishCommand)(deviceId, command);
        return res.status(200).json({
            success: true,
            device: deviceId,
            message: 'Override command sent'
        });
    }
    catch (error) {
        console.error('MQTT Error:', error);
        return res.status(500).json({ error: 'Failed to communicate with device' });
    }
}
