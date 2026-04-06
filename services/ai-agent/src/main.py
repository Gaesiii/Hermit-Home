import logging
import time

import schedule
from dotenv import load_dotenv

from comms.mqtt_publisher import CommandPublisher
from data.telemetry_fetcher import TelemetryFetcher
from model.recommender import Recommender

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

load_dotenv()

fetcher = TelemetryFetcher()
recommender = Recommender()
publisher = CommandPublisher()


def control_loop() -> None:
    logger.info('--- Starting Control Cycle ---')

    status = fetcher.get_latest_status()
    if not status:
        return

    threshold_update = recommender.evaluate_conditions(status)
    if threshold_update:
        publisher.send_threshold_update(threshold_update)

    logger.info('--- Cycle Complete ---')


def main() -> None:
    logger.info('Initializing AI Agent (Tier 2)')
    control_loop()
    schedule.every(60).seconds.do(control_loop)

    while True:
        schedule.run_pending()
        time.sleep(1)


if __name__ == '__main__':
    main()
