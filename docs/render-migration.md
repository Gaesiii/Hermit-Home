# Render Migration Guide (AI Agent + MQTT Worker)

This guide moves the always-on control processes from serverless runtime to Render:

- `services/ai-agent` -> Render Background Worker (`type: worker`)
- `services/mqtt-worker` -> Render Web Service (`type: web`)

`services/api` can remain on Vercel.

## Why This Migration

Vercel serverless functions are request-driven and not designed for persistent loops.
Your AI agent (`src/main.py`) uses a continuous control loop and needs an always-on runtime.

## Blueprint File

Use the repository root [render.yaml](../render.yaml) to provision services on Render.

## Required Environment Variables

Shared integration values:

- `DEVICE_ID` (Mongo ObjectId for the terrarium)
- `SERVICE_API_KEY` (must match API secret on Vercel)
- `MONGODB_URI`
- `MONGODB_DB_NAME`

AI agent values:

- `API_BASE_URL` (your Vercel API base URL)
- `GEMINI_API_KEY`
- Optional tuning:
  - `CONTROL_INTERVAL_SECONDS`
  - `TELEMETRY_WINDOW_SIZE`
  - `TELEMETRY_CSV_PATH`
  - `USER_OVERRIDE_TAKEOVER_DELAY_SECONDS`

MQTT worker values:

- `MQTT_BROKER`
- `MQTT_PORT`
- `MQTT_USER`
- `MQTT_PASS`
- `ALLOWED_DEVICE_IDS` (optional)
- `ENFORCE_ALLOWED_DEVICE_IDS=false` for dynamic onboarding flow

Temporary bridge values (mqtt-worker -> Vercel trigger endpoint):

- `AGENT_CONTROL_ENABLED=true`
- `AGENT_CONTROL_URL=https://hermit-home.vercel.app/api/agent/control/cycle`
- `AGENT_CONTROL_METHOD=POST`
- `AGENT_CONTROL_API_KEY=<same value as SERVICE_API_KEY on Vercel>`
- `AGENT_CONTROL_INTERVAL_MS=20000`
- `AGENT_CONTROL_TIMEOUT_MS=8000`
- `AGENT_CONTROL_BODY_JSON={"source":"mqtt-worker","trigger":"interval"}`

## CSV Context Notes

The AI agent loads CSV context from `TELEMETRY_CSV_PATH` each cycle.

Default value in blueprint:

- `../../exports/telemetry-export.csv` (relative to `services/ai-agent`)

If you update CSV regularly, refresh it and redeploy, or point to a stable mounted file path.

To regenerate CSV from MongoDB:

```bash
npm run export:telemetry:csv -- --device-id <DEVICE_ID> --out exports/telemetry-export.csv
```

## Verification Checklist

After deployment:

1. Render worker logs include: `Initializing AI Agent (Tier 2)`
2. Agent logs show repeated control cycles (every `CONTROL_INTERVAL_SECONDS`).
3. API logs show service-key auth passes for agent calls.
4. MQTT worker logs show telemetry processing + confirm acknowledgements.
5. Danger-state simulation via [e2e_verify.py](../services/ai-agent/src/e2e_verify.py) triggers alert/override flow.

## Troubleshooting

- `401 Invalid service API key`:
  - `SERVICE_API_KEY` on Render and Vercel API do not match.
- Agent cannot read CSV:
  - Fix `TELEMETRY_CSV_PATH` or ensure file exists in deploy artifact.
- Agent runs but no device action:
  - Check `DEVICE_ID` mismatch or API route auth constraints.
- MQTT publish fails:
  - Verify broker credentials and TLS settings (`MQTT_CA_CERT` if required).
