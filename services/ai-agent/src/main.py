import logging
import time

import schedule
from dotenv import load_dotenv

from comms.mqtt_publisher import CommandPublisher
from config import load_agent_config
from data.telemetry_fetcher import TelemetryFetcher
from model.recommender import Recommender

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

load_dotenv()

agent_config = load_agent_config()
fetcher = TelemetryFetcher()
recommender = Recommender()
publisher = CommandPublisher()


def control_loop() -> None:
    logger.info('--- Starting Control Cycle ---')

    status = fetcher.get_latest_status()
    if not status:
        logger.warning('No status payload received for this cycle.')
        return

    recent = fetcher.get_recent_telemetry(agent_config.telemetry_window_size)
    decision = recommender.evaluate_conditions(status, recent)
    if decision:
        publisher.send_threshold_update(decision.thresholds, reason=decision.reason)

    logger.info('--- Cycle Complete ---')


def main() -> None:
    logger.info(
        'Initializing AI Agent (Tier 2) | model=%s | interval=%ss',
        agent_config.gemini_model,
        agent_config.control_interval_seconds,
    )
    control_loop()
    schedule.every(agent_config.control_interval_seconds).seconds.do(control_loop)

    while True:
        schedule.run_pending()
        time.sleep(1)


if __name__ == '__main__':
    main()
