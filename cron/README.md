# cron/

> **0.1.1 note** — Hermes cron is **not yaml-file-based**. Earlier 0.1.0 shipped 3 yaml files on the assumption that `~/.hermes/cron/*.yaml` was the integration point. **It is not.** Real Hermes cron uses `~/.hermes/cron/jobs.json` written by the `cronjob` tool (`hermes-agent/tools/cronjob_tools.py`).
>
> This directory now documents the 3 jobs you should register **via Hermes itself**. Run the commands below from a Hermes session (TUI, Telegram, etc.). The agent will call its `cronjob` tool to add entries to `jobs.json`.

## Schema reference

Real Hermes job schema (excerpt, from `~/.hermes/cron/jobs.json`):

```json
{
  "id": "auto-generated",
  "name": "human-readable",
  "prompt": "free-text prompt the agent runs",
  "skills": ["restrict-to-this-skill"],
  "schedule": { "kind": "cron", "expr": "0 * * * *" },
  "enabled": true,
  "deliver": "telegram",
  "origin": { "platform": "telegram", "chat_id": "...", "chat_name": "..." }
}
```

`prompt` runs in a fresh session with full tool access — Hermes scans for high-risk patterns before accepting.

## 3 jobs to register

Ask Hermes to register each. The exact CLI / tool-call shape depends on your Hermes version — adapt as needed.

### 1. pai-watch (hourly)

```
Register a cron job:
  name: pai-watch
  schedule: 0 * * * *
  skill: pai-watch
  prompt: "Run the pai-watch skill. Sources: oh-my-claudecode, Personal_AI_Infrastructure, pai-anywhere, pai-review-mode. Threshold: 10. If proposals generated, push a short summary via pai-pulse skill."
  deliver: telegram (or your preferred platform)
```

### 2. pai-cost-tracker (hourly)

```
Register a cron job:
  name: pai-cost-tracker
  schedule: 0 * * * *
  skill: pai-cost-tracker
  prompt: "Run the pai-cost-tracker skill. Call tools/cost_check.py --voice. If output non-empty, send via pai-pulse skill. Respect quiet hours 22:00-07:00 (skip voice during these hours, log only)."
  deliver: telegram
```

### 3. pai-statusline-banner (daily 18:00)

```
Register a cron job:
  name: pai-statusline-banner
  schedule: 0 18 * * *
  skill: pai-statusline-banner
  prompt: "Run the pai-statusline-banner skill. Compose the daily PAI ecosystem digest (5h/7d usage, proposals pending, doctor failures, mood, top quote). Deliver via pai-pulse and Telegram."
  deliver: telegram
```

## Why this changed

0.1.0 cron yaml files made wrong assumptions:
- ❌ Files in `~/.hermes/cron/*.yaml` are loaded automatically — **false**
- ❌ Schema is yaml — **false** (real schema is JSON in `jobs.json`)
- ❌ install.sh can symlink job entries — **false** (job state is managed by `cronjob` tool, including derived fields like `next_run_at`, `created_at`, `origin`)

0.1.1 stops guessing. Real registration goes through Hermes.

## Future automation (0.2.0 candidate)

If you want fully automated registration, write a `cron/install-cron-jobs.sh` that runs `hermes cronjob create ...` for each of the 3 jobs. Requires verifying the exact `hermes` CLI flag set on your Hermes version. Not shipped in 0.1.1 because flag stability across Hermes versions isn't yet known.

For now: manual registration via Hermes prompt is the safe path.

## Verification

After registering, list jobs:

```
Ask Hermes: "List my cron jobs."
```

Or inspect directly (read-only):

```bash
jq '.jobs[] | {name, schedule: .schedule.expr, enabled}' ~/.hermes/cron/jobs.json
```

Expected: 3 jobs named `pai-watch`, `pai-cost-tracker`, `pai-statusline-banner`, all `enabled: true`.
