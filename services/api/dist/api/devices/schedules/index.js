"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
function handler(_req, res) {
    res.status(501).json({
        error: 'Not implemented',
        message: 'Device schedule endpoints are not available yet.',
    });
}
