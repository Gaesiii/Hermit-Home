# Hermit-Home Mobile (API Test Build)

This Flutter app currently boots into a simple **User API Test** screen for fast backend verification.

## What You Can Test

- `POST /api/users/register`
- `POST /api/users/login`
- Secure token persistence in `flutter_secure_storage`

## Quick Run

1. Set your API base URL (optional):
   - default is `https://hermit-home.vercel.app`
   - override with:
     - `flutter run --dart-define=API_BASE_URL=https://your-domain`
2. Launch the app.
3. Use the `User API Test` screen:
   - Enter base URL, email, password
   - Tap `Register` or `Login`
   - Inspect the raw request/response panel

## Notes

- `Login` saves `token` and `email` to secure storage.
- `Load Saved Token` reloads current local session data.
- `Clear Session` removes saved token/email from secure storage.
