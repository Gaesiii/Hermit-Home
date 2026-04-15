"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const http_1 = require("../../lib/http");
function handler(req, res) {
    const allowedMethods = ['GET'];
    if ((0, http_1.handleApiPreflight)(req, res, allowedMethods)) {
        return;
    }
    if (req.method !== 'GET') {
        (0, http_1.methodNotAllowed)(req, res, allowedMethods);
        return;
    }
    res.status(200).json({
        success: true,
        message: 'Use /api/devices/{deviceId}/status, /api/devices/{deviceId}/override, /api/devices/{deviceId}/control, or /api/devices/{deviceId}',
    });
}
