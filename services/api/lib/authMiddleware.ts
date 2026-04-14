import { VercelRequest, VercelResponse } from '@vercel/node';
import * as admin from 'firebase-admin';

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

export async function verifyAuth(
  req: VercelRequest,
  res: VercelResponse
): Promise<string | null> {
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

  try {
    ensureFirebaseInitialized();
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    return decodedToken.uid;
  } catch (error: unknown) {
    const isExpired =
      error instanceof Error && error.message.toLowerCase().includes('expired');

    res.status(401).json({
      error: 'Unauthorized',
      message: isExpired ? 'Token has expired.' : 'Invalid token.',
    });
    return null;
  }
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
  };
}
