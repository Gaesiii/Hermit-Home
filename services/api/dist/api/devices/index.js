"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const mongoClient_1 = require("../../lib/mongoClient");
const deviceRepository_1 = require("../../lib/deviceRepository");
async function handler(req, res) {
    if (req.method !== 'GET') {
        return res.status(405).json({ error: 'Method not allowed' });
    }
    try {
        const { db } = await (0, mongoClient_1.connectToDatabase)();
        const devices = await (0, deviceRepository_1.listDevices)(db);
        return res.status(200).json(devices);
    }
    catch (error) {
        return res.status(500).json({ error: error.message });
    }
}
