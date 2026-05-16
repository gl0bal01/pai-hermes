# Changelog

## [0.1.1] — 2026-05-16 — Review-driven fixes

Addresses external code review of 0.1.0. All 5 "must fix" items + 6 of 7 "missing" items resolved. One deferred (Anthropic admin-API spend fetch) with honest removal from output schema.

### Fixed

- **`tools/cost_check.py` pct() zero-falsy bug**: `d.get("used_percentage") or d.get("utilization") or 0` silently swapped a genuine `0%` for `utilization` or `0`. Now uses explicit `None` checks. Added type coercion + non-dict guard. (Review item #1.)
- **`install.sh` YAML patcher**: regex-on-YAML replaced with PyYAML (`yaml.safe_load` + `yaml.safe_dump`). Idempotent. Pre-edit backup `.bak` + post-edit YAML parse validation; **rollback to backup on any parse failure**. (Review items #2, #7 — "no rollback in install.sh".)
- **Cron pivot**: deleted 3 yaml files (`cron/pai-*.yaml`). Hermes cron is JSON-based (`~/.hermes/cron/jobs.json`), managed by Hermes's own `cronjob` tool — yaml files were never the integration point. Replaced with `cron/README.md` documenting the 3 jobs as manual registration prompts to run inside a Hermes session. (Review item #4 — biggest correctness gap.)
- **`bin/pai-accept-guard`** (NEW, 90 LOC bash): shell-level enforcer of SSH-only constraint that was previously markdown-only. Refuses non-SSH invocation with `exit 77` (EX_NOPERM). Adds: input validation regex (`exit 65` EX_DATAERR), `flock` with timeout (`exit 75` EX_TEMPFAIL on contention), atomic `paths.env` mutation (write-tmp-then-`mv`), atomic proposal status update. Override only via env (`PAI_LOCAL_OVERRIDE=1`), never CLI flag. (Review items #5, "race condition in pai-accept".)
- **`skills/pai-accept/SKILL.md`**: now mandates invoking `pai-accept-guard` instead of inline bash. Markdown rules remain advisory; guard is the actual security boundary.
- **Skill-chaining contradiction in `CLAUDE.md`**: previous rule "Skills do NOT invoke each other" contradicted statusline-banner/watch/cost-tracker chaining patterns. Clarified: skills MAY recommend chains via prose hints; Hermes is always the orchestrator; the graph is a strict DAG (no cycles). (Review item #3.)
- **Placeholder URLs**: `README.md` + `docs/INSTALL.md` `<you>` → `gl0bal01`. (Review item "README has placeholder URL".)

### Added

- **`tests/test_cost_check.py`** (NEW, 27 pytest tests): pct() edge cases (zero, None, string, garbage, non-dict), extract_metrics partial/empty/zero-division, classify alert+block precedence, compose_voice silence-when-clean + staleness-warning, read_cache invalid-JSON, cache_age missing-file. (Review item "no unit tests".)
- **`tools/cost_check.py` staleness check**: cache mtime read; output schema gains `cache_age_seconds` + `cache_stale` (boolean); `compose_voice` prepends "usage cache stale by N minutes" when threshold (15 min per SKILL.md) crossed. (Review item "no staleness check".)
- **`.github/workflows/test.yml`** (NEW): CI runs `shellcheck` (install/uninstall/guard), `bats` (skill-format suite), `pytest` (cost_check), and a smoke test asserting `pai-accept-guard` returns 77 in non-SSH context. Triggered on push to main + PRs. (Review item "no CI".)
- **`tests/skill-format.bats`**: new tests verifying cron/README.md documents the 3 jobs, no yaml files remain, and pai-accept-guard refuses non-SSH (exit 77).

### Removed

- **`api_spend_month_usd`** from `DEFAULT_THRESHOLDS` + output schema. 0.1.0 declared it but never computed (admin-API path not implemented). Honest removal until admin-key fetch ships. (Review item "api_spend_month_usd never computed".)
- 3 obsolete cron yaml files (replaced by cron/README.md).

### Changed

- `uninstall.sh`: matches `install.sh` — pyyaml-based external_dirs removal + validate + rollback on parse failure. Reminds user to delete cron jobs via Hermes (not filesystem) since cron was never symlinked.
- `tools/cost_check.py` `extract_metrics`: defensive `or {}` on every dict access; zero-division-safe extra_credits percentage.

### Test status

- 27/27 pytest (`tests/test_cost_check.py`) ✓
- 15/15 bats (`tests/skill-format.bats`) ✓
- shellcheck clean on `install.sh`, `uninstall.sh`, `bin/pai-accept-guard` ✓
- `pai-accept-guard fake-id` (no SSH env) → exit 77 ✓

### Known limitations (still in 0.1.1)

- Hermes cron job registration is **manual prompt-based** (see `cron/README.md`). 0.2.0 candidate: ship `cron/install-cron-jobs.sh` using `hermes cronjob create ...` once flag set is verified across versions.
- Anthropic admin-API spend fetch deferred — `api_spend` removed from schema rather than stubbed.
- Live Hermes integration runtime still unverified (skills written, never loaded by an actual Hermes session).

## [0.1.0] — 2026-05-16 — Initial scaffold

Initial scaffold drafted in same session as `pai-projet` 540 LOC bash router. Concluded `pai-projet` overlapped Hermes 70% and pivoted to this bridge approach.

### Added

- 7 SKILL.md drafts:
  - `omc` — Claude Code harness routing (ralph/team/autopilot/ultrawork/ask).
  - `pai-pulse` — Pulse `/notify` TTS POST wrapper.
  - `pai-watch` — `git fetch` × 4 sources + impact-score + JSON proposal writer.
  - `pai-doctor` — PAI ecosystem health probes (Pulse, Tailscale, paths, statusline files, OMC CLI).
  - `pai-accept` — SHA pin in paths.env + arc review markdown. SSH-only.
  - `pai-cost-tracker` — 5h/7d Claude usage % via `~/.claude/PAI/MEMORY/STATE/usage-cache.json` + voice-alert at threshold.
  - `pai-statusline-banner` — Daily 18:00 digest of 5h/7d/leaks pushed to mobile.
- 3 Hermes cron yaml entries (`pai-watch` hourly, `pai-cost-tracker` hourly, `pai-statusline-banner` daily 18:00).
- `install.sh` — idempotent editor of `~/.hermes/config.yaml` (`skills.external_dirs` + cron registration).
- `uninstall.sh` — reverses install via marker comments.
- `tools/cost_check.py` — optional helper for cost-tracker skill (subprocess-callable, reads PAI usage cache + emits JSON).
- `tests/skill-format.bats` — validates SKILL.md frontmatter on all 7 skills.
- `docs/INSTALL.md` — VPS deploy walkthrough.
- `docs/ARCHITECTURE.md` — design notes + diagram.
- README, LICENSE (MIT, `Copyright (c) 2026 gl0bal01 and pai-hermes contributors`), CLAUDE.md (agent briefing).
- CLAUDE.md "AGPL boundary" section: documents allowed/forbidden patterns for interacting with `pai-collab` (AGPL-3.0). Filesystem writes to `pai-collab/projects/arc/reviews/` permitted; embedding source / linking as lib / network-exposing forbidden. Composition rule table gained License column per dependency.

### Context

- Replaces `pai-projet/bin/pai` bash router. pai-projet retired after Hermes adoption proves out.
- Built atop Hermes Agent v1.0.0 (Nous Research, MIT), PAI canonical v5.0.0 (Miessler), OMC v4.13.7+, pai-anywhere v0.2.0.
- Cost discipline: cron jobs are zero-AI-cost (pure data aggregation). Only user-triggered skills invoke models.

### NOT done in 0.1.0

- No live testing on Hermes (skills written, integration unverified).
- `tools/cost_check.py` reads PAI usage cache format — needs verification against real `~/.claude/PAI/MEMORY/STATE/usage-cache.json` schema.
- Hermes cron yaml format guessed from `~/.hermes/cron/` examples — needs schema verification.
- No GitHub repo published yet.
- No CI workflow.

## [Unreleased]

### 0.2.0 candidates
- Hermes TUI statusline port (Python rendering equivalent to PAI bash statusline).
- `pai-skill-discover` skill that auto-loads PAI canonical Packs into Hermes `external_dirs`.
- `pai-telos-bridge` skill exposing PAI TELOS files (goals/beliefs/wisdom) as Hermes memory entries.
- `pai-algorithm-v6.3` skill routing through Algorithm phases for major tasks.
- Telegram/Discord-specific routing helpers.

### Won't do
- Modify Hermes Agent source.
- Modify PAI canonical source (Miessler-owned).
- Bundle Whisper.cpp (Hermes manages its own STT).
- Add new Pulse routes (composition rule).
