import logging
import time
from typing import Any, Dict, Optional

import requests

from config import load_agent_config

logger = logging.getLogger(__name__)


class CommandPublisher:
    def __init__(self):
        config = load_agent_config()
        self.base_url = config.api_base_url
        self.device_id = config.device_id
        self.timeout = config.timeout_seconds
        self.release_delay_seconds = config.emergency_release_delay_seconds
        self.headers = {"x-api-key": config.service_api_key}

    def _post_json(self, endpoint: str, payload: Dict[str, Any]) -> bool:
        url = f"{self.base_url}{endpoint}"
        try:
            response = requests.post(
                url,
                headers=self.headers,
                json=payload,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return True
        except requests.exceptions.RequestException as exc:
            logger.error("POST %s failed: %s", endpoint, exc)
            return False

    def revoke_user_override(self, thresholds: Dict[str, float], reason: Optional[str] = None) -> bool:
        payload = {
            "user_override": False,
            "thresholds": thresholds,
        }
        ok = self._post_json(f"/api/devices/{self.device_id}/action?type=override", payload)
        if ok:
            if reason:
                logger.warning("User override revoked by AI: %s", reason)
            else:
                logger.warning("User override revoked by AI")
        return ok

    def send_threshold_update(self, thresholds: Dict[str, float], reason: Optional[str] = None) -> bool:
        if not thresholds:
            return False

        payload = {
            "user_override": False,
            "thresholds": thresholds,
        }
        ok = self._post_json(f"/api/devices/{self.device_id}/action?type=override", payload)
        if ok:
            if reason:
                logger.info("Published AI threshold update: %s | reason=%s", thresholds, reason)
            else:
                logger.info("Published AI threshold update: %s", thresholds)
        return ok

    def send_emergency_device_override(
        self,
        devices: Dict[str, bool],
        reason: Optional[str] = None,
    ) -> bool:
        if not devices:
            return False

        payload = {
            "user_override": True,
            "devices": devices,
        }
        ok = self._post_json(f"/api/devices/{self.device_id}/action?type=override", payload)
        if ok:
            if reason:
                logger.warning(
                    "Published emergency AI override command: %s | reason=%s",
                    devices,
                    reason,
                )
            else:
                logger.warning("Published emergency AI override command: %s", devices)
        return ok

    def run_emergency_sequence(
        self,
        devices: Dict[str, bool],
        thresholds: Dict[str, float],
        reason: str,
        revoke_first: bool,
    ) -> bool:
        success = True

        if revoke_first:
            success = self.revoke_user_override(thresholds, reason=reason) and success

        success = self.send_emergency_device_override(devices, reason=reason) and success

        if self.release_delay_seconds > 0:
            time.sleep(self.release_delay_seconds)

        success = self.revoke_user_override(
            thresholds,
            reason="Emergency override released back to auto control.",
        ) and success

        return success

    def send_alert(self, payload: Dict[str, Any]) -> bool:
        ok = self._post_json(f"/api/devices/{self.device_id}/action?type=alert", payload)
        if ok:
            logger.warning("Published AI alert payload to API: %s", payload.get("title", "Untitled"))
        return ok
