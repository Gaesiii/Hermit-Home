import argparse
import json
import logging
import sys
from copy import deepcopy

from dotenv import load_dotenv

from comms.mqtt_publisher import CommandPublisher
from config import load_agent_config
from data.history_context import HistoryContextProvider
from data.telemetry_fetcher import TelemetryFetcher
from model.recommender import Recommender

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


def assert_or_exit(condition: bool, message: str) -> None:
    if condition:
        return
    logger.error("FAILED: %s", message)
    sys.exit(1)


def run() -> None:
    parser = argparse.ArgumentParser(description="Hermit Home AI Agent E2E verifier")
    parser.add_argument(
        "--tests",
        default="1,2,3,4",
        help="Comma-separated test IDs to run (1,2,3,4). Default: all.",
    )
    parser.add_argument(
        "--execute-test4",
        action="store_true",
        help="Actually publish emergency override commands for Test 4.",
    )
    args = parser.parse_args()
    selected_tests = {item.strip() for item in args.tests.split(",") if item.strip()}

    load_dotenv()
    config = load_agent_config()

    fetcher = TelemetryFetcher()
    history_provider = HistoryContextProvider(config.telemetry_csv_path)
    recommender = Recommender()
    publisher = CommandPublisher()

    status = fetcher.get_latest_status()
    if "1" in selected_tests:
        assert_or_exit(status is not None, "Test 1 failed: unable to fetch telemetry from API.")
        logger.info(
            "Test 1 PASS: API telemetry fetched (temp=%s hum=%s lux=%s user_override=%s).",
            status.get("temperature"),
            status.get("humidity"),
            status.get("lux"),
            status.get("user_override"),
        )
    else:
        assert_or_exit(status is not None, "Telemetry fetch is required for tests 2/3/4.")

    recent = fetcher.get_recent_telemetry(config.telemetry_window_size)
    csv_context = history_provider.load_context(config.device_id, sample_size=300)

    if "2" in selected_tests:
        assert_or_exit(len(recent) > 0, "Test 2 failed: recent telemetry list is empty.")
        assert_or_exit(
            csv_context.get("csv_available") is True,
            f"Test 2 failed: CSV not available at {config.telemetry_csv_path}.",
        )
        logger.info(
            "Test 2 PASS: API recent telemetry=%d rows, CSV context rows=%s",
            len(recent),
            csv_context.get("records_considered"),
        )

    if "3" in selected_tests:
        plan = recommender.evaluate_conditions(status, recent, csv_context)
        assert_or_exit(plan is not None, "Test 3 failed: recommender returned no plan.")
        logger.info(
            "Test 3 PASS: Gemini decision produced (danger=%s, reason=%s)",
            plan.danger_state,
            plan.reason,
        )

    if "4" in selected_tests:
        danger_status = deepcopy(status)
        danger_status["temperature"] = 32.5
        danger_status["humidity"] = 60.0
        danger_status["lux"] = 1200.0
        danger_status["sensor_fault"] = False
        danger_status["user_override"] = True

        danger_recent = [danger_status] + recent[: max(0, config.telemetry_window_size - 1)]
        danger_plan = recommender.evaluate_conditions(danger_status, danger_recent, csv_context)

        assert_or_exit(danger_plan.danger_state, "Test 4 failed: simulated danger not detected.")
        assert_or_exit(
            bool(danger_plan.emergency_devices),
            "Test 4 failed: no emergency device commands were generated.",
        )

        logger.info(
            "Test 4 PLAN: danger=%s revoke=%s emergency=%s devices=%s",
            danger_plan.danger_state,
            danger_plan.revoke_user_override,
            danger_plan.send_emergency_override,
            json.dumps(danger_plan.emergency_devices),
        )

        if args.execute_test4:
            if danger_plan.send_alert and danger_plan.alert_payload:
                publisher.send_alert(danger_plan.alert_payload)

            if danger_plan.send_emergency_override:
                ok = publisher.run_emergency_sequence(
                    devices=danger_plan.emergency_devices,
                    thresholds=danger_plan.thresholds,
                    reason=danger_plan.reason,
                    revoke_first=True,
                )
                assert_or_exit(ok, "Test 4 failed: emergency command sequence publish failed.")
            elif danger_plan.revoke_user_override:
                ok = publisher.revoke_user_override(danger_plan.thresholds, reason=danger_plan.reason)
                assert_or_exit(ok, "Test 4 failed: revoke user override publish failed.")
            elif danger_plan.send_threshold_update:
                ok = publisher.send_threshold_update(danger_plan.thresholds, reason=danger_plan.reason)
                assert_or_exit(ok, "Test 4 failed: threshold update publish failed.")
            else:
                logger.info(
                    "Test 4 INFO: takeover pending, no override command published in this cycle."
                )

            logger.info(
                "Test 4 EXECUTED: verify ESP32 ack in mqtt-worker logs: "
                "'Received ESP32 override acknowledgement'"
            )
        else:
            logger.info("Test 4 DRY-RUN only. Re-run with --execute-test4 to publish MQTT commands.")

    logger.info("All E2E verification steps completed.")


if __name__ == "__main__":
    run()
