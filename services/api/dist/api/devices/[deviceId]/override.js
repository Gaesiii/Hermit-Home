"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const mqttPublisher_1 = require("../../../lib/mqttPublisher");
const authMiddleware_1 = require("../../../lib/authMiddleware");
async function handler(req, res) {
    if (req.method !== 'POST')
        return res.status(405).end();
    // ----------------------------------------------------------------
    //  Auth gate — SEV-1 fix
    //  verifyAuth() returns null and writes the 401 response itself.
    //  We must return immediately on null so the rest of the handler
    //  never executes with an unauthenticated request.
    // ----------------------------------------------------------------
    const uid = await (0, authMiddleware_1.verifyAuth)(req, res);
    if (uid === null)
        return;
    const { deviceId } = req.query;
    const command = req.body;
    if (!deviceId || typeof deviceId !== 'string') {
        return res.status(400).json({ error: 'Device ID is required' });
    }
    // ----------------------------------------------------------------
    //  Ownership check
    //  The authenticated uid must match the deviceId being commanded.
    //  This prevents a legitimate user from sending relay commands
    //  to another user's device — even with a valid token.
    // ----------------------------------------------------------------
    if (uid !== deviceId) {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'You do not have permission to control this device.',
        });
    }
    try {
        await (0, mqttPublisher_1.publishCommand)(deviceId, command);
        return res.status(200).json({
            success: true,
            device: deviceId,
            message: 'Override command sent',
        });
    }
    catch (error) {
        console.error('MQTT Error:', error);
        return res.status(500).json({ error: 'Failed to communicate with device' });
    }
}
