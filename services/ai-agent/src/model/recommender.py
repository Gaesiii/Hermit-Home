import json
import logging
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from config import load_agent_config
from model.analyzer import OpenRouterAnalyzer

logger = logging.getLogger(__name__)

MIN_CHANGE_THRESHOLD = {
    "temp_min": 0.2,
    "temp_max": 0.2,
    "hum_min": 0.5,
    "hum_max": 0.5,
    "lux_min": 20.0,
    "lux_max": 20.0,
}

EMERGENCY_REPEAT_COOLDOWN_SECONDS = 45
ALERT_REPEAT_COOLDOWN_SECONDS = 90
AGENT_CONTROL_REPEAT_COOLDOWN_SECONDS = 20


@dataclass(frozen=True)
class ActionPlan:
    danger_state: bool
    reason: str
    thresholds: Dict[str, float]
    emergency_devices: Dict[str, bool]
    agent_devices: Dict[str, bool]
    revoke_user_override: bool
    send_emergency_override: bool
    send_agent_control: bool
    send_threshold_update: bool
    send_alert: bool
    alert_payload: Optional[Dict[str, Any]]
    danger_reasons: List[str]


class Recommender:
    def __init__(self):
        config = load_agent_config()
        self.mist_safety_lock_enabled = config.mist_safety_lock_enabled
        self.user_override_takeover_delay_seconds = (
            config.user_override_takeover_delay_seconds
        )
        self.analyzer = OpenRouterAnalyzer(
            api_key=config.openrouter_api_key,
            model=config.openrouter_model,
            base_url=config.openrouter_base_url,
            request_timeout_seconds=config.timeout_seconds,
            http_referer=config.openrouter_http_referer,
            app_name=config.openrouter_app_name,
        )
        self._last_sent_thresholds: Optional[Dict[str, float]] = None
        self._last_emergency_signature: Optional[str] = None
        self._last_emergency_at: float = 0.0
        self._last_alert_signature: Optional[str] = None
        self._last_alert_at: float = 0.0
        self._last_agent_devices_signature: Optional[str] = None
        self._last_agent_devices_at: float = 0.0
        self._danger_override_since: Optional[float] = None

    def evaluate_conditions(
        self,
        telemetry: Dict[str, Any],
        recent_telemetry: List[Dict[str, Any]],
        csv_context: Dict[str, Any],
    ) -> ActionPlan:
        decision = self.analyzer.analyze(
            current_status=telemetry,
            recent_telemetry=recent_telemetry,
            csv_context=csv_context,
            mist_safety_lock_enabled=self.mist_safety_lock_enabled,
        )

        now = time.time()
        danger_state = decision.danger_state
        user_override_active = telemetry.get("user_override") is True

        if danger_state and user_override_active:
            if self._danger_override_since is None:
                self._danger_override_since = now
        else:
            self._danger_override_since = None

        takeover_delay_elapsed = False
        if danger_state and user_override_active and self._danger_override_since is not None:
            takeover_delay_elapsed = (
                (now - self._danger_override_since)
                >= self.user_override_takeover_delay_seconds
            )

        revoke_user_override = bool(
            danger_state and user_override_active and takeover_delay_elapsed
        )

        send_emergency_override = False
        if (
            danger_state
            and decision.emergency_devices
            and telemetry.get("sensor_fault") is not True
        ):
            should_delay_takeover = user_override_active and not takeover_delay_elapsed
            if not should_delay_takeover:
                signature = self._to_signature(decision.emergency_devices)
                if (
                    signature != self._last_emergency_signature
                    or now - self._last_emergency_at >= EMERGENCY_REPEAT_COOLDOWN_SECONDS
                ):
                    send_emergency_override = True
                    self._last_emergency_signature = signature
                    self._last_emergency_at = now

        send_threshold_update = False
        if not danger_state and not user_override_active and self._thresholds_changed(
            decision.thresholds
        ):
            send_threshold_update = True
            self._last_sent_thresholds = decision.thresholds.copy()

        agent_devices: Dict[str, bool] = {}
        send_agent_control = False
        if not danger_state and not user_override_active:
            agent_devices = self._build_agent_control_devices(
                telemetry=telemetry,
                thresholds=decision.thresholds,
            )
            if agent_devices:
                signature = self._to_signature(agent_devices)
                if (
                    signature != self._last_agent_devices_signature
                    or now - self._last_agent_devices_at
                    >= AGENT_CONTROL_REPEAT_COOLDOWN_SECONDS
                ):
                    send_agent_control = True
                    self._last_agent_devices_signature = signature
                    self._last_agent_devices_at = now

        effective_reason = decision.reason
        takeover_pending = (
            danger_state and user_override_active and not takeover_delay_elapsed
        )
        if takeover_pending:
            effective_reason = (
                "Safety breach detected during active user override. "
                "AI takeover is delayed briefly before forcing safe control."
            )

        alert_payload: Optional[Dict[str, Any]] = None
        send_alert = False
        if decision.alert:
            alert_payload = {
                "level": decision.alert.severity,
                "title": decision.alert.title,
                "message": decision.alert.message,
                "danger_state": danger_state,
                "reason": effective_reason,
                "danger_reasons": decision.danger_reasons,
                "telemetry": {
                    "temperature": telemetry.get("temperature"),
                    "humidity": telemetry.get("humidity"),
                    "lux": telemetry.get("lux"),
                    "sensor_fault": telemetry.get("sensor_fault"),
                    "user_override": telemetry.get("user_override"),
                    "timestamp": telemetry.get("timestamp"),
                },
                "actions": {
                    "emergency_devices": decision.emergency_devices,
                    "agent_devices": agent_devices,
                    "thresholds": decision.thresholds,
                    "mist_safety_lock_enabled": self.mist_safety_lock_enabled,
                    "user_override_takeover_delay_seconds": self.user_override_takeover_delay_seconds,
                    "takeover_pending": takeover_pending,
                    "takeover_executed": takeover_delay_elapsed and danger_state,
                },
            }
            alert_signature = self._to_signature(alert_payload)
            if (
                alert_signature != self._last_alert_signature
                or now - self._last_alert_at >= ALERT_REPEAT_COOLDOWN_SECONDS
            ):
                send_alert = True
                self._last_alert_signature = alert_signature
                self._last_alert_at = now

        if danger_state:
            self._last_sent_thresholds = decision.thresholds.copy()

        logger.info(
            "Action plan: danger=%s user_override=%s takeover_pending=%s revoke=%s "
            "emergency=%s agent_control=%s threshold_update=%s alert=%s",
            danger_state,
            user_override_active,
            takeover_pending,
            revoke_user_override,
            send_emergency_override,
            send_agent_control,
            send_threshold_update,
            send_alert,
        )

        return ActionPlan(
            danger_state=danger_state,
            reason=effective_reason,
            thresholds=decision.thresholds,
            emergency_devices=decision.emergency_devices,
            agent_devices=agent_devices,
            revoke_user_override=revoke_user_override,
            send_emergency_override=send_emergency_override,
            send_agent_control=send_agent_control,
            send_threshold_update=send_threshold_update,
            send_alert=send_alert,
            alert_payload=alert_payload,
            danger_reasons=decision.danger_reasons,
        )

    @staticmethod
    def _as_float(value: Any) -> Optional[float]:
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, str):
            try:
                return float(value.strip())
            except ValueError:
                return None
        return None

    def _build_agent_control_devices(
        self,
        telemetry: Dict[str, Any],
        thresholds: Dict[str, float],
    ) -> Dict[str, bool]:
        devices: Dict[str, bool] = {}

        temperature = self._as_float(telemetry.get("temperature"))
        humidity = self._as_float(telemetry.get("humidity"))
        lux = self._as_float(telemetry.get("lux"))

        if temperature is not None:
            if temperature < thresholds["temp_min"]:
                devices["heater"] = True
                devices["fan"] = False
            elif temperature > thresholds["temp_max"]:
                devices["heater"] = False
                devices["fan"] = True

        if humidity is not None:
            if humidity < thresholds["hum_min"]:
                if self.mist_safety_lock_enabled:
                    devices["mist"] = False
                    devices["fan"] = False
                else:
                    devices["mist"] = True
                    devices.setdefault("fan", False)
            elif humidity > thresholds["hum_max"]:
                devices["mist"] = False
                devices["fan"] = True

        if lux is not None:
            if lux < thresholds["lux_min"]:
                devices["light"] = True
            elif lux > thresholds["lux_max"]:
                devices["light"] = False

        if self.mist_safety_lock_enabled and "mist" in devices:
            devices["mist"] = False

        return devices

    @staticmethod
    def _to_signature(payload: Dict[str, Any]) -> str:
        return json.dumps(payload, sort_keys=True, separators=(",", ":"))

    def _thresholds_changed(self, next_thresholds: Dict[str, float]) -> bool:
        previous = self._last_sent_thresholds
        if not previous:
            return True

        for key, value in next_thresholds.items():
            prev = previous.get(key)
            if prev is None:
                return True
            tolerance = MIN_CHANGE_THRESHOLD.get(key, 0.0)
            if abs(float(value) - float(prev)) > tolerance:
                return True

        return False
