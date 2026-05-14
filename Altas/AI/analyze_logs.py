import argparse
import json
from pathlib import Path

import pandas as pd


def calc_accuracy_by_mode(df):
    if "label" not in df.columns or "predicted_class" not in df.columns:
        return {}
    valid = df[df["label"] >= 0]
    if valid.empty:
        return {}
    grouped = valid.groupby("experiment_mode")
    return {mode: float((g["label"] == g["predicted_class"]).mean()) for mode, g in grouped}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--result", required=True)
    ap.add_argument("--perf", required=True)
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    result_df = pd.read_csv(args.result)
    perf_df = pd.read_csv(args.perf)

    acc = calc_accuracy_by_mode(result_df)
    valid_frames = int(len(perf_df))
    summary = {
        "valid_frames": valid_frames,
        "avg_inference_ms": float(perf_df["inference_ms"].mean()) if valid_frames else 0.0,
        "p95_inference_ms": float(perf_df["inference_ms"].quantile(0.95)) if valid_frames else 0.0,
        "max_inference_ms": float(perf_df["inference_ms"].max()) if valid_frames else 0.0,
        "avg_total_ms": float(perf_df["total_ms"].mean()) if valid_frames else 0.0,
        "p95_total_ms": float(perf_df["total_ms"].quantile(0.95)) if valid_frames else 0.0,
        "max_total_ms": float(perf_df["total_ms"].max()) if valid_frames else 0.0,
        "full_accuracy": float(acc.get("full", 0.0)),
        "no_audio_accuracy": float(acc.get("no_audio", 0.0)),
        "no_vibration_accuracy": float(acc.get("no_vibration", 0.0)),
        "no_temperature_accuracy": float(acc.get("no_temperature", 0.0)),
        "health_score_std": float(result_df["health_score"].std()) if "health_score" in result_df.columns else 0.0,
        "false_alarm_per_hour": 0.0,
    }
    if "false_alarm" in result_df.columns and "time" in result_df.columns and len(result_df) > 1:
        t0 = pd.to_datetime(result_df["time"].iloc[0])
        t1 = pd.to_datetime(result_df["time"].iloc[-1])
        duration_hours = max((t1 - t0).total_seconds() / 3600.0, 1e-6)
        summary["false_alarm_per_hour"] = float(result_df["false_alarm"].sum() / duration_hours)

    output = Path(args.output) if args.output else Path(args.result).with_name(Path(args.result).stem.replace("_result", "") + "_summary.json")
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
