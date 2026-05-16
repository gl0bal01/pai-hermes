"""pytest suite for tools/cost_check.py — pct() edge cases, classification,
voice composition, staleness."""

import json
import os
import sys
import tempfile
import time
from pathlib import Path

import pytest

# Make tools/ importable
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import cost_check as cc  # noqa: E402


# ---------------------------------------------------------------- pct() ----

def test_pct_zero_genuine_returns_zero():
    """0% used must return 0.0, NOT fall through to utilization or default."""
    assert cc.pct({"used_percentage": 0}) == 0.0
    assert cc.pct({"used_percentage": 0, "utilization": 42}) == 0.0


def test_pct_prefers_used_percentage_over_utilization():
    assert cc.pct({"used_percentage": 55, "utilization": 99}) == 55.0


def test_pct_falls_back_to_utilization_when_used_percentage_missing():
    assert cc.pct({"utilization": 33}) == 33.0


def test_pct_none_when_both_missing():
    assert cc.pct({}) == 0.0
    assert cc.pct({"other_key": 99}) == 0.0


def test_pct_handles_none_values_explicitly():
    assert cc.pct({"used_percentage": None}) == 0.0
    assert cc.pct({"used_percentage": None, "utilization": 77}) == 77.0


def test_pct_not_dict_returns_zero():
    assert cc.pct(None) == 0.0
    assert cc.pct("not a dict") == 0.0
    assert cc.pct(42) == 0.0


def test_pct_handles_string_numbers():
    assert cc.pct({"used_percentage": "65"}) == 65.0


def test_pct_handles_garbage_gracefully():
    assert cc.pct({"used_percentage": "not-a-number"}) == 0.0


# ---------------------------------------------------- extract_metrics() ----

def test_extract_metrics_empty_cache_returns_zeros():
    m = cc.extract_metrics({})
    assert m["five_hour_pct"] == 0.0
    assert m["seven_day_pct"] == 0.0
    assert m["extra_credits_used_pct"] == 0.0
    assert m["extra_enabled"] is False


def test_extract_metrics_full_cache():
    cache = {
        "rate_limits": {
            "five_hour": {"used_percentage": 82, "resets_at": "2026-05-16T21:00:00Z"},
            "seven_day": {"used_percentage": 45},
            "seven_day_opus": {"used_percentage": 70},
            "seven_day_sonnet": {"used_percentage": 20},
            "extra_usage": {"used_credits": 50, "monthly_limit": 200, "is_enabled": True},
        }
    }
    m = cc.extract_metrics(cache)
    assert m["five_hour_pct"] == 82.0
    assert m["seven_day_pct"] == 45.0
    assert m["opus_7d_pct"] == 70.0
    assert m["sonnet_7d_pct"] == 20.0
    assert m["extra_credits_used_pct"] == 25.0  # 50/200 * 100
    assert m["extra_enabled"] is True
    assert m["five_hour_reset"] == "2026-05-16T21:00:00Z"


def test_extract_metrics_partial_rate_limits():
    """Real-world: some blocks may be absent."""
    cache = {"rate_limits": {"five_hour": {"used_percentage": 30}}}
    m = cc.extract_metrics(cache)
    assert m["five_hour_pct"] == 30.0
    assert m["seven_day_pct"] == 0.0
    assert m["opus_7d_pct"] == 0.0


def test_extract_metrics_zero_division_safe():
    cache = {"rate_limits": {"extra_usage": {"used_credits": 5, "monthly_limit": 0}}}
    m = cc.extract_metrics(cache)
    assert m["extra_credits_used_pct"] == 0.0  # not crash


# --------------------------------------------------------- classify() ----

def test_classify_no_alerts_when_below_thresholds():
    m = {"five_hour_pct": 50, "seven_day_pct": 30, "opus_7d_pct": 10,
         "sonnet_7d_pct": 10, "extra_credits_used_pct": 5}
    s = cc.classify(m, cc.DEFAULT_THRESHOLDS)
    assert s == {"alerts": [], "blocks": []}


def test_classify_alert_on_five_hour():
    m = {"five_hour_pct": 85, "seven_day_pct": 0, "opus_7d_pct": 0,
         "sonnet_7d_pct": 0, "extra_credits_used_pct": 0}
    s = cc.classify(m, cc.DEFAULT_THRESHOLDS)
    assert "five_hour" in s["alerts"]
    assert s["blocks"] == []


def test_classify_block_supersedes_alert():
    """Once block threshold crossed, classify as block (not double-counted)."""
    m = {"five_hour_pct": 98, "seven_day_pct": 0, "opus_7d_pct": 0,
         "sonnet_7d_pct": 0, "extra_credits_used_pct": 0}
    s = cc.classify(m, cc.DEFAULT_THRESHOLDS)
    assert "five_hour" in s["blocks"]
    assert "five_hour" not in s["alerts"]


def test_classify_extra_credits_alert():
    m = {"five_hour_pct": 0, "seven_day_pct": 0, "opus_7d_pct": 0,
         "sonnet_7d_pct": 0, "extra_credits_used_pct": 75}
    s = cc.classify(m, cc.DEFAULT_THRESHOLDS)
    assert "extra_credits_used" in s["alerts"]


# ---------------------------------------------------- compose_voice() ----

def test_compose_voice_silent_when_nothing_triggered():
    assert cc.compose_voice({}, {"alerts": [], "blocks": []}) == ""


def test_compose_voice_five_hour_alert():
    m = {"five_hour_pct": 82}
    out = cc.compose_voice(m, {"alerts": ["five_hour"], "blocks": []})
    assert "82" in out
    assert "five hour" in out.lower() or "Five hour" in out


def test_compose_voice_block_message_is_stronger():
    m = {"five_hour_pct": 98}
    out = cc.compose_voice(m, {"alerts": [], "blocks": ["five_hour"]})
    assert "Stop" in out or "Block" in out


def test_compose_voice_warns_when_cache_stale():
    out = cc.compose_voice({}, {"alerts": [], "blocks": []}, stale_seconds=20 * 60)
    assert "stale" in out.lower()


def test_compose_voice_no_stale_when_fresh():
    out = cc.compose_voice({"five_hour_pct": 50}, {"alerts": [], "blocks": []}, stale_seconds=5 * 60)
    assert "stale" not in out.lower()


# ---------------------------------------------------- read_cache + age ----

def test_read_cache_missing_file_returns_empty_dict(tmp_path):
    missing = tmp_path / "absent.json"
    assert cc.read_cache(str(missing)) == {}


def test_read_cache_invalid_json_returns_empty(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    assert cc.read_cache(str(bad)) == {}


def test_read_cache_valid_json(tmp_path):
    good = tmp_path / "ok.json"
    good.write_text(json.dumps({"hello": "world"}))
    assert cc.read_cache(str(good)) == {"hello": "world"}


def test_cache_age_seconds_missing_returns_none(tmp_path):
    assert cc.cache_age_seconds(str(tmp_path / "absent")) is None


def test_cache_age_seconds_fresh_file_under_one_second(tmp_path):
    p = tmp_path / "fresh.json"
    p.write_text("{}")
    age = cc.cache_age_seconds(str(p))
    assert age is not None
    assert age >= 0
    assert age < 5  # should be near-zero


# ---------------------------------------------------- end-to-end smoke ----

def test_end_to_end_with_synthetic_cache(tmp_path):
    cache_path = tmp_path / "usage-cache.json"
    cache_path.write_text(json.dumps({
        "rate_limits": {
            "five_hour": {"used_percentage": 85},
            "seven_day": {"used_percentage": 50},
        }
    }))
    metrics = cc.extract_metrics(cc.read_cache(str(cache_path)))
    status = cc.classify(metrics, cc.DEFAULT_THRESHOLDS)
    assert "five_hour" in status["alerts"]
    msg = cc.compose_voice(metrics, status)
    assert "85" in msg
