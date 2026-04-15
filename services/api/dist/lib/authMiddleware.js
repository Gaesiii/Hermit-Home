"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.verifyAuth = verifyAuth;
exports.withAuth = withAuth;
const admin = __importStar(require("firebase-admin"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
let firebaseInitialized = false;
function readHeaderValue(value) {
    if (typeof value === 'string') {
        return value;
    }
    if (Array.isArray(value) && value.length > 0) {
        return value[0];
    }
    return null;
}
function ensureFirebaseInitialized() {
    if (firebaseInitialized || admin.apps.length > 0) {
        firebaseInitialized = true;
        return;
    }
    const serviceAccountKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
    if (!serviceAccountKey) {
        throw new Error('[authMiddleware] FIREBASE_SERVICE_ACCOUNT_KEY is required for Bearer-token authentication.');
    }
    let serviceAccount;
    try {
        serviceAccount = JSON.parse(serviceAccountKey);
    }
    catch {
        throw new Error('[authMiddleware] FIREBASE_SERVICE_ACCOUNT_KEY must be a valid JSON string.');
    }
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
    });
    firebaseInitialized = true;
}
function verifyInternalJwtToken(token) {
    const jwtSecret = process.env.JWT_SECRET || '';
    if (!jwtSecret) {
        return null;
    }
    const decoded = jsonwebtoken_1.default.verify(token, jwtSecret);
    if (typeof decoded !== 'object' || decoded === null) {
        return null;
    }
    const userId = decoded.userId;
    return typeof userId === 'string' && userId.trim().length > 0 ? userId : null;
}
async function verifyAuth(req, res) {
    const providedApiKey = readHeaderValue(req.headers['x-api-key']);
    const expectedApiKey = process.env.SERVICE_API_KEY || '';
    if (providedApiKey) {
        if (expectedApiKey && providedApiKey === expectedApiKey) {
            const { deviceId } = req.query;
            return typeof deviceId === 'string' ? deviceId : 'service-account';
        }
        res.status(401).json({
            error: 'Unauthorized',
            message: 'Invalid service API key.',
        });
        return null;
    }
    const authHeader = readHeaderValue(req.headers.authorization);
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        res.status(401).json({
            error: 'Unauthorized',
            message: 'Missing Authorization header. Expected: Bearer <token>',
        });
        return null;
    }
    const idToken = authHeader.slice('Bearer '.length).trim();
    if (!idToken) {
        res.status(401).json({
            error: 'Unauthorized',
            message: 'Bearer token is empty.',
        });
        return null;
    }
    let firebaseError = null;
    try {
        if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
            ensureFirebaseInitialized();
            const decodedToken = await admin.auth().verifyIdToken(idToken);
            return decodedToken.uid;
        }
    }
    catch (error) {
        firebaseError = error;
    }
    try {
        const internalUserId = verifyInternalJwtToken(idToken);
        if (internalUserId) {
            return internalUserId;
        }
    }
    catch (error) {
        const isExpired = error instanceof Error && error.message.toLowerCase().includes('expired');
        res.status(401).json({
            error: 'Unauthorized',
            message: isExpired ? 'Token has expired.' : 'Invalid token.',
        });
        return null;
    }
    const firebaseTokenExpired = firebaseError instanceof Error &&
        firebaseError.message.toLowerCase().includes('expired');
    res.status(401).json({
        error: 'Unauthorized',
        message: firebaseTokenExpired ? 'Token has expired.' : 'Invalid token.',
    });
    return null;
}
function withAuth(handler) {
    return async (req, res) => {
        const userId = await verifyAuth(req, res);
        if (userId === null) {
            return;
        }
        const authenticatedReq = req;
        authenticatedReq.user = { userId };
        await handler(authenticatedReq, res);
    };
}
