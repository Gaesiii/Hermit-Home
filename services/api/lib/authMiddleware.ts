import { VercelRequest, VercelResponse } from '@vercel/node';
import * as admin from 'firebase-admin';

// ----------------------------------------------------------------
//  Firebase Admin SDK — singleton initialization
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
// ----------------------------------------------------------------
export async function verifyAuth(
  req: VercelRequest,
  res: VercelResponse
): Promise<string | null> {
  
  // ----------------------------------------------------------------
  // 🚪 CỬA NGÁCH CHO AI AGENT & POSTMAN (Server-to-Server)
  // ----------------------------------------------------------------
  const apiKey = req.headers['x-api-key'];
  if (apiKey && apiKey === process.env.SERVICE_API_KEY) {
    // Nếu đúng khóa bí mật, giả lập uid chính là deviceId để 
    // lọt qua được bước kiểm tra Ownership (uid === deviceId) ở route.
    const { deviceId } = req.query;
    return typeof deviceId === 'string' ? deviceId : 'service-account';
  }

  // ----------------------------------------------------------------
  // 🚪 CỬA CHÍNH DÀNH CHO NGƯỜI DÙNG (Firebase App)
  // ----------------------------------------------------------------
  const authHeader = req.headers['authorization'];

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      error: 'Unauthorized',
      message: 'Missing or malformed Authorization header. Expected: Bearer <token>',
    });
    return null;
  }

  const idToken = authHeader.split('Bearer ')[1].trim();

  if (!idToken) {
    res.status(401).json({ error: 'Unauthorized', message: 'Bearer token is empty.' });
    return null;
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    return decodedToken.uid;
  } catch (error: unknown) {
    const isExpired = error instanceof Error && error.message.includes('expired');
    res.status(401).json({
      error: 'Unauthorized',
      message: isExpired ? 'Token has expired.' : 'Invalid token.',
    });
    return null;
  }
}