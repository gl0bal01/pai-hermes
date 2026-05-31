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
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


DEFAULT_CACHE = "~/.claude/PAI/MEMORY/STATE/usage-cache.json"
DEFAULT_SNAPSHOT = "~/.hermes/state/pai-cost-snapshots.jsonl"

STALENESS_WARN_SECONDS = 15 * 60  # 15 min per SKILL.md

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
    # api_spend_alert_usd intentionally absent in 0.1.x — fetching admin API
    # spend is not yet implemented. Re-add when admin-key path lands.
}


def read_cache(path: str) -> dict:
    """Read PAI usage cache JSON; return empty dict if missing/unreadable."""
    p = Path(os.path.expanduser(path))
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def cache_age_seconds(path: str) -> Optional[float]:
    """Return mtime age of cache in seconds, or None if file missing."""
    p = Path(os.path.expanduser(path))
    if not p.exists():
        return None
    return time.time() - p.stat().st_mtime


def pct(d: dict) -> float:
    """Extract a percentage value. Treats explicit 0 as 0 (not falsy fallback)."""
    if not isinstance(d, dict):
        return 0.0
    v = d.get("used_percentage")
    if v is None:
        v = d.get("utilization")
    if v is None:
        return 0.0
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def extract_metrics(cache: dict) -> dict:
    """Pull 5h/7d/opus/sonnet/extra_usage out of the rate_limits block."""
    rl = cache.get("rate_limits") or {}
    if not isinstance(rl, dict):
        rl = {}
    five = rl.get("five_hour") or {}
    seven = rl.get("seven_day") or {}
    opus = rl.get("seven_day_opus") or {}
    sonnet = rl.get("seven_day_sonnet") or {}
    extra = rl.get("extra_usage") or {}

    used = extra.get("used_credits") or 0
    limit = extra.get("monthly_limit") or 0
    extra_pct = round(100 * used / limit, 1) if limit else 0.0

    return {
        "five_hour_pct": pct(five),
        "five_hour_reset": five.get("resets_at"),
        "seven_day_pct": pct(seven),
        "seven_day_reset": seven.get("resets_at"),
        "opus_7d_pct": pct(opus),
        "sonnet_7d_pct": pct(sonnet),
        "extra_credits_used_pct": extra_pct,
        "extra_credits_used": used,
        "extra_credits_limit": limit,
        "extra_enabled": bool(extra.get("is_enabled", False)),
    }


def classify(metrics: dict, thresholds: dict) -> dict:
    """Return {alerts, blocks} — names of metrics crossing thresholds."""
    alerts, blocks = [], []

    def at(metric_key: str, alert_key: str, block_key: Optional[str] = None):
        v = metrics.get(metric_key, 0)
        if block_key and v >= thresholds.get(block_key, 999):
            blocks.append(metric_key.replace("_pct", ""))
        elif v >= thresholds.get(alert_key, 999):
            alerts.append(metric_key.replace("_pct", ""))

    at("five_hour_pct", "five_hour_alert", "five_hour_block")
    at("seven_day_pct", "seven_day_alert", "seven_day_block")
    at("opus_7d_pct", "opus_7d_alert")
    at("sonnet_7d_pct", "sonnet_7d_alert")
    at("extra_credits_used_pct", "extra_credits_alert")

    return {"alerts": alerts, "blocks": blocks}


def compose_voice(metrics: dict, status: dict, stale_seconds: Optional[float] = None) -> str:
    """Compose a single line of voice-alert text. Empty if nothing to alert."""
    parts = []

    if stale_seconds is not None and stale_seconds > STALENESS_WARN_SECONDS:
        mins = int(stale_seconds / 60)
        parts.append(f"Warning: usage cache stale by {mins} minutes.")

    for key in status.get("blocks", []):
        if key == "five_hour":
            parts.append(f"Block triggered. Five hour window at {metrics['five_hour_pct']:.0f} percent. Stop now.")
        elif key == "seven_day":
            parts.append(f"Block triggered. Weekly Claude limit at {metrics['seven_day_pct']:.0f} percent.")

    for key in status.get("alerts", []):
        if key == "five_hour":
            parts.append(f"Five hour Claude window at {metrics['five_hour_pct']:.0f} percent. Consider a break.")
        elif key == "seven_day":
            parts.append(f"Weekly Claude limit at {metrics['seven_day_pct']:.0f} percent.")
        elif key == "opus_7d":
            parts.append(f"Opus weekly at {metrics['opus_7d_pct']:.0f} percent.")
        elif key == "sonnet_7d":
            parts.append(f"Sonnet weekly at {metrics['sonnet_7d_pct']:.0f} percent.")
        elif key == "extra_credits_used":
            parts.append(f"Extra credits at {metrics['extra_credits_used_pct']:.0f} percent of monthly limit.")

    return " ".join(parts)


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
        try:
            thresholds.update(json.loads(args.thresholds))
        except json.JSONDecodeError as exc:
            print(f"invalid --thresholds JSON: {exc}", file=sys.stderr)
            sys.exit(2)

    cache = read_cache(args.cache)
    metrics = extract_metrics(cache)
    status = classify(metrics, thresholds)
    stale = cache_age_seconds(args.cache)

    output = {
        "schema": "pai-hermes.cost.v1",
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cache_age_seconds": stale,
        "cache_stale": (stale is not None and stale > STALENESS_WARN_SECONDS),
        **metrics,
        "alerts_triggered": status["alerts"],
        "block_triggered": status["blocks"],
    }

    if args.snapshot:
        # M5 fix: resolve symlinks, require path under ~/.hermes/, open with
        # O_NOFOLLOW so cron-driven append cannot follow an attacker symlink
        # into an arbitrary file.
        log_path = Path(os.path.expanduser(args.snapshot_log)).resolve()
        hermes_home = Path(os.path.expanduser("~/.hermes")).resolve()
        if hermes_home != log_path and hermes_home not in log_path.parents:
            print(
                f"snapshot path must live under {hermes_home}/ "
                f"(got: {log_path})",
                file=sys.stderr,
            )
            sys.exit(2)
        log_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW
        fd = os.open(str(log_path), flags, 0o600)
        with os.fdopen(fd, "a") as f:
            f.write(json.dumps(output) + "\n")

    if args.voice:
        msg = compose_voice(metrics, status, stale)
        if msg:
            print(msg)
        # exit 0 even when no message (silence = within bounds)
    else:
        print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
