# AI Agent (Priority 2 Autonomous Control)

This service runs the Tier-2 control loop:

1. Read latest telemetry from the API.
2. Read a recent telemetry window for trend context.
3. Ask Gemini to compare current data against ideal hermit-crab conditions.
4. Publish threshold updates as `user_override: false` commands.

## Environment Variables

Required:

- `API_BASE_URL`
- `DEVICE_ID`
- `SERVICE_API_KEY`
- `GEMINI_API_KEY`

Optional:

- `GEMINI_MODEL` (default: `gemini-2.5-flash`)
- `HTTP_TIMEOUT_SECONDS` (default: `10`)
- `CONTROL_INTERVAL_SECONDS` (default: `60`)
- `TELEMETRY_WINDOW_SIZE` (default: `12`)

## Install & Run

```bash
cd services/ai-agent
python -m venv venv
source venv/bin/activate  # Windows: .\venv\Scripts\activate
pip install -r requirements.txt
python src/main.py
```

## Notes

- Commands are sent to `/api/devices/{deviceId}/override` with `user_override=false`.
- AI output is clamped to safe bounds before publishing.
- If `sensor_fault=true` or `user_override=true`, AI will skip updates for that cycle.
