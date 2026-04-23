import os
from dataclasses import dataclass


@dataclass(frozen=True)
class AgentConfig:
    api_base_url: str
    device_id: str
    service_api_key: str
    timeout_seconds: int
    control_interval_seconds: int
    telemetry_window_size: int
    telemetry_csv_path: str
    mist_safety_lock_enabled: bool
    emergency_release_delay_seconds: int
    user_override_takeover_delay_seconds: int
    openrouter_api_key: str
    openrouter_model: str
    openrouter_base_url: str
    openrouter_http_referer: str
    openrouter_app_name: str


def _parse_bool(raw: str) -> bool:
    normalized = raw.strip().lower()
    return normalized in {"1", "true", "yes", "on"}


def load_agent_config() -> AgentConfig:
    api_base_url = os.getenv("API_BASE_URL", "http://localhost:3000").rstrip("/")
    device_id = os.getenv("DEVICE_ID")
    service_api_key = os.getenv("SERVICE_API_KEY")
    timeout_seconds_raw = os.getenv("HTTP_TIMEOUT_SECONDS", "10")
    control_interval_seconds_raw = os.getenv("CONTROL_INTERVAL_SECONDS", "30")
    telemetry_window_size_raw = os.getenv("TELEMETRY_WINDOW_SIZE", "12")
    telemetry_csv_path = os.getenv(
        "TELEMETRY_CSV_PATH",
        "../../exports/telemetry-export.csv",
    )
    mist_safety_lock_raw = os.getenv("MIST_SAFETY_LOCK_ENABLED", "true")
    emergency_release_delay_raw = os.getenv("EMERGENCY_RELEASE_DELAY_SECONDS", "2")
    takeover_delay_raw = os.getenv("USER_OVERRIDE_TAKEOVER_DELAY_SECONDS", "20")
    openrouter_api_key = (os.getenv("OPENROUTER_API_KEY") or os.getenv("GEMINI_API_KEY") or "").strip()
    openrouter_model = (
        os.getenv("OPENROUTER_MODEL")
        or os.getenv("GEMINI_MODEL")
        or "google/gemma-3-27b-it:free"
    ).strip()
    openrouter_base_url = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1").rstrip("/")
    openrouter_http_referer = os.getenv("OPENROUTER_HTTP_REFERER", "").strip()
    openrouter_app_name = os.getenv("OPENROUTER_APP_NAME", "Hermit Home AI Agent").strip()

    if not device_id:
        raise ValueError("Missing DEVICE_ID environment variable for AI Agent.")

    if not service_api_key:
        raise ValueError("Missing SERVICE_API_KEY environment variable for AI Agent.")

    if not openrouter_api_key:
        raise ValueError("Missing OPENROUTER_API_KEY environment variable for AI Agent.")

    if not openrouter_model:
        raise ValueError("OPENROUTER_MODEL cannot be empty.")

    try:
        timeout_seconds = max(1, int(timeout_seconds_raw))
    except ValueError as exc:
        raise ValueError("HTTP_TIMEOUT_SECONDS must be an integer.") from exc

    try:
        control_interval_seconds = max(10, int(control_interval_seconds_raw))
    except ValueError as exc:
        raise ValueError("CONTROL_INTERVAL_SECONDS must be an integer.") from exc

    try:
        telemetry_window_size = max(1, min(200, int(telemetry_window_size_raw)))
    except ValueError as exc:
        raise ValueError("TELEMETRY_WINDOW_SIZE must be an integer.") from exc

    try:
        emergency_release_delay_seconds = max(0, int(emergency_release_delay_raw))
    except ValueError as exc:
        raise ValueError("EMERGENCY_RELEASE_DELAY_SECONDS must be an integer.") from exc

    try:
        user_override_takeover_delay_seconds = max(5, int(takeover_delay_raw))
    except ValueError as exc:
        raise ValueError("USER_OVERRIDE_TAKEOVER_DELAY_SECONDS must be an integer.") from exc

    mist_safety_lock_enabled = _parse_bool(mist_safety_lock_raw)

    return AgentConfig(
        api_base_url=api_base_url,
        device_id=device_id,
        service_api_key=service_api_key,
        timeout_seconds=timeout_seconds,
        control_interval_seconds=control_interval_seconds,
        telemetry_window_size=telemetry_window_size,
        telemetry_csv_path=telemetry_csv_path,
        mist_safety_lock_enabled=mist_safety_lock_enabled,
        emergency_release_delay_seconds=emergency_release_delay_seconds,
        user_override_takeover_delay_seconds=user_override_takeover_delay_seconds,
        openrouter_api_key=openrouter_api_key,
        openrouter_model=openrouter_model,
        openrouter_base_url=openrouter_base_url,
        openrouter_http_referer=openrouter_http_referer,
        openrouter_app_name=openrouter_app_name,
    )
