#!/usr/bin/env python3
"""
cost_check.py — helper for pai-cost-tracker skill.

Reads PAI canonical usage cache JSON, classifies against thresholds,
emits structured JSON suitable for Hermes context or voice alert composition.

Usage:
    python3 cost_check.py [--cache PATH] [--thresholds JSON]
    python3 cost_check.py --snapshot         # append to snapshots.jsonl
    python3 cost_check.py --voice            # emit voice alert message text

Zero AI cost — pure file reads + threshold logic.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_CACHE = "~/.claude/PAI/MEMORY/STATE/usage-cache.json"
DEFAULT_SNAPSHOT = "~/.hermes/state/pai-cost-snapshots.jsonl"

DEFAULT_THRESHOLDS = {
    "five_hour_warn": 60,
    "five_hour_alert": 80,
    "five_hour_block": 95,
    "seven_day_warn": 70,
    "seven_day_alert": 85,
    "seven_day_block": 95,
    "opus_7d_alert": 90,
    "sonnet_7d_alert": 90,
    "extra_credits_alert": 70,
    "api_spend_alert_usd": 150,
}


def read_cache(path: str) -> dict:
    p = Path(os.path.expanduser(path))
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def extract_metrics(cache: dict) -> dict:
    """Pull 5h/7d/opus/sonnet/extra_usage out of the rate_limits block."""
    rl = cache.get("rate_limits", {}) or {}
    five = rl.get("five_hour", {}) or {}
    seven = rl.get("seven_day", {}) or {}
    opus = rl.get("seven_day_opus", {}) or {}
    sonnet = rl.get("seven_day_sonnet", {}) or {}
    extra = rl.get("extra_usage", {}) or {}

    extra_pct = 0
    if extra.get("monthly_limit"):
        extra_pct = round(100 * extra.get("used_credits", 0) / extra["monthly_limit"], 1)

    return {
        "five_hour_pct": pct(five),
        "five_hour_reset": five.get("resets_at"),
        "seven_day_pct": pct(seven),
        "seven_day_reset": seven.get("resets_at"),
        "opus_7d_pct": pct(opus),
        "sonnet_7d_pct": pct(sonnet),
        "extra_credits_used_pct": extra_pct,
        "extra_credits_used": extra.get("used_credits", 0),
        "extra_credits_limit": extra.get("monthly_limit", 0),
        "extra_enabled": extra.get("is_enabled", False),
    }


def pct(d: dict) -> float:
    return d.get("used_percentage") or d.get("utilization") or 0


def classify(metrics: dict, thresholds: dict) -> dict:
    alerts = []
    blocks = []
    if metrics["five_hour_pct"] >= thresholds["five_hour_block"]:
        blocks.append("five_hour")
    elif metrics["five_hour_pct"] >= thresholds["five_hour_alert"]:
        alerts.append("five_hour")
    if metrics["seven_day_pct"] >= thresholds["seven_day_block"]:
        blocks.append("seven_day")
    elif metrics["seven_day_pct"] >= thresholds["seven_day_alert"]:
        alerts.append("seven_day")
    if metrics["opus_7d_pct"] >= thresholds["opus_7d_alert"]:
        alerts.append("opus_7d")
    if metrics["sonnet_7d_pct"] >= thresholds["sonnet_7d_alert"]:
        alerts.append("sonnet_7d")
    if metrics["extra_credits_used_pct"] >= thresholds["extra_credits_alert"]:
        alerts.append("extra_credits")
    return {"alerts": alerts, "blocks": blocks}


def compose_voice(metrics: dict, status: dict) -> str:
    parts = []
    for key in status["blocks"]:
        if key == "five_hour":
            parts.append(f"Block triggered. Five hour window at {metrics['five_hour_pct']} percent. Stop now.")
        elif key == "seven_day":
            parts.append(f"Block triggered. Weekly Claude limit at {metrics['seven_day_pct']} percent.")
    for key in status["alerts"]:
        if key == "five_hour":
            parts.append(f"Five hour Claude window at {metrics['five_hour_pct']} percent. Consider a break.")
        elif key == "seven_day":
            parts.append(f"Weekly Claude limit at {metrics['seven_day_pct']} percent.")
        elif key == "opus_7d":
            parts.append(f"Opus weekly at {metrics['opus_7d_pct']} percent.")
        elif key == "sonnet_7d":
            parts.append(f"Sonnet weekly at {metrics['sonnet_7d_pct']} percent.")
        elif key == "extra_credits":
            parts.append(
                f"Extra credits at {metrics['extra_credits_used_pct']} percent of monthly limit."
            )
    return " ".join(parts) if parts else "All Claude usage windows within bounds."


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--snapshot-log", default=DEFAULT_SNAPSHOT)
    ap.add_argument("--thresholds", help="JSON string overriding defaults")
    ap.add_argument("--snapshot", action="store_true", help="append snapshot to jsonl")
    ap.add_argument("--voice", action="store_true", help="emit only voice alert text")
    args = ap.parse_args()

    thresholds = DEFAULT_THRESHOLDS.copy()
    if args.thresholds:
        thresholds.update(json.loads(args.thresholds))

    cache = read_cache(args.cache)
    metrics = extract_metrics(cache)
    status = classify(metrics, thresholds)

    output = {
        "schema": "pai-hermes.cost.v1",
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **metrics,
        "alerts_triggered": status["alerts"],
        "block_triggered": status["blocks"],
    }

    if args.snapshot:
        log_path = Path(os.path.expanduser(args.snapshot_log))
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a") as f:
            f.write(json.dumps(output) + "\n")

    if args.voice:
        print(compose_voice(metrics, status))
    else:
        print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
