---
name: pai-cost-tracker
description: Hourly Claude subscription usage guardrail. Reads PAI canonical usage cache (~/.claude/PAI/MEMORY/STATE/usage-cache.json) for 5h/7d window percentages. Voice-alert via pai-pulse if threshold exceeded. Use when user says usage, cost, am I burning too much, take a break, claude limit, rate limit.
---

# pai-cost-tracker skill

## Why this exists

PAI canonical's `CostTracker.ts` ledger documents real story: **April 2026 invoice was $498.45**, dominated by processes that billed API instead of subscription. Leak undetected until monthly invoice. This skill closes that feedback loop on Hermes side.

Also: wellness. "Working too much" = approaching 5h/7d Claude subscription limit. Voice alert tells user to stop.

## When to use

User intent:
- "usage" → snapshot current 5h/7d %
- "am I close to limit" → threshold check
- "cost this month" → API spend from admin key (if available)
- Automated hourly cron — see `cron/pai-cost-tracker.yaml`

## Data sources

| Source | What | Path |
|--------|------|------|
| PAI usage cache | 5h/7d %, native rate_limits | `~/.claude/PAI/MEMORY/STATE/usage-cache.json` |
| PAI CostTracker ledger | Historical snapshots | `~/.claude/PAI/MEMORY/OBSERVABILITY/anthropic-cost.jsonl` |
| Hermes own model usage | Multi-provider tokens consumed | `~/.hermes/state.db` (sqlite, table TBD) |
| Anthropic admin API | API spend $ this month | requires `ANTHROPIC_ADMIN_API_KEY` env |

## Thresholds (default)

| Window | Warn | Alert (voice) | Block |
|--------|------|---------------|-------|
| 5h Claude | 60% | 80% | 95% |
| 7d Claude | 70% | 85% | 95% |
| 7d Opus-specific | 75% | 90% | 95% |
| 7d Sonnet-specific | 75% | 90% | 95% |
| Monthly extra_usage credits | 40% | 70% | 90% |
| API spend (admin key) | $50 | $150 | $400 |

Configurable in `~/.hermes/config.yaml` under `pai_hermes.cost_thresholds:`.

## Algorithm

1. Read `usage-cache.json` JSON.
2. Extract fields:
   - `rate_limits.five_hour.used_percentage`
   - `rate_limits.seven_day.used_percentage`
   - `rate_limits.seven_day_opus.used_percentage`
   - `rate_limits.seven_day_sonnet.used_percentage`
   - `rate_limits.extra_usage.used_credits` / `.monthly_limit`
3. For each, classify against threshold.
4. If ANY at "Alert" level OR "Block" level → invoke `pai-pulse` skill with composed message:
   - "Take a break — 5h window at 82%."
   - "Approaching 7d limit — 88% used, 14h until reset."
5. If at "Block" level → also tag message with priority + push to Telegram via Hermes gateway.
6. Append snapshot to `~/.hermes/state/pai-cost-snapshots.jsonl` (audit trail).
7. Return JSON summary for in-context display.

## Output

```
{
  "schema": "pai-hermes.cost.v1",
  "ts": "2026-05-16T15:00:00Z",
  "five_hour_pct": 78,
  "seven_day_pct": 52,
  "opus_7d_pct": 65,
  "sonnet_7d_pct": 30,
  "extra_credits_used_pct": 12,
  "api_spend_month_usd": 0,
  "alerts_triggered": ["five_hour"],
  "block_triggered": [],
  "next_reset_5h": "2026-05-16T18:00:00Z"
}
```

## Voice alert composition

Templates per trigger:
- `five_hour Alert`: "5 hour Claude window at {pct}%. Consider taking a break."
- `seven_day Alert`: "Weekly Claude limit at {pct}%. Reset in {hours} hours."
- `extra_credits Alert`: "Extra credits at {pct}% of monthly limit. ${used} of ${limit}."
- `api_spend Alert`: "API spend this month {usd_used} dollars. Watch for leaks."

Sent via `pai-pulse` skill (ElevenLabs TTS through Pulse).

## Cron entry

See `cron/pai-cost-tracker.yaml`:

```yaml
name: pai-cost-tracker
schedule: "0 * * * *"     # hourly
task: "Run pai-cost-tracker skill, voice-alert if threshold exceeded"
```

## Coordination with omc skill

`omc` skill should call `pai-cost-tracker` PRE-FLIGHT before launching:
- ralph, autopilot, team, ultrawork (HIGH cost class)

If 5h window >85%, refuse launch:
```
omc: pre-flight refused. 5h window at 87%. Resume after {reset_time}.
Override: explicit --force flag from user.
```

## Caveats

- `usage-cache.json` schema is PAI canonical's. If Miessler changes format in v6+, this skill needs update.
- 5h/7d % from Claude OAuth API has aggressive rate limits (5 reads before 429). Cron at hourly is safe.
- Hermes own model usage (z.ai/GLM, OpenRouter, etc.) NOT included in Claude windows — adds to overall AI spend separately.
- Voice alerts at night can be silenced via Hermes config quiet hours.

## Cost

ZERO AI cost. File reads + JSON parsing + optional Pulse POST.

## Triggers in Hermes natural language

- "how much have I used" → snapshot
- "am I close to limit" → threshold check, summarize
- "what's my burn rate" → trend from snapshots jsonl
- Pre-flight before `omc ralph` etc. — silent unless threshold hit
