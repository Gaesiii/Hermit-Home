import os
import logging
import requests
from typing import Dict

logger = logging.getLogger(__name__)

class CommandPublisher:
    def __init__(self):
        self.base_url = os.getenv("API_BASE_URL", "http://localhost:3000").rstrip('/')
        self.device_id = os.getenv("DEVICE_ID", "67c6fd9a9acfdbc1d05c22b1")
        self.timeout = 10

    def send_override(self, command_devices: Dict[str, bool]) -> bool:
        if not command_devices:
            return False
            
        url = f"{self.base_url}/api/devices/{self.device_id}/override"
        payload = {
            "user_override": True,
            "devices": command_devices
        }
        try:
            response = requests.post(url, json=payload, timeout=self.timeout)
            response.raise_for_status()
            logger.info(f"Successfully published command: {command_devices}")
            return True
        except requests.exceptions.RequestException as e:
            logger.error(f"Publisher Error: {e}")
            return False