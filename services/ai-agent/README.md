# AI Agent (Priority 2 Autonomous Control)

This service implements Tier-2 control for the terrarium:

1. Pulls live telemetry from the API.
2. Pulls recent telemetry history from API.
3. Loads historical CSV context (`TELEMETRY_CSV_PATH`).
4. Uses Gemini to validate control decisions against hermit-crab safe ranges:
   - Temperature: `24C - 29C`
   - Humidity: `70% - 85%`
5. In danger state:
   - Revokes user override when active.
   - Sends emergency override command to edge.
   - Releases back to auto control with safe thresholds.
   - Pushes alert payload to `/api/devices/{deviceId}/action?type=alert`.

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

## Install & Run

```bash
cd services/ai-agent
python -m venv venv
source venv/bin/activate  # Windows: .\venv\Scripts\activate
pip install -r requirements.txt
python src/main.py
```

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
