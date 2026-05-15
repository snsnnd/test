import math
import time
from collections import deque


class PerfTracker:
    def __init__(self, window_size=100):
        self.window_size = window_size
        self.samples = {
            "preprocess_ms": deque(maxlen=window_size),
            "inference_ms": deque(maxlen=window_size),
            "total_ms": deque(maxlen=window_size),
        }
        self.frame_count = 0

    def _avg(self, key):
        values = self.samples[key]
        if not values:
            return 0.0
        return round(sum(values) / len(values), 3)

    def _max(self, key):
        values = self.samples[key]
        if not values:
            return 0.0
        return round(max(values), 3)

    def _p95(self, key):
        values = self.samples[key]
        if not values:
            return 0.0
        sorted_values = sorted(values)
        index = int(math.ceil(0.95 * len(sorted_values))) - 1
        index = min(max(index, 0), len(sorted_values) - 1)
        return round(sorted_values[index], 3)

    def start(self):
        return time.time()

    def finish(self, preprocess_ms, inference_ms, total_ms):
        self.frame_count += 1
        self.samples["preprocess_ms"].append(preprocess_ms)
        self.samples["inference_ms"].append(inference_ms)
        self.samples["total_ms"].append(total_ms)
        return self.snapshot(preprocess_ms, inference_ms, total_ms)

    def snapshot(self, preprocess_ms=0.0, inference_ms=0.0, total_ms=0.0):
        current_fps = 0.0 if total_ms <= 0 else round(1000.0 / total_ms, 3)
        avg_total_ms = self._avg("total_ms")
        return {
            "frameCount": self.frame_count,
            "current": {
                "preprocessMs": round(preprocess_ms, 3),
                "inferenceMs": round(inference_ms, 3),
                "totalMs": round(total_ms, 3),
                "fps": current_fps,
            },
            "average": {
                "preprocessMs": self._avg("preprocess_ms"),
                "inferenceMs": self._avg("inference_ms"),
                "totalMs": avg_total_ms,
                "fps": 0.0 if avg_total_ms <= 0 else round(1000.0 / avg_total_ms, 3),
            },
            "p95": {
                "preprocessMs": self._p95("preprocess_ms"),
                "inferenceMs": self._p95("inference_ms"),
                "totalMs": self._p95("total_ms"),
            },
            "max": {
                "preprocessMs": self._max("preprocess_ms"),
                "inferenceMs": self._max("inference_ms"),
                "totalMs": self._max("total_ms"),
            },
        }
