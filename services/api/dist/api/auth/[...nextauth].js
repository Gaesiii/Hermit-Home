"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = handler;
const http_1 = require("../../lib/http");
function handler(req, res) {
    if ((0, http_1.handleApiPreflight)(req, res, ['GET', 'POST'])) {
        return;
    }
    res.status(501).json({
        error: 'Not implemented',
        message: 'Authentication route is not configured yet.',
    });
}
