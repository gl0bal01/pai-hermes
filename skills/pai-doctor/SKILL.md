---
name: pai-doctor
description: Health probe suite for PAI ecosystem. Use when user says doctor, is everything ok, health check, what's broken, pai status.
---

# pai-doctor skill

## When to use

User intent:
- "doctor", "health check", "is everything ok", "what's broken"
- "pai status", "ecosystem state"
- Before launching expensive task (verify pai-anywhere up before omc ralph)
- Cron-driven daily health digest (pair with pai-statusline-banner)

## Probes (25 checks)

### Infra
- `pai_anywhere_systemd_status` — systemctl is-active pai-anywhere.service
- `pulse_reachable` — HTTP 200 on $PAI_PULSE_URL; probe refuses non-loopback URLs (must be http://127.0.0.1:... or http://localhost:...). See S10 caveat below.
- `pulse_port_format` — URL matches loopback 127.0.0.1 port pattern
- `tailscale_present` — tailscale binary on PATH
- `tailscale_serve_active` — gateway exposed via Serve PRIVATE

### PAI canonical
- `pai_canonical_dir_present` — $PAI_CANONICAL_DIR is directory
- `pai_statusline_command` — ~/.claude/PAI/statusline-command.sh executable
- `pai_spinner_assets` — ~/.claude/PAI/USER/SHARED/Spinner/ exists
- `pai_settings_statusline_wired` — settings.json .statusLine.command set
- `pai_usage_cache_present` — ~/.claude/PAI/MEMORY/STATE/usage-cache.json readable

### OMC
- `omc_cli_present` — omc binary on PATH
- `omc_version` — omc --version returns >=4.13.7
- `omc_sqlite_native_load` — better-sqlite3 native addon loads inside OMC install dir

### pai-anywhere
- `pai_anywhere_dir_present` — sub-project dir exists
- `pai_anywhere_install_manifest` — /etc/pai-anywhere/install-manifest.jsonl readable
- `pai_anywhere_gateway_reachable` — HTTP 200/401 on 127.0.0.1:8787

### pai-hermes wiring
- `hermes_config_present` — ~/.hermes/config.yaml readable
- `hermes_external_dirs_includes_pai_hermes` — config has pai-hermes path in external_dirs
- `hermes_cron_pai_watch` — job entry present in ~/.hermes/cron/jobs.json
- `hermes_cron_pai_cost_tracker` — job entry present in ~/.hermes/cron/jobs.json
- `hermes_cron_pai_statusline_banner` — job entry present in ~/.hermes/cron/jobs.json

### Tooling
- `jq_available`, `curl_available`, `git_available`, `flock_available`
- `bun_present`, `node_present`

### State
- `proposals_dir_writable` — PAI_PROPOSALS_DIR writable
- `audit_log_writable` — PAI_LOG_DIR writable

## Output schema

```
schema: pai-hermes.doctor.v1
generatedAt: ISO-8601 timestamp
passCount: integer
failCount: integer
probes: array of {name, status, detail}
```

Status values: `pass`, `fail`, `skip`.

## Execution

Via Hermes terminal toolset. Pure shell. ~1s total. Zero AI cost.

Implemented as pure shell checks. Does NOT delegate to the retired `pai-projet/bin/pai doctor`.

## Caveats

- Some probes macOS-specific (PAI canonical statusline assumes launchd). On Linux VPS, pai_anywhere_systemd_status replaces.
- Probes are advisory — fail doesn't auto-fix. For remediation, pai-anywhere doctor --fix or install missing deps.
- Voice probes (arecord_present, whisper_cli_present) may legitimately fail on headless server.
- `pulse_reachable`: $PAI_PULSE_URL MUST be loopback (http://127.0.0.1:31337 or http://localhost:31337). The probe aborts with exit 78 if the URL resolves to a non-loopback address.

## Triggers in Hermes natural language

- "pai doctor" → run skill
- "is the system ok?" → run + summarize failures
- "what's broken with PAI" → focus on fail probes
- "before I ralph, verify pai-anywhere" → run before chaining to omc skill
