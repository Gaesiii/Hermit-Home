import { VercelRequest, VercelResponse } from '@vercel/node';
import * as admin from 'firebase-admin';
import jwt from 'jsonwebtoken';
import { insertDiagnosticLog } from './diagnosticLogRepo';

let firebaseInitialized = false;

export interface AuthenticatedRequest extends VercelRequest {
  user: {
    userId: string;
  };
}

type AuthenticatedHandler = (
  req: AuthenticatedRequest,
  res: VercelResponse
) => Promise<void> | void;

async function safeLogAuthEvent(params: {
  req: VercelRequest;
  status: 'PASS' | 'FAIL' | 'INFO';
  message: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  try {
    const deviceId = typeof params.req.query.deviceId === 'string' ? params.req.query.deviceId : null;
    await insertDiagnosticLog({
      deviceId,
      userId: null,
      source: 'auth',
      category: 'AUTH',
      status: params.status,
      message: params.message,
      metadata: {
        path: params.req.url || null,
        method: params.req.method || null,
        ...(params.metadata || {}),
      },
    });
  } catch {
    // Best-effort diagnostics only.
  }
}

function readHeaderValue(value: string | string[] | undefined): string | null {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0) {
    return value[0];
  }

  return null;
}

function ensureFirebaseInitialized(): void {
  if (firebaseInitialized || admin.apps.length > 0) {
    firebaseInitialized = true;
    return;
  }

  const serviceAccountKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;
  if (!serviceAccountKey) {
    throw new Error(
      '[authMiddleware] FIREBASE_SERVICE_ACCOUNT_KEY is required for Bearer-token authentication.'
    );
  }

  let serviceAccount: admin.ServiceAccount;
  try {
    serviceAccount = JSON.parse(serviceAccountKey) as admin.ServiceAccount;
  } catch {
    throw new Error(
      '[authMiddleware] FIREBASE_SERVICE_ACCOUNT_KEY must be a valid JSON string.'
    );
  }

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
  firebaseInitialized = true;
}

function verifyInternalJwtToken(token: string): string | null {
  const jwtSecret = process.env.JWT_SECRET || '';
  if (!jwtSecret) {
    return null;
  }

  const decoded = jwt.verify(token, jwtSecret) as jwt.JwtPayload | string;
  if (typeof decoded !== 'object' || decoded === null) {
    return null;
  }

  const userId = decoded.userId;
  return typeof userId === 'string' && userId.trim().length > 0 ? userId : null;
}

export async function verifyAuth(
  req: VercelRequest,
  res: VercelResponse
): Promise<string | null> {
  const providedApiKey = readHeaderValue(req.headers['x-api-key']);
  const expectedApiKey = process.env.SERVICE_API_KEY || '';

  if (providedApiKey) {
    if (expectedApiKey && providedApiKey === expectedApiKey) {
      const { deviceId } = req.query;
      await safeLogAuthEvent({
        req,
        status: 'PASS',
        message: '[PASS] Service API key validation succeeded.',
        metadata: { mode: 'service-api-key' },
      });
      return typeof deviceId === 'string' ? deviceId : 'service-account';
    }

    await safeLogAuthEvent({
      req,
      status: 'FAIL',
      message: '[FAIL] Service API key validation failed.',
      metadata: { mode: 'service-api-key' },
    });
    res.status(401).json({
      error: 'Unauthorized',
      message: 'Invalid service API key.',
    });
    return null;
  }

  const authHeader = readHeaderValue(req.headers.authorization);
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    await safeLogAuthEvent({
      req,
      status: 'FAIL',
      message: '[FAIL] Missing or malformed Authorization bearer token.',
      metadata: { mode: 'bearer' },
    });
    res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing Authorization header. Expected: Bearer <token>',
    });
    return null;
  }

  const idToken = authHeader.slice('Bearer '.length).trim();
  if (!idToken) {
    await safeLogAuthEvent({
      req,
      status: 'FAIL',
      message: '[FAIL] Bearer token is empty.',
      metadata: { mode: 'bearer' },
    });
    res.status(401).json({
      error: 'Unauthorized',
      message: 'Bearer token is empty.',
    });
    return null;
  }

  let firebaseError: unknown = null;
  try {
    if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
      ensureFirebaseInitialized();
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      await safeLogAuthEvent({
        req,
        status: 'PASS',
        message: '[PASS] Firebase token validation succeeded.',
        metadata: { mode: 'firebase' },
      });
      return decodedToken.uid;
    }
  } catch (error: unknown) {
    firebaseError = error;
  }

  try {
    const internalUserId = verifyInternalJwtToken(idToken);
    if (internalUserId) {
      await safeLogAuthEvent({
        req,
        status: 'PASS',
        message: '[PASS] Internal JWT token validation succeeded.',
        metadata: { mode: 'internal-jwt' },
      });
      return internalUserId;
    }
  } catch (error: unknown) {
    const isExpired =
      error instanceof Error && error.message.toLowerCase().includes('expired');

    await safeLogAuthEvent({
      req,
      status: 'FAIL',
      message: isExpired
        ? '[FAIL] Token validation failed: token expired.'
        : '[FAIL] Token validation failed: invalid token.',
      metadata: { mode: 'internal-jwt' },
    });
    res.status(401).json({
      error: 'Unauthorized',
      message: isExpired ? 'Token has expired.' : 'Invalid token.',
    });
    return null;
  }

  const firebaseTokenExpired =
    firebaseError instanceof Error &&
    firebaseError.message.toLowerCase().includes('expired');

  await safeLogAuthEvent({
    req,
    status: 'FAIL',
    message: firebaseTokenExpired
      ? '[FAIL] Firebase token validation failed: token expired.'
      : '[FAIL] Firebase token validation failed.',
    metadata: { mode: 'firebase' },
  });
  res.status(401).json({
    error: 'Unauthorized',
    message: firebaseTokenExpired ? 'Token has expired.' : 'Invalid token.',
  });
  return null;
}

export function withAuth(handler: AuthenticatedHandler) {
  return async (req: VercelRequest, res: VercelResponse): Promise<void> => {
    const userId = await verifyAuth(req, res);
    if (userId === null) {
      return;
    }

    const authenticatedReq = req as AuthenticatedRequest;
    authenticatedReq.user = { userId };
    await handler(authenticatedReq, res);
  }
}
