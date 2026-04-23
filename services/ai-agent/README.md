# AI Agent (Priority 2 Autonomous Control)

This service implements Tier-2 control for the terrarium:

1. Pulls live telemetry from the API.
2. Pulls recent telemetry history from API.
3. Loads historical CSV context (`TELEMETRY_CSV_PATH`).
4. Uses Gemini + deterministic safety checks to validate control decisions against hermit-crab safe ranges:
   - Temperature: `24C - 29C`
   - Humidity: `70% - 85%`
   - Lux: `200 - 500`
5. In danger state:
   - Revokes user override when active.
   - Sends emergency override command to edge.
   - Releases back to auto control with safe thresholds.
   - Pushes alert payload to `/api/devices/{deviceId}/action?type=alert`.

The runtime is an always-on loop (`while True` in `src/main.py`), so it is suitable for Render Background Worker deployment (not Vercel serverless functions).

## Environment Variables

Required:

- `API_BASE_URL`
- `DEVICE_ID`
- `SERVICE_API_KEY`
- `GEMINI_API_KEY`

Optional:

- `GEMINI_MODEL` (default: `gemini-2.5-flash`)
- `HTTP_TIMEOUT_SECONDS` (default: `10`)
- `CONTROL_INTERVAL_SECONDS` (default: `30`)
- `TELEMETRY_WINDOW_SIZE` (default: `12`)
- `TELEMETRY_CSV_PATH` (default: `../../exports/telemetry-export.csv`)
- `MIST_SAFETY_LOCK_ENABLED` (default: `true`)
- `EMERGENCY_RELEASE_DELAY_SECONDS` (default: `2`)
- `USER_OVERRIDE_TAKEOVER_DELAY_SECONDS` (default: `20`)

## Install & Run

```bash
cd services/ai-agent
python -m venv venv
source venv/bin/activate  # Windows: .\venv\Scripts\activate
pip install -r requirements.txt
python src/main.py
```

## Deploy On Render (Recommended For Always-On Agent)

At repository root, this project now includes `render.yaml` with:

- `hermit-home-ai-agent` as `type: worker` (always-on loop).
- `hermit-home-mqtt-worker` as `type: web` (MQTT consumer + `/ping` health endpoint).

Deployment flow:

1. Keep `services/api` on Vercel (current architecture).
2. In Render, create Blueprint from this repo (it will read `render.yaml`).
3. Fill secret env values in Render:
   - `API_BASE_URL` should point to your Vercel API domain.
   - `DEVICE_ID`, `SERVICE_API_KEY`, `GEMINI_API_KEY`
   - MQTT + MongoDB credentials for `mqtt-worker`
4. Ensure CSV path is valid for worker runtime:
   - default: `../../exports/telemetry-export.csv` (relative to `services/ai-agent`)
   - or override `TELEMETRY_CSV_PATH` to your own absolute path.

Important:

- Render Background Worker requires at least `starter` plan (no free tier for worker service).
- If your CSV changes frequently, update the file in repo or point `TELEMETRY_CSV_PATH` to a stable mounted location.

## E2E Verifier

Dry-run (no emergency publish):

```bash
python src/e2e_verify.py --tests 1,2,3,4
```

Execute danger-state publish:

```bash
python src/e2e_verify.py --tests 4 --execute-test4
```

When executing Test 4, verify edge acknowledgements in mqtt-worker logs:

```bash
cd ../mqtt-worker
npm run dev
```

Look for: `Received ESP32 override acknowledgement`.
