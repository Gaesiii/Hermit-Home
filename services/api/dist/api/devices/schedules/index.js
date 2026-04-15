"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const http_1 = require("../../../lib/http");
function handler(req, res) {
    const allowedMethods = ['GET'];
    if ((0, http_1.handleApiPreflight)(req, res, allowedMethods)) {
        return;
    }
    if (req.method !== 'GET') {
        (0, http_1.methodNotAllowed)(req, res, allowedMethods);
        return;
    }
    res.status(501).json({
        error: 'Not implemented',
        message: 'Device schedule endpoints are not available yet.',
    });
}
