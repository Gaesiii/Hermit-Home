import json
import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from google import genai

logger = logging.getLogger(__name__)

IDEAL_THRESHOLDS: Dict[str, float] = {
    "temp_min": 24.0,
    "temp_max": 29.0,
    "hum_min": 70.0,
    "hum_max": 85.0,
    "lux_min": 200.0,
    "lux_max": 500.0,
}

SAFE_BOUNDS: Dict[str, tuple[float, float]] = {
    "temp_min": (20.0, 30.0),
    "temp_max": (22.0, 34.0),
    "hum_min": (55.0, 90.0),
    "hum_max": (60.0, 95.0),
    "lux_min": (50.0, 800.0),
    "lux_max": (100.0, 1200.0),
}

MIN_GAP = {
    "temp": 1.0,
    "hum": 5.0,
    "lux": 50.0,
}


@dataclass(frozen=True)
class ThresholdDecision:
    thresholds: Dict[str, float]
    reason: str


class GeminiAnalyzer:
    def __init__(self, api_key: str, model: str):
        self.client = genai.Client(api_key=api_key)
        self.model = model

    def analyze(
        self,
        current_status: Dict[str, Any],
        recent_telemetry: List[Dict[str, Any]],
    ) -> Optional[ThresholdDecision]:
        prompt = self._build_prompt(current_status, recent_telemetry)

        try:
            response = self.client.models.generate_content(
                model=self.model,
                contents=prompt,
                config={
                    "temperature": 0.2,
                    "response_mime_type": "application/json",
                    "max_output_tokens": 600,
                },
            )
        except Exception as exc:  # pylint: disable=broad-except
            logger.error("Gemini request failed: %s", exc)
            return None

        raw_text = getattr(response, "text", None)
        if not raw_text:
            logger.warning("Gemini returned empty text output.")
            return None

        payload = self._parse_json(raw_text)
        if not payload:
            logger.warning("Gemini response is not valid JSON: %s", raw_text)
            return None

        if payload.get("should_update") is not True:
            return None

        raw_thresholds = payload.get("thresholds")
        if not isinstance(raw_thresholds, dict):
            logger.warning("Gemini omitted `thresholds` in update decision.")
            return None

        thresholds = self._sanitize_thresholds(raw_thresholds)
        reason = str(payload.get("reason", "")).strip() or "Gemini recommendation."

        return ThresholdDecision(thresholds=thresholds, reason=reason[:240])

    def _build_prompt(
        self,
        current_status: Dict[str, Any],
        recent_telemetry: List[Dict[str, Any]],
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
                }
            )

        request_payload = {
            "objective": (
                "Decide if Tier-2 autonomous control should update terrarium thresholds "
                "for a hermit crab habitat."
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
            "ideal_hermit_crab_thresholds": IDEAL_THRESHOLDS,
            "safe_bounds": SAFE_BOUNDS,
            "rules": [
                "If sensor_fault is true, return should_update=false.",
                "If user_override is true, return should_update=false.",
                "Keep thresholds close to ideal values unless trend shows persistent drift.",
                "Thresholds must obey temp_min < temp_max, hum_min < hum_max, lux_min < lux_max.",
                "Output only JSON with keys: should_update, reason, thresholds.",
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

    def _sanitize_thresholds(self, raw_thresholds: Dict[str, Any]) -> Dict[str, float]:
        merged = IDEAL_THRESHOLDS.copy()

        for key, default_value in IDEAL_THRESHOLDS.items():
            candidate = self._as_float(raw_thresholds.get(key))
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
