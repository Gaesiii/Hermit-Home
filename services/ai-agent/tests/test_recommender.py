import os
import sys
import unittest
from pathlib import Path

SRC_ROOT = Path(__file__).resolve().parents[1] / "src"
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from model.analyzer import GeminiAnalyzer, ThresholdDecision
from model.recommender import Recommender


class _StubAnalyzer:
    def __init__(self, decisions):
        self._decisions = list(decisions)
        self.calls = 0

    def analyze(self, telemetry, recent):
        self.calls += 1
        if not self._decisions:
            return None
        return self._decisions.pop(0)


class AnalyzerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.analyzer = GeminiAnalyzer.__new__(GeminiAnalyzer)

    def test_parse_json_can_extract_from_code_block(self):
        payload = self.analyzer._parse_json(
            "```json\n{\"should_update\":true,\"reason\":\"ok\",\"thresholds\":{}}\n```"
        )
        self.assertIsNotNone(payload)
        self.assertEqual(payload.get("should_update"), True)

    def test_sanitize_thresholds_clamps_and_fixes_invalid_ranges(self):
        raw = {
            "temp_min": 40,
            "temp_max": 10,
            "hum_min": -10,
            "hum_max": 10,
            "lux_min": 2000,
            "lux_max": 10,
        }
        cleaned = self.analyzer._sanitize_thresholds(raw)

        self.assertGreater(cleaned["temp_max"], cleaned["temp_min"])
        self.assertGreater(cleaned["hum_max"], cleaned["hum_min"])
        self.assertGreater(cleaned["lux_max"], cleaned["lux_min"])
        self.assertLessEqual(cleaned["temp_min"], 30.0)
        self.assertGreaterEqual(cleaned["hum_min"], 55.0)
        self.assertLessEqual(cleaned["lux_max"], 1200.0)


class RecommenderBehaviorTests(unittest.TestCase):
    def _new_recommender(self, decisions):
        recommender = Recommender.__new__(Recommender)
        recommender.analyzer = _StubAnalyzer(decisions)
        recommender._last_sent_thresholds = None
        return recommender

    def test_skip_when_user_override_is_active(self):
        recommender = self._new_recommender(
            [
                ThresholdDecision(
                    thresholds={
                        "temp_min": 24.0,
                        "temp_max": 29.0,
                        "hum_min": 70.0,
                        "hum_max": 85.0,
                        "lux_min": 200.0,
                        "lux_max": 500.0,
                    },
                    reason="unused",
                )
            ]
        )

        result = recommender.evaluate_conditions(
            {"user_override": True, "sensor_fault": False},
            [],
        )
        self.assertIsNone(result)
        self.assertEqual(recommender.analyzer.calls, 0)

    def test_duplicate_thresholds_are_suppressed(self):
        decision = ThresholdDecision(
            thresholds={
                "temp_min": 24.0,
                "temp_max": 29.0,
                "hum_min": 70.0,
                "hum_max": 85.0,
                "lux_min": 200.0,
                "lux_max": 500.0,
            },
            reason="stable",
        )
        recommender = self._new_recommender([decision, decision])

        first = recommender.evaluate_conditions(
            {"user_override": False, "sensor_fault": False},
            [],
        )
        second = recommender.evaluate_conditions(
            {"user_override": False, "sensor_fault": False},
            [],
        )

        self.assertIsNotNone(first)
        self.assertIsNone(second)

    def test_non_duplicate_thresholds_are_accepted(self):
        first = ThresholdDecision(
            thresholds={
                "temp_min": 24.0,
                "temp_max": 29.0,
                "hum_min": 70.0,
                "hum_max": 85.0,
                "lux_min": 200.0,
                "lux_max": 500.0,
            },
            reason="first",
        )
        second = ThresholdDecision(
            thresholds={
                "temp_min": 24.4,
                "temp_max": 29.5,
                "hum_min": 71.0,
                "hum_max": 85.8,
                "lux_min": 260.0,
                "lux_max": 560.0,
            },
            reason="second",
        )
        recommender = self._new_recommender([first, second])

        first_result = recommender.evaluate_conditions(
            {"user_override": False, "sensor_fault": False},
            [],
        )
        second_result = recommender.evaluate_conditions(
            {"user_override": False, "sensor_fault": False},
            [],
        )

        self.assertIsNotNone(first_result)
        self.assertIsNotNone(second_result)


if __name__ == "__main__":
    # Keep imports stable for developers running the file directly.
    os.environ.setdefault("DEVICE_ID", "67f333eebf6bd60f2ac1536a")
    os.environ.setdefault("SERVICE_API_KEY", "test-service-key")
    os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
    unittest.main()
