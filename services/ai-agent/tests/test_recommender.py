import sys
import time
import unittest
from pathlib import Path

SRC_ROOT = Path(__file__).resolve().parents[1] / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from model.analyzer import AIControlDecision, AlertDecision, GeminiAnalyzer
from model.recommender import Recommender


class _StubAnalyzer:
    def __init__(self, decisions):
        self._decisions = list(decisions)

    def analyze(self, current_status, recent_telemetry, csv_context, mist_safety_lock_enabled):
        del current_status, recent_telemetry, csv_context, mist_safety_lock_enabled
        if not self._decisions:
            return AIControlDecision(
                danger_state=False,
                reason="noop",
                thresholds={
                    "temp_min": 24.0,
                    "temp_max": 29.0,
                    "hum_min": 70.0,
                    "hum_max": 85.0,
                    "lux_min": 200.0,
                    "lux_max": 500.0,
                },
                emergency_devices={},
                alert=None,
                danger_reasons=[],
            )
        return self._decisions.pop(0)


class AnalyzerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.analyzer = GeminiAnalyzer.__new__(GeminiAnalyzer)

    def test_parse_json_extracts_object(self):
        payload = self.analyzer._parse_json(
            "```json\n{\"danger_state\":true,\"reason\":\"hot\"}\n```"
        )
        self.assertIsNotNone(payload)
        self.assertEqual(payload.get("danger_state"), True)

    def test_detect_danger_reasons_out_of_range(self):
        reasons = self.analyzer.detect_danger_reasons(
            {
                "temperature": 32.0,
                "humidity": 60.0,
                "lux": 1200.0,
                "sensor_fault": False,
            }
        )
        self.assertGreaterEqual(len(reasons), 3)

    def test_mist_lock_forces_mist_off(self):
        output = self.analyzer._sanitize_emergency_devices(
            raw_devices={"mist": True, "heater": True},
            fallback={},
            mist_safety_lock_enabled=True,
        )
        self.assertEqual(output.get("mist"), False)
        self.assertEqual(output.get("heater"), True)


class RecommenderBehaviorTests(unittest.TestCase):
    def _new_recommender(self, decisions, takeover_delay_seconds: int = 20):
        recommender = Recommender.__new__(Recommender)
        recommender.mist_safety_lock_enabled = True
        recommender.user_override_takeover_delay_seconds = takeover_delay_seconds
        recommender.analyzer = _StubAnalyzer(decisions)
        recommender._last_sent_thresholds = None
        recommender._last_emergency_signature = None
        recommender._last_emergency_at = 0.0
        recommender._last_alert_signature = None
        recommender._last_alert_at = 0.0
        recommender._last_agent_devices_signature = None
        recommender._last_agent_devices_at = 0.0
        recommender._danger_override_since = None
        return recommender

    def test_danger_takeover_delayed_for_user_override(self):
        decision = AIControlDecision(
            danger_state=True,
            reason="Danger",
            thresholds={
                "temp_min": 24.0,
                "temp_max": 29.0,
                "hum_min": 70.0,
                "hum_max": 85.0,
                "lux_min": 200.0,
                "lux_max": 500.0,
            },
            emergency_devices={"heater": False, "fan": True, "mist": False},
            alert=AlertDecision(
                severity="critical",
                title="Danger",
                message="Out of range",
            ),
            danger_reasons=["Temperature too high"],
        )
        recommender = self._new_recommender([decision])

        first_plan = recommender.evaluate_conditions(
            telemetry={"user_override": True, "sensor_fault": False},
            recent_telemetry=[],
            csv_context={},
        )
        self.assertTrue(first_plan.danger_state)
        self.assertFalse(first_plan.revoke_user_override)
        self.assertFalse(first_plan.send_emergency_override)
        self.assertTrue(first_plan.send_alert)

        recommender.analyzer = _StubAnalyzer([decision])
        recommender._danger_override_since = time.time() - 25.0
        second_plan = recommender.evaluate_conditions(
            telemetry={"user_override": True, "sensor_fault": False},
            recent_telemetry=[],
            csv_context={},
        )

        self.assertTrue(second_plan.danger_state)
        self.assertTrue(second_plan.revoke_user_override)
        self.assertTrue(second_plan.send_emergency_override)
        self.assertTrue(second_plan.send_alert)

    def test_safe_user_override_keeps_user_priority(self):
        safe_decision = AIControlDecision(
            danger_state=False,
            reason="safe",
            thresholds={
                "temp_min": 24.0,
                "temp_max": 29.0,
                "hum_min": 70.0,
                "hum_max": 85.0,
                "lux_min": 200.0,
                "lux_max": 500.0,
            },
            emergency_devices={},
            alert=None,
            danger_reasons=[],
        )
        recommender = self._new_recommender([safe_decision])
        plan = recommender.evaluate_conditions(
            telemetry={"user_override": True, "temperature": 26.0, "humidity": 76.0, "lux": 300.0},
            recent_telemetry=[],
            csv_context={},
        )

        self.assertFalse(plan.send_threshold_update)
        self.assertFalse(plan.send_agent_control)
        self.assertEqual(plan.agent_devices, {})

    def test_duplicate_non_danger_threshold_suppressed(self):
        safe_decision = AIControlDecision(
            danger_state=False,
            reason="safe",
            thresholds={
                "temp_min": 24.0,
                "temp_max": 29.0,
                "hum_min": 70.0,
                "hum_max": 85.0,
                "lux_min": 200.0,
                "lux_max": 500.0,
            },
            emergency_devices={},
            alert=None,
            danger_reasons=[],
        )
        recommender = self._new_recommender([safe_decision, safe_decision])

        first = recommender.evaluate_conditions({}, [], {})
        second = recommender.evaluate_conditions({}, [], {})

        self.assertTrue(first.send_threshold_update)
        self.assertFalse(second.send_threshold_update)

    def test_alert_deduplication(self):
        danger = AIControlDecision(
            danger_state=True,
            reason="Danger",
            thresholds={
                "temp_min": 24.0,
                "temp_max": 29.0,
                "hum_min": 70.0,
                "hum_max": 85.0,
                "lux_min": 200.0,
                "lux_max": 500.0,
            },
            emergency_devices={"fan": True, "mist": False},
            alert=AlertDecision(
                severity="warning",
                title="Alert",
                message="Repeat",
            ),
            danger_reasons=["Humidity too high"],
        )
        recommender = self._new_recommender([danger, danger])

        first = recommender.evaluate_conditions({}, [], {})
        second = recommender.evaluate_conditions({}, [], {})

        self.assertTrue(first.send_alert)
        self.assertFalse(second.send_alert)


if __name__ == "__main__":
    unittest.main()
