import logging
import time

from dotenv import load_dotenv

from comms.mqtt_publisher import CommandPublisher
from config import load_agent_config
from data.history_context import HistoryContextProvider
from data.telemetry_fetcher import TelemetryFetcher
from model.recommender import Recommender

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

load_dotenv()

agent_config = load_agent_config()
fetcher = TelemetryFetcher()
history_provider = HistoryContextProvider(agent_config.telemetry_csv_path)
recommender = Recommender()
publisher = CommandPublisher()


def control_loop() -> bool:
    logger.info("--- Starting Control Cycle ---")

    status = fetcher.get_latest_status()
    if not status:
        logger.warning("No status payload received for this cycle.")
        return False

    recent = fetcher.get_recent_telemetry(agent_config.telemetry_window_size)
    csv_context = history_provider.load_context(
        device_id=agent_config.device_id,
        sample_size=max(100, agent_config.telemetry_window_size * 10),
    )

    action_plan = recommender.evaluate_conditions(status, recent, csv_context)

    if action_plan.send_alert and action_plan.alert_payload:
        publisher.send_alert(action_plan.alert_payload)

    if action_plan.send_agent_control and action_plan.agent_devices:
        publisher.send_agent_device_control(
            action_plan.agent_devices,
            reason=action_plan.reason,
        )

    if action_plan.danger_state:
        if action_plan.send_emergency_override:
            publisher.run_emergency_sequence(
                devices=action_plan.emergency_devices,
                thresholds=action_plan.thresholds,
                reason=action_plan.reason,
                revoke_first=action_plan.revoke_user_override,
            )
        elif action_plan.revoke_user_override:
            publisher.revoke_user_override(action_plan.thresholds, reason=action_plan.reason)
        elif action_plan.send_threshold_update:
            publisher.send_threshold_update(action_plan.thresholds, reason=action_plan.reason)
    elif action_plan.send_threshold_update:
        publisher.send_threshold_update(action_plan.thresholds, reason=action_plan.reason)

    logger.info("--- Cycle Complete ---")
    return action_plan.danger_state


def main() -> None:
    logger.info(
        "Initializing AI Agent (Tier 2) | model=%s | interval=%ss",
        agent_config.openrouter_model,
        agent_config.control_interval_seconds,
    )

    while True:
        started_at = time.monotonic()
        danger_state = control_loop()

        target_interval = (
            30 if danger_state else agent_config.control_interval_seconds
        )
        elapsed = time.monotonic() - started_at
        sleep_for = max(1.0, target_interval - elapsed)
        logger.info("Next cycle in %.1fs (danger_state=%s)", sleep_for, danger_state)
        time.sleep(sleep_for)


if __name__ == "__main__":
    main()
