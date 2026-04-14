"use strict";
// lib/authMiddleware.ts
//
// HOW IT WORKS
// ─────────────────────────────────────────────────────────────────────────────
// `withAuth` is a higher-order function (HOF) that wraps any Vercel handler.
// On every invocation it:
//   1. Pulls the raw JWT out of the Authorization header.
//   2. Verifies the signature and expiry against JWT_SECRET.
//   3. Casts the verified payload to JwtPayload and attaches it to the request
//      as `req.user` so downstream handlers have typed access.
//   4. Calls the original handler only if all the above succeeded.
//
// If anything goes wrong the HOF short-circuits with a 401 and the real
// handler is never invoked.
// ─────────────────────────────────────────────────────────────────────────────
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.withAuth = withAuth;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
// ─── Environment validation ───────────────────────────────────────────────────
//
// Fail loudly at module load time rather than silently returning wrong 401s
// at runtime. Vercel will surface this as a deployment-time error.
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
    throw new Error('[authMiddleware] Missing required environment variable: JWT_SECRET');
}
// ─── Helper ───────────────────────────────────────────────────────────────────
/**
 * Extracts the raw token string from an `Authorization: Bearer <token>` header.
 * Returns `null` for any header that is absent or does not start with "Bearer ".
 */
function extractBearerToken(req) {
    const header = req.headers.authorization;
    // Must be a non-empty string that starts with exactly "Bearer " (7 chars).
    if (!header || !header.startsWith('Bearer ')) {
        return null;
    }
    // Slice off the prefix and trim any accidental whitespace.
    const token = header.slice(7).trim();
    // Reject an empty string left behind after slicing (e.g. "Bearer   ").
    return token.length > 0 ? token : null;
}
// ─── Core middleware ──────────────────────────────────────────────────────────
/**
 * Higher-order function that wraps a Vercel handler with JWT authentication.
 *
 * Usage:
 * ```ts
 * export default withAuth(async (req, res) => {
 *   const { userId } = req.user; // fully typed
 *   res.status(200).json({ userId });
 * });
 * ```
 *
 * @param handler  The protected handler that receives an `AuthenticatedRequest`.
 * @returns        A standard Vercel handler that performs auth before delegating.
 */
function withAuth(handler) {
    return async (req, res) => {
        // ── Step 1: Extract token ────────────────────────────────────────────────
        const token = extractBearerToken(req);
        if (!token) {
            res.status(401).json({
                error: 'Authorization header is missing or malformed. Expected: Bearer <token>',
            });
            return;
        }
        // ── Step 2: Verify signature + expiry ────────────────────────────────────
        let payload;
        try {
            // `jwt.verify` throws for an invalid signature, an expired token, or a
            // malformed JWT structure — all of which should produce a 401.
            payload = jsonwebtoken_1.default.verify(token, JWT_SECRET);
        }
        catch (err) {
            // Distinguish the two most actionable error types for clearer client messages.
            if (err instanceof jsonwebtoken_1.default.TokenExpiredError) {
                res.status(401).json({ error: 'Token has expired. Please log in again.' });
                return;
            }
            // Covers JsonWebTokenError (bad signature) and NotBeforeError.
            res.status(401).json({ error: 'Token is invalid.' });
            return;
        }
        // ── Step 3: Validate payload shape ───────────────────────────────────────
        //
        // `jwt.verify` only guarantees the signature is valid; it does NOT check
        // that the payload has the fields our application expects. A token signed
        // with the correct secret but with a different payload (e.g. an older
        // schema) would otherwise pass silently and crash downstream handlers.
        if (typeof payload.userId !== 'string' || payload.userId.trim() === '' ||
            typeof payload.email !== 'string' || payload.email.trim() === '') {
            res.status(401).json({
                error: 'Token payload is malformed. Please log in again.',
            });
            return;
        }
        // ── Step 4: Inject user and delegate ────────────────────────────────────
        //
        // Cast req to AuthenticatedRequest and attach the verified payload.
        // The cast is safe because we own the HOF — no other code path reaches
        // the inner handler without first passing the checks above.
        const authenticatedReq = req;
        authenticatedReq.user = payload;
        await handler(authenticatedReq, res);
    };
}
