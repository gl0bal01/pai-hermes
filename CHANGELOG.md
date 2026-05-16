# Changelog

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
