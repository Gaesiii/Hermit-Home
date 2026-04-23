import json
import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import requests

logger = logging.getLogger(__name__)

SAFETY_THRESHOLDS: Dict[str, tuple[float, float]] = {
    "temperature": (24.0, 29.0),
    "humidity": (70.0, 85.0),
    "lux": (200.0, 500.0),
}

IDEAL_THRESHOLDS: Dict[str, float] = {
    "temp_min": SAFETY_THRESHOLDS["temperature"][0],
    "temp_max": SAFETY_THRESHOLDS["temperature"][1],
    "hum_min": SAFETY_THRESHOLDS["humidity"][0],
    "hum_max": SAFETY_THRESHOLDS["humidity"][1],
    "lux_min": SAFETY_THRESHOLDS["lux"][0],
    "lux_max": SAFETY_THRESHOLDS["lux"][1],
}

SAFE_BOUNDS: Dict[str, tuple[float, float]] = {
    "temp_min": (20.0, 31.0),
    "temp_max": (22.0, 34.0),
    "hum_min": (55.0, 90.0),
    "hum_max": (60.0, 95.0),
    "lux_min": (80.0, 900.0),
    "lux_max": (100.0, 1300.0),
}

MIN_GAP = {
    "temp": 1.0,
    "hum": 5.0,
    "lux": 50.0,
}

DEVICE_KEYS = ("heater", "mist", "fan", "light")


@dataclass(frozen=True)
class AlertDecision:
    severity: str
    title: str
    message: str


@dataclass(frozen=True)
class AIControlDecision:
    danger_state: bool
    reason: str
    thresholds: Dict[str, float]
    emergency_devices: Dict[str, bool]
    alert: Optional[AlertDecision]
    danger_reasons: List[str]


class OpenRouterAnalyzer:
    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str,
        request_timeout_seconds: int = 20,
        http_referer: str = "",
        app_name: str = "Hermit Home AI Agent",
    ):
        self.api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.request_timeout_seconds = max(5, int(request_timeout_seconds))
        self.http_referer = http_referer
        self.app_name = app_name

    def analyze(
        self,
        current_status: Dict[str, Any],
        recent_telemetry: List[Dict[str, Any]],
        csv_context: Dict[str, Any],
        mist_safety_lock_enabled: bool,
    ) -> AIControlDecision:
        danger_reasons = self.detect_danger_reasons(current_status)
        heuristic_devices = self._build_heuristic_emergency_devices(
            current_status,
            mist_safety_lock_enabled,
        )

        prompt = self._build_prompt(
            current_status=current_status,
            recent_telemetry=recent_telemetry,
            csv_context=csv_context,
            danger_reasons=danger_reasons,
            heuristic_devices=heuristic_devices,
            mist_safety_lock_enabled=mist_safety_lock_enabled,
        )

        payload: Optional[Dict[str, Any]] = None
        try:
            raw_text = self._invoke_openrouter(prompt, use_json_response_format=True)
            if raw_text:
                payload = self._parse_json(raw_text)
        except Exception as exc:  # pylint: disable=broad-except
            logger.error("OpenRouter request failed: %s", exc)

        thresholds = self._sanitize_thresholds(
            payload.get("thresholds") if isinstance(payload, dict) else None
        )
        model_devices = payload.get("emergency_devices") if isinstance(payload, dict) else None
        emergency_devices = self._sanitize_emergency_devices(
            model_devices,
            fallback=heuristic_devices,
            mist_safety_lock_enabled=mist_safety_lock_enabled,
        )

        model_danger = bool(payload.get("danger_state")) if isinstance(payload, dict) else False
        danger_state = bool(danger_reasons) or model_danger

        reason = ""
        if isinstance(payload, dict):
            reason = str(payload.get("reason", "")).strip()
        if not reason:
            reason = (
                "Danger conditions detected by deterministic safety rules."
                if danger_state
                else "Conditions are within safe hermit-crab ranges."
            )

        alert = self._sanitize_alert(
            payload.get("alert") if isinstance(payload, dict) else None,
            danger_state=danger_state,
            danger_reasons=danger_reasons,
        )

        if danger_state and not emergency_devices:
            emergency_devices = heuristic_devices

        return AIControlDecision(
            danger_state=danger_state,
            reason=reason[:280],
            thresholds=thresholds,
            emergency_devices=emergency_devices,
            alert=alert,
            danger_reasons=danger_reasons,
        )

    def _invoke_openrouter(
        self,
        prompt: str,
        use_json_response_format: bool,
    ) -> Optional[str]:
        endpoint = f"{self.base_url}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        if self.http_referer:
            headers["HTTP-Referer"] = self.http_referer
        if self.app_name:
            headers["X-Title"] = self.app_name

        body: Dict[str, Any] = {
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": "You are a terrarium safety analyzer. Always return strict JSON only.",
                },
                {
                    "role": "user",
                    "content": prompt,
                },
            ],
            "temperature": 0.1,
            "max_tokens": 900,
        }
        if use_json_response_format:
            body["response_format"] = {"type": "json_object"}

        response = requests.post(
            endpoint,
            headers=headers,
            json=body,
            timeout=self.request_timeout_seconds,
        )
        if response.status_code >= 400 and use_json_response_format:
            # Some free models do not support response_format=json_object.
            # Retry once without response_format for compatibility.
            logger.warning(
                "OpenRouter response_format rejected (%s). Retrying without response_format.",
                response.status_code,
            )
            return self._invoke_openrouter(prompt, use_json_response_format=False)

        response.raise_for_status()
        data = response.json()
        choices = data.get("choices")
        if not isinstance(choices, list) or len(choices) == 0:
            logger.warning("OpenRouter returned no choices.")
            return None

        first = choices[0]
        if not isinstance(first, dict):
            return None
        message = first.get("message")
        if not isinstance(message, dict):
            return None
        content = message.get("content")
        return content if isinstance(content, str) else None

    def detect_danger_reasons(self, current_status: Dict[str, Any]) -> List[str]:
        reasons: List[str] = []
        if current_status.get("sensor_fault") is True:
            reasons.append("Sensor fault flag is active.")

        temperature = self._as_float(current_status.get("temperature"))
        humidity = self._as_float(current_status.get("humidity"))
        lux = self._as_float(current_status.get("lux"))

        temp_min, temp_max = SAFETY_THRESHOLDS["temperature"]
        hum_min, hum_max = SAFETY_THRESHOLDS["humidity"]
        lux_min, lux_max = SAFETY_THRESHOLDS["lux"]

        if temperature is None:
            reasons.append("Temperature telemetry is missing.")
        elif temperature < temp_min:
            reasons.append(f"Temperature too low ({temperature:.1f}C < {temp_min:.1f}C).")
        elif temperature > temp_max:
            reasons.append(f"Temperature too high ({temperature:.1f}C > {temp_max:.1f}C).")

        if humidity is None:
            reasons.append("Humidity telemetry is missing.")
        elif humidity < hum_min:
            reasons.append(f"Humidity too low ({humidity:.1f}% < {hum_min:.1f}%).")
        elif humidity > hum_max:
            reasons.append(f"Humidity too high ({humidity:.1f}% > {hum_max:.1f}%).")

        if lux is None:
            reasons.append("Lux telemetry is missing.")
        elif lux < lux_min:
            reasons.append(f"Light level too low ({lux:.0f} < {lux_min:.0f}).")
        elif lux > lux_max:
            reasons.append(f"Light level too high ({lux:.0f} > {lux_max:.0f}).")

        return reasons

    def _build_prompt(
        self,
        current_status: Dict[str, Any],
        recent_telemetry: List[Dict[str, Any]],
        csv_context: Dict[str, Any],
        danger_reasons: List[str],
        heuristic_devices: Dict[str, bool],
        mist_safety_lock_enabled: bool,
    ) -> str:
        compact_recent = []
        for item in reversed(recent_telemetry[:20]):
            compact_recent.append(
                {
                    "timestamp": item.get("timestamp"),
                    "temperature": item.get("temperature"),
                    "humidity": item.get("humidity"),
                    "lux": item.get("lux"),
                    "sensor_fault": item.get("sensor_fault"),
                    "user_override": item.get("user_override"),
                }
            )

        request_payload = {
            "task": (
                "Validate environmental control decisions for a hermit crab terrarium. "
                "Output strict JSON only."
            ),
            "current_status": {
                "temperature": current_status.get("temperature"),
                "humidity": current_status.get("humidity"),
                "lux": current_status.get("lux"),
                "sensor_fault": current_status.get("sensor_fault"),
                "user_override": current_status.get("user_override"),
                "timestamp": current_status.get("timestamp"),
            },
            "recent_telemetry": compact_recent,
            "csv_context": {
                "csv_available": csv_context.get("csv_available", False),
                "records_considered": csv_context.get("records_considered", 0),
                "summary": csv_context.get("summary", {}),
                "sample": csv_context.get("sample", [])[:12],
            },
            "safety_thresholds": SAFETY_THRESHOLDS,
            "ideal_threshold_config": IDEAL_THRESHOLDS,
            "safe_bounds": SAFE_BOUNDS,
            "deterministic_danger_reasons": danger_reasons,
            "heuristic_emergency_devices": heuristic_devices,
            "constraints": {
                "mist_safety_lock_enabled": mist_safety_lock_enabled,
                "mist_command_must_be_false_when_locked": True,
            },
            "required_json_schema": {
                "danger_state": "boolean",
                "reason": "string",
                "thresholds": {
                    "temp_min": "number",
                    "temp_max": "number",
                    "hum_min": "number",
                    "hum_max": "number",
                    "lux_min": "number",
                    "lux_max": "number",
                },
                "emergency_devices": {
                    "heater": "boolean optional",
                    "mist": "boolean optional",
                    "fan": "boolean optional",
                    "light": "boolean optional",
                },
                "alert": {
                    "severity": "warning|critical",
                    "title": "string",
                    "message": "string",
                },
            },
            "rules": [
                "If any deterministic_danger_reasons exist, set danger_state=true.",
                "When danger_state=true, provide emergency_devices and alert.",
                "Keep thresholds within safe_bounds and near ideal values.",
                "If mist safety lock is enabled, emergency_devices.mist must be false.",
                "Output only JSON object, no markdown.",
            ],
        }

        return json.dumps(request_payload, ensure_ascii=True)

    @staticmethod
    def _parse_json(raw_text: str) -> Optional[Dict[str, Any]]:
        try:
            parsed = json.loads(raw_text)
            return parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            pass

        match = re.search(r"\{.*\}", raw_text, re.DOTALL)
        if not match:
            return None

        try:
            parsed = json.loads(match.group(0))
            return parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            return None

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

    def _sanitize_thresholds(self, raw_thresholds: Any) -> Dict[str, float]:
        merged = IDEAL_THRESHOLDS.copy()
        source = raw_thresholds if isinstance(raw_thresholds, dict) else {}

        for key, default_value in IDEAL_THRESHOLDS.items():
            candidate = self._as_float(source.get(key))
            value = default_value if candidate is None else candidate
            lower, upper = SAFE_BOUNDS[key]
            merged[key] = max(lower, min(upper, value))

        if merged["temp_max"] <= merged["temp_min"]:
            merged["temp_max"] = min(
                SAFE_BOUNDS["temp_max"][1],
                merged["temp_min"] + MIN_GAP["temp"],
            )
        if merged["temp_min"] >= merged["temp_max"]:
            merged["temp_min"] = max(
                SAFE_BOUNDS["temp_min"][0],
                merged["temp_max"] - MIN_GAP["temp"],
            )

        if merged["hum_max"] <= merged["hum_min"]:
            merged["hum_max"] = min(
                SAFE_BOUNDS["hum_max"][1],
                merged["hum_min"] + MIN_GAP["hum"],
            )
        if merged["hum_min"] >= merged["hum_max"]:
            merged["hum_min"] = max(
                SAFE_BOUNDS["hum_min"][0],
                merged["hum_max"] - MIN_GAP["hum"],
            )

        if merged["lux_max"] <= merged["lux_min"]:
            merged["lux_max"] = min(
                SAFE_BOUNDS["lux_max"][1],
                merged["lux_min"] + MIN_GAP["lux"],
            )
        if merged["lux_min"] >= merged["lux_max"]:
            merged["lux_min"] = max(
                SAFE_BOUNDS["lux_min"][0],
                merged["lux_max"] - MIN_GAP["lux"],
            )

        return {
            "temp_min": round(merged["temp_min"], 1),
            "temp_max": round(merged["temp_max"], 1),
            "hum_min": round(merged["hum_min"], 1),
            "hum_max": round(merged["hum_max"], 1),
            "lux_min": round(merged["lux_min"], 0),
            "lux_max": round(merged["lux_max"], 0),
        }

    def _sanitize_emergency_devices(
        self,
        raw_devices: Any,
        fallback: Dict[str, bool],
        mist_safety_lock_enabled: bool,
    ) -> Dict[str, bool]:
        output: Dict[str, bool] = {}
        source = raw_devices if isinstance(raw_devices, dict) else {}

        for key in DEVICE_KEYS:
            value = source.get(key)
            if isinstance(value, bool):
                output[key] = value

        if not output:
            output = fallback.copy()

        if mist_safety_lock_enabled:
            output["mist"] = False

        return output

    def _sanitize_alert(
        self,
        raw_alert: Any,
        danger_state: bool,
        danger_reasons: List[str],
    ) -> Optional[AlertDecision]:
        if not danger_state:
            return None

        severity = "critical" if any("missing" in reason.lower() for reason in danger_reasons) else "warning"
        title = "Hermit Home Danger State Detected"
        if danger_reasons:
            message = "; ".join(danger_reasons[:3])
        else:
            message = "Environment is outside safe hermit crab thresholds."

        if isinstance(raw_alert, dict):
            candidate_severity = str(raw_alert.get("severity", "")).strip().lower()
            if candidate_severity in {"warning", "critical"}:
                severity = candidate_severity

            candidate_title = str(raw_alert.get("title", "")).strip()
            if candidate_title:
                title = candidate_title

            candidate_message = str(raw_alert.get("message", "")).strip()
            if candidate_message:
                message = candidate_message

        return AlertDecision(
            severity=severity,
            title=title[:120],
            message=message[:600],
        )

    def _build_heuristic_emergency_devices(
        self,
        telemetry: Dict[str, Any],
        mist_safety_lock_enabled: bool,
    ) -> Dict[str, bool]:
        devices: Dict[str, bool] = {}

        temperature = self._as_float(telemetry.get("temperature"))
        humidity = self._as_float(telemetry.get("humidity"))
        lux = self._as_float(telemetry.get("lux"))

        temp_min, temp_max = SAFETY_THRESHOLDS["temperature"]
        hum_min, hum_max = SAFETY_THRESHOLDS["humidity"]
        lux_min, lux_max = SAFETY_THRESHOLDS["lux"]

        if temperature is not None:
            if temperature < temp_min:
                devices["heater"] = True
                devices["fan"] = False
            elif temperature > temp_max:
                devices["heater"] = False
                devices["fan"] = True

        if humidity is not None:
            if humidity < hum_min:
                if mist_safety_lock_enabled:
                    devices["fan"] = False
                    devices["mist"] = False
                else:
                    devices["mist"] = True
            elif humidity > hum_max:
                devices["fan"] = True
                devices["mist"] = False

        if lux is not None:
            if lux < lux_min:
                devices["light"] = True
            elif lux > lux_max:
                devices["light"] = False

        if mist_safety_lock_enabled:
            devices["mist"] = False

        return devices


# Backward compatibility for existing imports/tests.
GeminiAnalyzer = OpenRouterAnalyzer
