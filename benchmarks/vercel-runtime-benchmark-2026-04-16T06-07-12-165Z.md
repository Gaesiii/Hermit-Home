# Vercel API + DB Benchmark

- Generated at: 2026-04-16T06:07:12.165Z
- Base URL: https://hermit-home.vercel.app
- Benchmark user/deviceId: 69e07bd3692ad4372b6e74ce

## API Runtime

| Name | Method | Path | p50 (ms) | p95 (ms) | p99 (ms) | Avg (ms) | Req/s | non2xx | Status |
|---|---|---|---:|---:|---:|---:|---:|---:|---|
| devices_index_get | GET | /api/devices | 271.31 | 329.16 | 369.57 | 276.47 | 35.56 | 0% | 200:294 |
| devices_schedules_get | GET | /api/devices/schedules | 270.36 | 302.01 | 348.63 | 272.63 | 36.15 | 0% | 200:299 |
| device_get | GET | /api/devices/69e07bd3692ad4372b6e74ce | 471.05 | 3423.38 | 3492.45 | 936 | 8.82 | 100% | 404:93 |
| device_status_get | GET | /api/devices/69e07bd3692ad4372b6e74ce/status | 476.74 | 3233.75 | 3299.66 | 958.62 | 10.1 | 100% | 404:86 |
| device_telemetry_get | GET | /api/devices/69e07bd3692ad4372b6e74ce/telemetry?limit=30 | 488.39 | 3070.65 | 3844 | 1010.41 | 8.66 | 0% | 200:91 |
| device_control_get | GET | /api/devices/69e07bd3692ad4372b6e74ce/control?limit=20 | 510 | 2532.59 | 3375.41 | 880.71 | 9.78 | 0% | 200:96 |
| device_patch | PATCH | /api/devices/69e07bd3692ad4372b6e74ce | 472 | 1904.42 | 2952.42 | 685.39 | 6.97 | 0% | 200:63 |
| device_override_post | POST | /api/devices/69e07bd3692ad4372b6e74ce/override | 276.47 | 379.78 | 1159.65 | 309.9 | 16 | 100% | 500:131 |
| device_control_post | POST | /api/devices/69e07bd3692ad4372b6e74ce/control | 276.4 | 355.66 | 462.69 | 283.95 | 17.35 | 100% | 502:143 |
| users_login_post | POST | /api/users/login | 1064.29 | 2686.97 | 3226.03 | 1439.57 | 3.42 | 0% | 200:30 |
| users_forgot_password_post | POST | /api/users/forgot-password | 476.93 | 1769.36 | 2883.56 | 681.68 | 7.02 | 0% | 200:62 |
| users_reset_password_invalid_post | POST | /api/users/reset-password | 464.84 | 1890.19 | 2876.41 | 680.17 | 7.17 | 100% | 400:60 |
| reset_password_link_get | GET | /reset-password?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx | 467.91 | 1769.31 | 2785.13 | 648.85 | 7.18 | 0% | - |
| auth_placeholder_get | GET | /api/auth/session | 268.6 | 308.97 | 456.83 | 275.18 | 18.06 | 100% | 501:147 |
| users_register_post_dynamic | POST | /api/users/register | 1076.4 | 1345.43 | 1370.34 | 1170.65 | 1.7 | 0% | 201:20 |

## DB Runtime

| Operation | Iterations | p50 (ms) | p95 (ms) | p99 (ms) | Avg (ms) |
|---|---:|---:|---:|---:|---:|
| users_findOne_email_existing | 80 | 50.12 | 53.09 | 65.02 | 50.8 |
| users_findOne_email_missing | 80 | 50.1 | 57.17 | 316.51 | 54.19 |
| users_insertOne_unique | 80 | 53.14 | 56.09 | 66.1 | 53.76 |
| devices_findOne_deviceId | 80 | 50.1 | 60.04 | 75.32 | 51.47 |
| devices_findOneAndUpdate | 80 | 54.05 | 61.13 | 72.31 | 54.75 |
| telemetry_find_latest | 80 | 52.11 | 56.1 | 63.15 | 52.58 |
| telemetry_find_limit_30 | 80 | 52.14 | 54.15 | 62.11 | 52.67 |
| device_states_find_recent_20 | 80 | 51.13 | 59.22 | 65.17 | 52.25 |
| device_states_insertOne | 80 | 53.94 | 58.22 | 69.1 | 54.19 |
| password_reset_findOne_tokenHash_existing | 80 | 50.09 | 51.42 | 58.13 | 50.29 |
| password_reset_findOneAndUpdate_no_match | 80 | 50.11 | 53.08 | 57.01 | 50.4 |

### Query Explain (executionStats)

| Query | executionTimeMillis | docsExamined | keysExamined | nReturned | stages | indexes |
|---|---:|---:|---:|---:|---|---|
| users_findOne_email | 0 | 96 | 0 | 1 | LIMIT, COLLSCAN | - |
| telemetry_find_limit_30 | 2 | 3127 | 0 | 30 | SORT, COLLSCAN | - |
| device_states_find_recent_20 | 0 | 604 | 0 | 20 | SORT, COLLSCAN | - |
| password_reset_findOne_tokenHash | 0 | 1 | 1 | 1 | EXPRESS_IXSCAN | token_hash_unique |

## Bottleneck Findings

- [API] device_get p95=3423.38ms (>1200ms)
- [API] device_get non2xx=100% (>5%)
- [API] device_status_get p95=3233.75ms (>1200ms)
- [API] device_status_get non2xx=100% (>5%)
- [API] device_telemetry_get p95=3070.65ms (>1200ms)
- [API] device_control_get p95=2532.59ms (>1200ms)
- [API] device_patch p95=1904.42ms (>1200ms)
- [API] device_override_post non2xx=100% (>5%)
- [API] device_control_post non2xx=100% (>5%)
- [API] users_login_post p95=2686.97ms (>1200ms)
- [API] users_forgot_password_post p95=1769.36ms (>1200ms)
- [API] users_reset_password_invalid_post p95=1890.19ms (>1200ms)
- [API] users_reset_password_invalid_post non2xx=100% (>5%)
- [API] reset_password_link_get p95=1769.31ms (>1200ms)
- [API] auth_placeholder_get non2xx=100% (>5%)
- [API] users_register_post_dynamic p95=1345.43ms (>1200ms)
- [DB] users_findOne_email uses COLLSCAN
- [DB] telemetry_find_limit_30 uses COLLSCAN
- [DB] telemetry_find_limit_30 docsExamined/nReturned=104.23 (high scan ratio)
- [DB] device_states_find_recent_20 uses COLLSCAN
