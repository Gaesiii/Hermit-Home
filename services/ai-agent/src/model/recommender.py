import logging
from typing import Any, Dict

logger = logging.getLogger(__name__)


class Recommender:
    @staticmethod
    def evaluate_conditions(telemetry: Dict[str, Any]) -> Dict[str, float]:
        humidity = telemetry.get("humidity")
        if humidity is None:
            logger.warning("Missing humidity data for evaluation.")
            return {}

        if humidity < 60.0:
            logger.info("Humidity low (%.1f). Recommending higher humidity thresholds.", humidity)
            return {"hum_min": 72.0, "hum_max": 82.0}

        if humidity > 80.0:
            logger.info("Humidity high (%.1f). Recommending lower humidity thresholds.", humidity)
            return {"hum_min": 65.0, "hum_max": 75.0}

        logger.info("Humidity stable (%.1f). No threshold change recommended.", humidity)
        return {}
