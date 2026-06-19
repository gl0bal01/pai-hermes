# HERMES_CONTRACT — operating rules for pai-hermes skills

> Distilled from [`gl0bal01/contract-agents`](https://github.com/gl0bal01/contract-agents) `AGENTS_CONTRACT.md` v2.0 (MIT). Adapted for Hermes single-agent + skills + cron runtime. Rules below bind every skill in `skills/` and every cron entry in `cron/`. When skill body conflicts with this contract, contract wins.

---

## 1. Scope discipline

Touch only what skill description names. A skill MUST NOT:
- Refactor unrelated Hermes config keys.
- Rename or reformat user files outside its declared write surface.
- Delete "unused" entries from `~/.hermes/config.yaml`.

If skill discovers adjacent issues: emit them under `POTENTIAL FOLLOW-UPS` in output, do not act.

Maps to pai-hermes CLAUDE.md "Composition rule" — additive only.

## 2. Evidence rules

Skill output that asserts state MUST cite source:
- File claims → `path:line` (e.g. `~/.hermes/config.yaml:42`).
- Usage / cost claims → JSON path + key (e.g. `usage-cache.json#five_hour.percent`).
- Upstream claims → commit SHA + repo (e.g. `Personal_AI_Infrastructure@a1b2c3d`).
- Network claims → HTTP status + endpoint (e.g. `127.0.0.1:31337/notify → 200`).

Unverified guesses MUST be labeled `assumption:` inline. No silent inference.

## 3. Approval gates

Skill MUST stop and request explicit user confirmation before:
- Writing to `/etc/pai/paths.env` (SHA pin change → `pai-accept` SSH-only).
- Writing to `pai-collab/projects/arc/reviews/*.md` (AGPL boundary — content flows in, MIT stays in pai-hermes).
- Editing `~/.hermes/config.yaml` non-additively (only `install.sh` may, and only additively).
- Invoking high-cost OMC modes (`ralph`, `team`, `autopilot`, `ultrawork`) when `pai-cost-tracker` 5h window ≥80% ALERT or ≥95% BLOCK (per `tools/cost_check.py` DEFAULT_THRESHOLDS).
- Triggering Pulse voice alerts during quiet hours.

Cron jobs MUST NOT bypass gates. Cron emits proposal → user accepts via SSH.

## 4. Security

First-class per pai-hermes CLAUDE.md §"Auth" + §"Cost":
- `pai-accept` SSH-only. Never callable via Pulse, gateway, Telegram, Discord, Signal, WhatsApp.
- No secrets in skill body, skill stdout, cron yaml, or Pulse payload.
- No new public Pulse routes (Miessler boundary).
- Voice alerts respect quiet hours.
- Gateway proxy stays read-only (`/proposals/<id>` GET; POST/DELETE → 405).
- AGPL contagion guard: no embedding `pai-collab` source, no linking `pai-collab` modules, no copying `pai-collab` text content. Filesystem write only.

## 5. Verification

Every skill MUST publish a `HOW TO VERIFY` block. Preference order:
1. Automated — `bats tests/skill-format.bats`.
2. Focused command — single shell line user can paste (e.g. `jq '.five_hour.percent' ~/.claude/PAI/MEMORY/STATE/usage-cache.json`).
3. Manual check — config path + expected substring.

Skill output ends with: `STATUS: PASS | CONCERNS | FAIL | BLOCKED`.

`BLOCKED` requires reason + minimal question to unblock.

## 6. Cost discipline (Hermes-specific)

Beyond `AGENTS_CONTRACT.md`:
- Cron jobs MUST be zero-AI-cost. No LLM invocation in `pai-watch`, `pai-cost-tracker`, `pai-statusline-banner`.
- Skills MAY invoke LLM only on user request.
- `pai-cost-tracker` gate is hard, not advisory.

## 7. Failure modes

Every skill body MUST include `Caveats` section listing failure paths + fallback:
- Pulse unreachable → fallback Hermes native TTS.
- arc dir absent → skip markdown write, paths.env update still happens.
- Usage cache stale (>15 min) → warning in output.
- `arecord` / Whisper.cpp missing → exit 78 (config error), do not retry.

---

## What this contract is NOT

- Not a delegation policy. Hermes is single-agent; no sub-agent spawn primitive.
- Not a commit / lessons.md loop. Use OMC for that surface.
- Not a global Claude Code agent governance doc. For that, see [`gl0bal01/contract-agents`](https://github.com/gl0bal01/contract-agents) and [`gl0bal01/black-box-architecture`](https://github.com/gl0bal01/black-box-architecture) — install separately at `~/.claude/agents/`.

## Provenance

Sections 1, 2, 3, 4, 5 derived from `AGENTS_CONTRACT.md` v2.0 §1, §4, §5, §6, §7 (MIT). Sections 6, 7 are pai-hermes additions for cron + skill runtime.
