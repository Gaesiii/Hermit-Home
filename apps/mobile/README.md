# Hermit-Home Mobile (API Test Build)

This Flutter app boots directly into a unified **User + Device API Test** screen.

## Covered Endpoints

- `POST /api/auth?action=register`
- `POST /api/auth?action=login`
- `GET /api/devices`
- `GET /api/devices/schedules`
- `GET /api/devices/{deviceId}`
- `PATCH /api/devices/{deviceId}`
- `GET /api/devices/{deviceId}/data?type=latest`
- `GET /api/devices/{deviceId}/action?type=control`
- `POST /api/devices/{deviceId}/action?type=control`
- `POST /api/devices/{deviceId}/action?type=override`
- `OPTIONS` probes for key routes

## Quick Run (Windows)

1. Open PowerShell in this directory.
2. Install packages:
   - `F:\Hermit-Home\.sdk\flutter\bin\flutter.bat pub get`
3. Run on Chrome:
   - `F:\Hermit-Home\.sdk\flutter\bin\flutter.bat run -d chrome --dart-define=API_BASE_URL=https://hermit-home.vercel.app`

## Usage Notes

- Login saves `token` and `email` to secure storage.
- The screen can decode `userId` from JWT and auto-fill `deviceId`.
- Protected API calls can use:
  - `Authorization: Bearer <token>`
  - `X-API-Key` (optional)
- The output panel shows:
  - method + URL
  - status
  - request body
  - response headers
  - response body
