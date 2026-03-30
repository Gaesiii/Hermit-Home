import time
import logging
import schedule
from dotenv import load_dotenv

from data.telemetry_fetcher import TelemetryFetcher
from model.recommender import Recommender
from comms.mqtt_publisher import CommandPublisher

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

load_dotenv()

fetcher = TelemetryFetcher()
recommender = Recommender()
publisher = CommandPublisher()

def control_loop():
    logger.info("--- Starting Control Cycle ---")
    
    # 1. SENSE
    status = fetcher.get_latest_status()
    if not status:
        return

    # 2. THINK
    recommended_action = recommender.evaluate_conditions(status)

    # 3. ACT
    if recommended_action:
        publisher.send_override(recommended_action)
        
    logger.info("--- Cycle Complete ---\n")

def main():
    logger.info("Initializing AI Agent (Tier 2)")
    control_loop()
    schedule.every(60).seconds.do(control_loop)
    
    while True:
        schedule.run_pending()
        time.sleep(1)

if __name__ == "__main__":
    main()