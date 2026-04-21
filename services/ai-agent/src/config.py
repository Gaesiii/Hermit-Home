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
    gemini_api_key: str
    gemini_model: str


def load_agent_config() -> AgentConfig:
    api_base_url = os.getenv("API_BASE_URL", "http://localhost:3000").rstrip("/")
    device_id = os.getenv("DEVICE_ID")
    service_api_key = os.getenv("SERVICE_API_KEY")
    timeout_seconds_raw = os.getenv("HTTP_TIMEOUT_SECONDS", "10")
    control_interval_seconds_raw = os.getenv("CONTROL_INTERVAL_SECONDS", "60")
    telemetry_window_size_raw = os.getenv("TELEMETRY_WINDOW_SIZE", "12")
    gemini_api_key = os.getenv("GEMINI_API_KEY")
    gemini_model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip()

    if not device_id:
        raise ValueError("Missing DEVICE_ID environment variable for AI Agent.")

    if not service_api_key:
        raise ValueError("Missing SERVICE_API_KEY environment variable for AI Agent.")

    if not gemini_api_key:
        raise ValueError("Missing GEMINI_API_KEY environment variable for AI Agent.")

    if not gemini_model:
        raise ValueError("GEMINI_MODEL cannot be empty.")

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

    return AgentConfig(
        api_base_url=api_base_url,
        device_id=device_id,
        service_api_key=service_api_key,
        timeout_seconds=timeout_seconds,
        control_interval_seconds=control_interval_seconds,
        telemetry_window_size=telemetry_window_size,
        gemini_api_key=gemini_api_key,
        gemini_model=gemini_model,
    )
