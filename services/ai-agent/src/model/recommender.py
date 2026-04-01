import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class Recommender:
    @staticmethod
    def evaluate_conditions(telemetry: Dict[str, Any]) -> Dict[str, bool]:
        command = {}
        mode = telemetry.get('mode')
        humidity = telemetry.get('humidity')
        current_mist_state = telemetry.get('relays', {}).get('mist')

        if mode == 'MANUAL':
            logger.info("Decision: Device is in MANUAL mode. Skip AI control.")
            return command

        if humidity is None:
            logger.warning("Missing humidity data for evaluation.")
            return command

        if humidity < 60.0 and not current_mist_state:
            logger.info("Decision: Humidity low (<60%). Recommend turning ON mist.")
            command["mist"] = True
        elif humidity > 80.0 and current_mist_state:
            logger.info("Decision: Humidity high (>80%). Recommend turning OFF mist.")
            command["mist"] = False
        else:
            logger.info("Decision: Conditions stable. No changes recommended.")
            
        return command
