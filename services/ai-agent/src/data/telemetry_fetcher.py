import os
import logging
import requests
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

class TelemetryFetcher:
    def __init__(self):
        self.base_url = os.getenv("API_BASE_URL", "http://localhost:3000").rstrip('/')
        self.device_id = os.getenv("DEVICE_ID", "67c6fd9a9acfdbc1d05c22b1")
        self.timeout = 10

    def get_latest_status(self) -> Optional[Dict[str, Any]]:
        url = f"{self.base_url}/api/devices/{self.device_id}/status"
        try:
            response = requests.get(url, timeout=self.timeout)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"Fetcher Error: {e}")
            return None