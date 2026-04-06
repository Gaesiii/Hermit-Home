import logging
from typing import Dict

import requests

from config import load_agent_config

logger = logging.getLogger(__name__)


class CommandPublisher:
    def __init__(self):
        config = load_agent_config()
        self.base_url = config.api_base_url
        self.device_id = config.device_id
        self.timeout = config.timeout_seconds
        self.headers = {"x-api-key": config.service_api_key}

    def send_threshold_update(self, thresholds: Dict[str, float]) -> bool:
        if not thresholds:
            return False

        url = f"{self.base_url}/api/devices/{self.device_id}/override"
        payload = {
            "user_override": False,
            "thresholds": thresholds,
        }

        try:
            response = requests.post(
                url,
                headers=self.headers,
                json=payload,
                timeout=self.timeout,
            )
            response.raise_for_status()
            logger.info("Published threshold update: %s", thresholds)
            return True
        except requests.exceptions.RequestException as exc:
            logger.error("Threshold publish failed: %s", exc)
            return False
