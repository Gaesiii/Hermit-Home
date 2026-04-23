import csv
import logging
from pathlib import Path
from typing import Any, Dict, List

logger = logging.getLogger(__name__)


class HistoryContextProvider:
    def __init__(self, csv_path: str):
        self.csv_path = Path(csv_path).expanduser().resolve()

    @staticmethod
    def _to_float(value: Any) -> float | None:
        if value is None:
            return None
        try:
            parsed = float(value)
            return parsed
        except (TypeError, ValueError):
            return None

    def load_context(self, device_id: str, sample_size: int = 200) -> Dict[str, Any]:
        if sample_size < 1:
            sample_size = 1
        if sample_size > 2000:
            sample_size = 2000

        if not self.csv_path.exists():
            logger.warning("Telemetry CSV not found at %s", self.csv_path)
            return {
                "csv_path": str(self.csv_path),
                "csv_available": False,
                "records_considered": 0,
                "summary": {},
                "sample": [],
            }

        try:
            with self.csv_path.open("r", encoding="utf-8", newline="") as handle:
                reader = csv.DictReader(handle)
                rows = [
                    row
                    for row in reader
                    if str(row.get("userId", "")).strip() == device_id
                ]
        except Exception as exc:  # pylint: disable=broad-except
            logger.error("Failed to parse telemetry CSV: %s", exc)
            return {
                "csv_path": str(self.csv_path),
                "csv_available": False,
                "records_considered": 0,
                "summary": {},
                "sample": [],
            }

        if not rows:
            return {
                "csv_path": str(self.csv_path),
                "csv_available": True,
                "records_considered": 0,
                "summary": {},
                "sample": [],
            }

        rows = rows[-sample_size:]
        temperatures = [self._to_float(row.get("temperature")) for row in rows]
        humidities = [self._to_float(row.get("humidity")) for row in rows]
        lux_values = [self._to_float(row.get("lux")) for row in rows]

        def summarize(series: List[float | None]) -> Dict[str, float] | None:
            clean = [value for value in series if value is not None]
            if not clean:
                return None
            return {
                "min": round(min(clean), 2),
                "max": round(max(clean), 2),
                "avg": round(sum(clean) / len(clean), 2),
            }

        sample = [
            {
                "timestamp": row.get("timestamp"),
                "temperature": self._to_float(row.get("temperature")),
                "humidity": self._to_float(row.get("humidity")),
                "lux": self._to_float(row.get("lux")),
            }
            for row in rows[-20:]
        ]

        summary: Dict[str, Any] = {}
        temperature_summary = summarize(temperatures)
        humidity_summary = summarize(humidities)
        lux_summary = summarize(lux_values)

        if temperature_summary is not None:
            summary["temperature"] = temperature_summary
        if humidity_summary is not None:
            summary["humidity"] = humidity_summary
        if lux_summary is not None:
            summary["lux"] = lux_summary

        return {
            "csv_path": str(self.csv_path),
            "csv_available": True,
            "records_considered": len(rows),
            "summary": summary,
            "sample": sample,
        }
