import logging
from typing import Any, Dict, Optional

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
        url = f"{self.base_url}/api/devices/{self.device_id}/status"
        try:
            response = requests.get(url, headers=self.headers, timeout=self.timeout)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as exc:
            logger.error("Telemetry fetch failed: %s", exc)
            return None
