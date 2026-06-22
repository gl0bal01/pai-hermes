---
name: pai-statusline-banner
description: Daily digest of PAI ecosystem state pushed to mobile at 18:00 — Claude 5h/7d usage, pending proposals, doctor failures, leak detector flags, mood/git/learning signals from PAI Algorithm. Mirrors PAI canonical statusline visible-section into single message. Use when user says daily summary, what happened today, banner, digest, brief me.
---

# pai-statusline-banner skill

## What it provides

PAI canonical statusline shows on EVERY Claude Code render (Greeting → Wielding → Git → Learning → Signal → Context → Quote). Beautiful in Claude Code session. **Invisible in Hermes TUI** (different renderer) and **invisible when not at desk**.

This skill aggregates the same signals into a single text message pushed via `pai-pulse` to mobile at 18:00 daily. You get the PAI statusline vibe via voice + Pulse mobile UI, even when away from terminal.

## When to use

User intent:
- "daily summary", "brief me", "digest"
- Cron-driven 18:00 daily — see `cron/README.md` (Hermes jobs.json registration)
- On-demand "what happened today"

## Composed message structure

```
PAI digest — Friday May 16, 18:00 UTC

Usage:
  5h Claude: 42%  (resets 21:00)
  7d Claude: 38%  (Opus 55%, Sonnet 22%)
  API spend month: $12.40

Ecosystem:
  doctor: 23 pass / 2 fail (arecord_present, whisper_model_present)
  proposals pending: 2  (omc abc1234, pai-anywhere def5678)
  leak detector: clean (no new ANTHROPIC_API_KEY call-sites)

Activity (PAI Algorithm signal):
  commits today: 7
  skills used today: ralph, science, telos
  mood: + 4  ~ 2  - 1
  learning entries: 3

Top quote: "<from PAI Quote rotation>"
```

## Algorithm

1. Read PAI usage cache → format 5h/7d.
2. Run `pai-doctor` skill internally → count pass/fail.
3. List proposals from `$PAI_PROPOSALS_DIR/*.json` where `.status=="pending"`.
4. Read PAI CostTracker latest entry → API spend + leak detector flags.
5. Read PAI MEMORY signals (git activity today, skills_used.jsonl, mood from DAGrowth.ts, learning entries count).
6. Pick quote from PAI canonical Quote pool (rotation).
7. Compose plaintext message.
8. POST via `pai-pulse` skill → ElevenLabs TTS + mobile push.

## Inputs (env)

| Env var | Default | Purpose |
|---------|---------|---------|
| `PAI_USAGE_CACHE` | `~/.claude/PAI/MEMORY/STATE/usage-cache.json` | usage source |
| `PAI_PROPOSALS_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/pai-hermes/proposals` | proposals dir (shared with `pai-watch`; set in `$HERMES_HOME/pai-hermes.env` by `install.sh`) |
| `PAI_ALGO_MEMORY` | `~/.claude/PAI/MEMORY/SKILLS/Algorithm/` | mood / commits / learning |
| `PAI_QUOTES_FILE` | `~/.claude/PAI/USER/SHARED/Quotes/quotes.jsonl` | quote pool |
| `PAI_BANNER_TIME` | `18:00` | daily schedule (override via Hermes config) |

## Cron entry

Register via Hermes — see `cron/README.md`. Job is stored in `~/.hermes/cron/jobs.json`:

```json
{ "name": "pai-statusline-banner", "schedule": { "kind": "cron", "expr": "0 18 * * *" }, "skill": "pai-statusline-banner" }
```

## Output

JSON (returned to Hermes context if invoked on-demand):
```
{
  "schema": "pai-hermes.banner.v1",
  "ts": "2026-05-16T18:00:00Z",
  "message": "<composed plaintext>",
  "sent_via": ["pulse-notify", "telegram"],
  "alerts_inline": ["five_hour at 82%"]
}
```

If invoked as cron, returns nothing to context — just posts and logs.

## Coordination with other skills

- Calls `pai-doctor` for fail count.
- Calls `pai-cost-tracker` for usage % (without re-fetching cache).
- Calls `pai-pulse` for delivery.

Skill chain pattern: banner is composer, others are providers.

## Caveats

- 18:00 default may not match user timezone — read `TZ` env or Hermes config.
- Mobile push relies on Pulse `/notify` reaching mobile via Tailscale — verify with `pai-doctor` before scheduling.
- Quote pool from PAI canonical may not exist on fresh install — fallback to empty quote section.
- DAGrowth.ts mood may be macOS-only — gracefully skip if file absent.
- `PAI_PROPOSALS_DIR` defaults to the Hermes user's state dir and is written to `$HERMES_HOME/pai-hermes.env` by `install.sh`. `PAI_ALGO_MEMORY` and `PAI_QUOTES_FILE` remain operator-set; they are read as-is with no further validation. Recommended locations: under `~/.claude/`.

## Cost

ZERO AI cost. Aggregation + Pulse POST. ElevenLabs cost = single short TTS synthesis (~$0.001).

## Triggers in Hermes natural language

- "brief me" → on-demand banner
- "daily summary now" → on-demand banner
- "what happened today" → banner with extended commits + skills list
- Cron-fired at 18:00 — silent in TUI, lands on mobile
