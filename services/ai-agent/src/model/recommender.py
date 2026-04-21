import logging
from typing import Any, Dict, List, Optional

from config import load_agent_config
from model.analyzer import GeminiAnalyzer, ThresholdDecision

logger = logging.getLogger(__name__)

MIN_CHANGE_THRESHOLD = {
    "temp_min": 0.2,
    "temp_max": 0.2,
    "hum_min": 0.5,
    "hum_max": 0.5,
    "lux_min": 20.0,
    "lux_max": 20.0,
}


class Recommender:
    def __init__(self):
        config = load_agent_config()
        self.analyzer = GeminiAnalyzer(
            api_key=config.gemini_api_key,
            model=config.gemini_model,
        )
        self._last_sent_thresholds: Optional[Dict[str, float]] = None

    def evaluate_conditions(
        self,
        telemetry: Dict[str, Any],
        recent_telemetry: List[Dict[str, Any]],
    ) -> Optional[ThresholdDecision]:
        if telemetry.get("sensor_fault") is True:
            logger.warning("Sensor fault active. AI autonomous update skipped.")
            return None

        if telemetry.get("user_override") is True:
            logger.info("User override is active. AI autonomous update skipped.")
            return None

        decision = self.analyzer.analyze(telemetry, recent_telemetry)
        if not decision:
            logger.info("Gemini recommends no threshold update for this cycle.")
            return None

        if self._is_duplicate(decision.thresholds):
            logger.info("Skipping duplicate AI threshold update: %s", decision.thresholds)
            return None

        self._last_sent_thresholds = decision.thresholds.copy()
        logger.info("Gemini threshold recommendation accepted: %s", decision.thresholds)
        return decision

    def _is_duplicate(self, next_thresholds: Dict[str, float]) -> bool:
        previous = self._last_sent_thresholds
        if not previous:
            return False

        for key, value in next_thresholds.items():
            prev = previous.get(key)
            if prev is None:
                return False
            tolerance = MIN_CHANGE_THRESHOLD.get(key, 0.0)
            if abs(float(value) - float(prev)) > tolerance:
                return False

        return True
