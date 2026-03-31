import { VercelRequest, VercelResponse } from '@vercel/node';
import * as admin from 'firebase-admin';

// ----------------------------------------------------------------
//  Firebase Admin SDK — singleton initialization
//  Vercel may reuse the same Node.js isolate across warm invocations,
//  so we guard against calling initializeApp() more than once.
// ----------------------------------------------------------------
if (!admin.apps.length) {
  const serviceAccountKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY;

  if (!serviceAccountKey) {
    throw new Error(
      '[authMiddleware] FIREBASE_SERVICE_ACCOUNT_KEY environment variable is not set. ' +
      'Add the full JSON key string to your Vercel project environment variables.'
    );
  }

  try {
    const serviceAccount = JSON.parse(serviceAccountKey);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } catch {
    throw new Error(
      '[authMiddleware] Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY. ' +
      'Ensure it is a valid JSON string (not a file path).'
    );
  }
}

// ----------------------------------------------------------------
//  Authenticated request type
//  Extends VercelRequest so route handlers can access the verified
//  uid without casting or re-verifying.
// ----------------------------------------------------------------
export interface AuthenticatedRequest extends VercelRequest {
  uid: string;
}

// ----------------------------------------------------------------
//  verifyAuth()
//  Call this as the first line of any protected route handler.
//
//  Returns the authenticated uid on success.
//  Writes a 401 response and returns null on any failure —
//  the caller must return immediately when null is received.
//
//  Expected header format:
//    Authorization: Bearer <Firebase ID Token>
// ----------------------------------------------------------------
export async function verifyAuth(
  req: VercelRequest,
  res: VercelResponse
): Promise<string | null> {
  const authHeader = req.headers['authorization'];

  // Header must exist and follow the "Bearer <token>" format
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing or malformed Authorization header. Expected: Bearer <token>',
    });
    return null;
  }

  const idToken = authHeader.split('Bearer ')[1].trim();

  if (!idToken) {
    res.status(401).json({
      error: 'Unauthorized',
      message: 'Bearer token is empty.',
    });
    return null;
  }

  try {
    // Verifies the token signature, expiry, and audience against your
    // Firebase project. Throws if the token is invalid or expired.
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    return decodedToken.uid;
  } catch (error: unknown) {
    // Distinguish between an expired token and a completely invalid one
    // so the client knows whether to refresh or re-authenticate.
    const isExpired =
      error instanceof Error && error.message.includes('expired');

    res.status(401).json({
      error: 'Unauthorized',
      message: isExpired
        ? 'Token has expired. Please refresh and retry.'
        : 'Invalid token. Please re-authenticate.',
    });
    return null;
  }
}