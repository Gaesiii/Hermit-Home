import os
from dataclasses import dataclass


@dataclass(frozen=True)
class AgentConfig:
    api_base_url: str
    device_id: str
    service_api_key: str
    timeout_seconds: int


def load_agent_config() -> AgentConfig:
    api_base_url = os.getenv("API_BASE_URL", "http://localhost:3000").rstrip("/")
    device_id = os.getenv("DEVICE_ID")
    service_api_key = os.getenv("SERVICE_API_KEY")
    timeout_seconds_raw = os.getenv("HTTP_TIMEOUT_SECONDS", "10")

    if not device_id:
        raise ValueError("Missing DEVICE_ID environment variable for AI Agent.")

    if not service_api_key:
        raise ValueError("Missing SERVICE_API_KEY environment variable for AI Agent.")

    try:
        timeout_seconds = max(1, int(timeout_seconds_raw))
    except ValueError as exc:
        raise ValueError("HTTP_TIMEOUT_SECONDS must be an integer.") from exc

    return AgentConfig(
        api_base_url=api_base_url,
        device_id=device_id,
        service_api_key=service_api_key,
        timeout_seconds=timeout_seconds,
    )
