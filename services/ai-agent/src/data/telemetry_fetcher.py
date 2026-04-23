import logging
from typing import Any, Dict, List, Optional

import requests

from config import load_agent_config

logger = logging.getLogger(__name__)


class TelemetryFetcher:
    def __init__(self):
        config = load_agent_config()
        self.base_url = config.api_base_url
        self.device_id = config.device_id
        self.timeout = config.timeout_seconds
        self.headers = {"x-api-key": config.service_api_key}

    def get_latest_status(self) -> Optional[Dict[str, Any]]:
        url = f"{self.base_url}/api/devices/{self.device_id}/data"
        params = {"type": "latest"}
        try:
            response = requests.get(
                url,
                headers=self.headers,
                params=params,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as exc:
            logger.error("Telemetry fetch failed: %s", exc)
            return None

    def get_recent_telemetry(self, limit: int) -> List[Dict[str, Any]]:
        safe_limit = max(1, min(200, limit))
        url = f"{self.base_url}/api/devices/{self.device_id}/data"
        params = {"type": "history", "limit": safe_limit}
        try:
            response = requests.get(
                url,
                headers=self.headers,
                params=params,
                timeout=self.timeout,
            )
            response.raise_for_status()
            payload = response.json()
            telemetry = payload.get("telemetry")
            if isinstance(telemetry, list):
                return telemetry
            logger.warning("Telemetry payload malformed: missing `telemetry` array.")
            return []
        except requests.exceptions.RequestException as exc:
            logger.error("Recent telemetry fetch failed: %s", exc)
            return []
