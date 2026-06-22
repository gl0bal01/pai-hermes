# Changelog

## [Unreleased]

### Fixed

- **`pai-watch` dead on a fresh install**: the skill defaulted `PAI_PROJET_ROOT` to `/opt/pai-projet` (rarely the real clone root) and `PAI_PROPOSALS_DIR` to `/var/lib/pai-anywhere/proposals` (owned by pai-anywhere's `pai` user, so the Hermes gateway — running as the human user — could never write it). Result: the hourly watcher silently no-op'd and proposals were dropped. `PAI_PROPOSALS_DIR` now defaults to `${XDG_STATE_HOME:-$HOME/.local/state}/pai-hermes/proposals` (always gateway-writable, created on demand), and `install.sh` now auto-detects `PAI_PROJET_ROOT` (the parent of the checkout), narrows `PAI_WATCH_SOURCES` to repos that actually exist, writes all three to `$HERMES_HOME/pai-hermes.env`, and wires that as an `EnvironmentFile=` drop-in on the systemd `--user` gateway (printed instructions otherwise). `uninstall.sh` reverses the env file + drop-in. Skill/doc defaults realigned.

## [0.1.3] — 2026-06-19 — Multi-model review hardening

Addresses a 4-reviewer (codex / deepseek / glm / kimi) audit of 0.1.2.
Headline: the SSH-only gate is now actually forge-resistant. No CRITICAL.

### Fixed (HIGH)

- **`bin/pai-accept-guard` SSH gate was forgeable (G1)**: the gate trusted `SSH_*` env vars (which an LLM controls in its own child env) plus a plain `PAI_LOCAL_OVERRIDE=1` bypass, so a prompt-injected Hermes could defeat the documented "never callable from a remote platform" guarantee. Replaced with a process-ancestry check (an `sshd`/`sshd-session` parent, walked via `/proc`) that the agent's process tree never has. Remote use is unchanged — a Tailscale SSH session satisfies it. The env bypass is gone; the only non-SSH escape hatch is a root-owned `/etc/pai/local-accept.allow` (mode 0600) a non-root process can't forge. New bats regressions for env-spoof refusal; CLAUDE.md/SKILL.md realigned to the enforced model.
- **`bin/pai-accept-guard` could wipe all SHA pins (G2/G3)**: `grep -v … || true` conflated grep's no-match (rc 1) with a read error (rc ≥ 2), so an unreadable `paths.env` mid-run replaced the file with a single line, dropping every other `PAI_*_SHA` pin. Rewritten with `awk` (rc 0 on no-match); a real error now aborts. The key filter is now a fixed-string prefix (was a grep regex, so a repo name containing `.` could strip unrelated keys). New pin-preservation regression.

### Fixed (MEDIUM)

- **Config patching extracted + made safe (H9/H7/H2/H5)**: the duplicated inline `python3 -c` heredoc is now `tools/patch_hermes_config.py`. ruamel round-trip preserves user comments/anchors (PyYAML `safe_dump` destroyed them — H7); writes are atomic (`mkstemp`+`fsync`+`os.replace`, re-parsed before swap — never truncate-in-place, H2); the config path comes from argv/env as a `Path`, never interpolated into Python source (H5).
- **`bin/pai-pulse-send` wrapper (S7)**: pai-pulse's safe JSON pattern was prose only. Added an enforcing wrapper — JSON built solely via `jq --arg`, Pulse URL restricted to loopback http (also closes the pai-doctor SSRF), length/NUL guards. SKILL.md now mandates it.
- **`pai-watch` repo-name validation (S6)**: `git -C <name>` ran on unvalidated `$PAI_WATCH_SOURCES` entries. The skill now enforces `^[A-Za-z0-9._-]+$`, confines the resolved path under `$PAI_PROJET_ROOT`, and sets `GIT_CONFIG_GLOBAL=/dev/null`.
- **`pai-accept-guard` proposals-dir symlink escape (G7)**: the root-only `readlink -f` escape check now also covers `PROPOSALS_DIR`, not just `paths.env`.
- **`install.sh` safety (H3/H1)**: single-flight `flock` + ownership guard; refuse a symlink backup path. **Arc-review fence escape (G5)**: untrusted commit subjects are rendered as an indented code block (a `~~~` in a subject can no longer break out). **`template_vars` injection removed (H4)**.

### Fixed (LOW)

- **`tools/cost_check.py` string-credit crash (P1)**: `extract_metrics` passed string `used_credits`/`monthly_limit` straight into arithmetic → `TypeError`, crashing the silent cron. Now coerced with `float()` + try/except like `pct()`.
- **Stale docs (S1–S4, S8–S12)**: dead `cron/*.yaml` references replaced with the jobs.json flow; cost thresholds single-sourced on `cost_check.py` (5h alert 80 / block 95, 7d alert 85); removed `api_spend_month_usd` / `ANTHROPIC_ADMIN_API_KEY`; pai-doctor probes target jobs.json and dropped the retired `bin/pai doctor` delegation; `HOME=$HOME` (was `/home/pai`); README status → 0.1.3.
- **Installer polish (H6/H8/G6)**: true-atomic skill symlink (`ln -s … && mv -T`); `mktemp` backup instead of a fixed `.bak` clobber; `install -d -m 700` for the lock dir (no mkdir+chmod TOCTOU).

### Tooling

- New dependency: `ruamel.yaml` (round-trip YAML) — `install.sh` auto-installs it (pip `--user`, PEP-668 fallback) and fails loudly if unavailable.
- Tests: +28 (guard env-spoof / pin-preservation / fence; cost string inputs; pulse wrapper injection / SSRF; install append-not-replace / comment-survival / H5). bats 40, pytest 32, shellcheck clean.

## [0.1.2] — 2026-05-31 — Security review hardening

Addresses full-tree security review of 0.1.1. 2 HIGH + 5 MEDIUM + 5 LOW + 1 INFO findings resolved. No CRITICAL.

### Fixed (HIGH)

- **`bin/pai-accept-guard` heredoc command injection (M4)**: the arc review markdown writer used an unquoted heredoc `<<EOF`, so `${LOG}` (a `git log --pretty='%h %s'` blob from fetched upstream refs) was shell-expanded before write. A malicious upstream commit subject like `$(cmd)` would execute at write time. Replaced with quoted `printf` per-line — `$LOG` is now treated as opaque text. Fence changed from ``` to `~~~` to reduce markdown-fence-break risk. New bats regression `pai-accept-guard treats proposal .commits as opaque`.
- **`install.sh` rollback gap (H1)**: the `ALREADY_PRESENT` branch deleted the backup before the post-patch YAML validate block, leaving rollback impossible if the on-disk config was malformed pre-run. Unexpected patcher output was non-fatal. Now: validate-then-delete in every branch; any unexpected output is a fatal rollback.
- **`bin/pai-accept-guard` env-var path trust under sudo (H2)**: with `EUID=0`, `PAI_PATHS_ENV=/etc/shadow` (or `PAI_PROPOSALS_DIR`/`PAI_COLLAB_DIR`) would have caused arbitrary-file overwrite. Now refuses non-canonical paths when running as root; `readlink -f` symlink-escape check on `paths.env`. Documented in `docs/INSTALL.md` that the guard must not be invoked via `sudo -E`.

### Fixed (MEDIUM)

- **`docs/INSTALL.md` `curl | bash` (M1)**: VPS install steps replaced with download → `sha256sum -c` → `less` review → `bash` pattern for both pai-anywhere and Hermes installers.
- **`bin/pai-accept-guard` lock-file symlink race (M2)**: `/tmp/pai-accept.lock` default replaced with `${XDG_RUNTIME_DIR:-/run/user/$EUID}/pai-accept/lock` (mode 700). Guard refuses to open the lock if the path is already a symlink (anti-truncate). New bats regression.
- **`bin/pai-accept-guard` trap chain (M3)**: switched from per-step `trap '... rm $TMP' EXIT; trap - EXIT` pattern to a single `CLEANUP=()` accumulator + exit-code-preserving cleanup function. Removes orphan-tempfile risk on failure between trap toggles.
- **`tools/cost_check.py` snapshot symlink follow (M5)**: `log_path.open("a")` followed symlinks under cron, allowing append to arbitrary file. Now: `Path.resolve()` + parent-directory allowlist under `~/.hermes/`, `O_NOFOLLOW` open. Snapshot dir created mode 700. New bats regression `cost_check.py refuses --snapshot-log outside ~/.hermes/`.

### Fixed (LOW)

- **`install.sh` symlink TOCTOU (L1)**: `[[ -L ]] then rm then [[ -e ]]` race replaced with `ln -snf` (atomic) + non-symlink pre-check.
- **`uninstall.sh` `cp` follows symlinks (L2)**: refuses if `$BACKUP` is a pre-existing symlink; `cp --no-dereference --remove-destination`. Also pre-checks `$HERMES_CONFIG` is not a symlink.
- **`skills/pai-pulse/SKILL.md` JSON construction guidance (L3)**: added `## Safety — JSON construction` section mandating `jq -n --arg` with explicit wrong/right examples; warns that `-d "{\"message\":\"$msg\"}"` re-evaluates `$()`/backticks/`${}` as shell.
- **`docs/INSTALL.md` regex-on-YAML antipattern (L4)**: the "Wire PAI canonical Packs" step taught the regex pattern explicitly removed from `install.sh` in 0.1.1. Replaced with a PyYAML safe_load/safe_dump snippet matching the installer.
- **`docs/INSTALL.md` stale cron docs (L5)**: removed references to symlinking `cron/*.yaml` and `ls ~/.hermes/cron/pai-*.yaml`. Verify/configure sections rewritten for `~/.hermes/cron/jobs.json`. Bats count corrected 13→15.

### Fixed (INFO)

- **`bin/pai-accept-guard` `set -uo pipefail` → `set -euo pipefail` (I1)**: stricter error contract; trap accumulator preserves exit code so `die`'s explicit code (e.g. 77 for non-SSH) survives.

### Test status

- 18/18 bats (was 15; +3 regressions: M4 heredoc, M2 lock symlink, M5 snapshot allowlist) ✓
- 27/27 pytest (`tests/test_cost_check.py`) ✓
- shellcheck clean on `install.sh`, `uninstall.sh`, `bin/pai-accept-guard` ✓

### Known limitations (still in 0.1.2)

- I3 (`SSH_CONNECTION` env spoofable by local unprivileged user) is a design choice per `CLAUDE.md` — the SSH gate prevents Hermes-via-prose bypass, not local-shell attacks.
- Anthropic admin-API spend fetch still deferred (carried from 0.1.1).
- Live Hermes integration runtime still unverified.

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
