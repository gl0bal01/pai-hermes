# INSTALL — pai-hermes wiring

## Prerequisites

| Component | Required | Verify |
|-----------|----------|--------|
| Hermes Agent | YES | `hermes --version` (any) |
| Python 3 | YES (config patcher, cost check) | `python3 --version` |
| ruamel.yaml | auto-installed by `install.sh` | `python3 -c "import ruamel.yaml"` |
| bats | YES (test runner) | `command -v bats` |
| jq | YES (skill bodies) | `command -v jq` |
| flock | YES (pai-accept guard) | `command -v flock` |
| OMC CLI | YES (for omc skill) | `omc --version` ≥4.13.7 |
| PAI canonical | RECOMMENDED | dir at `~/.claude/PAI/` |
| pai-anywhere | RECOMMENDED (VPS) | `/etc/pai-anywhere/install-manifest.jsonl` |

Install missing pieces:
```bash
# OMC
npm install -g oh-my-claudecode
# or
bun install -g oh-my-claudecode

# bats + jq + flock + python3/pip (Ubuntu/Debian; ruamel.yaml is auto-installed)
sudo apt install -y bats jq python3 python3-pip git curl util-linux
```

## Quick install (local dev)

```bash
git clone https://github.com/gl0bal01/pai-hermes ~/pai-hermes
cd ~/pai-hermes
chmod +x install.sh
./install.sh
```

What `install.sh` does (0.1.3):
1. Symlinks `skills/` → `~/.hermes/skills/pai-hermes` (true-atomic `ln -s … && mv -T`)
2. Ensures `ruamel.yaml` is importable (auto-installs via `pip` if missing)
3. Adds `~/.hermes/skills/pai-hermes` to `skills.external_dirs` in `~/.hermes/config.yaml`
   via `tools/patch_hermes_config.py` — a ruamel round-trip that **appends** (never
   replaces) and preserves your comments/formatting (see "Why ruamel" below)
4. Backs up the config first, writes it **atomically**, rolls back if the result won't parse
5. Holds a single-flight lock and refuses to run if the config isn't owned by you
6. Validates SKILL.md format via bats

Cron jobs are NOT symlinked. Hermes cron is JSON-managed via Hermes itself;
register manually after install — see `cron/README.md`.

Idempotent — re-run safely.

## VPS install (production with pai-anywhere)

> SECURITY: NEVER run installers via `curl … | bash`. Each step below
> downloads, verifies, reviews, then executes. Pin SHA256s once published.

```bash
# 0. Prerequisites — install pai-anywhere socle FIRST
#    Download, review, then execute. Do not pipe directly to bash.
curl -fsSL https://pai-anywhere.dev/install -o /tmp/pai-anywhere-install.sh
# Verify checksum (replace with published SHA256 from the release page)
# echo "<expected-sha256>  /tmp/pai-anywhere-install.sh" | sha256sum -c
less /tmp/pai-anywhere-install.sh          # review the script
bash /tmp/pai-anywhere-install.sh
pai-anywhere doctor && pai-anywhere verify

# 1. Install Hermes (Nous Research) as the pai user
sudo -u pai bash -lc 'curl -fsSL https://hermes-agent.nousresearch.com/install -o /tmp/hermes-install.sh'
sudo -u pai less /tmp/hermes-install.sh    # review
# sudo -u pai bash -lc 'echo "<expected-sha256>  /tmp/hermes-install.sh" | sha256sum -c'
sudo -u pai bash -lc 'bash /tmp/hermes-install.sh'
sudo -u pai hermes --version

# 2. Install OMC globally (Claude Code harness)
sudo -u pai bash -lc 'npm install -g oh-my-claudecode'

# 3. Clone pai-hermes
sudo git clone https://github.com/gl0bal01/pai-hermes /opt/pai-hermes
sudo chown -R pai:pai /opt/pai-hermes

# 4. Install pai-hermes wiring as pai user
sudo -u pai bash -lc 'cd /opt/pai-hermes && ./install.sh'

# 5. (Optional) Wire PAI canonical Packs into Hermes' external_dirs.
#    Use the bundled patcher (comment-preserving, atomic, append-only) —
#    not an inline edit. Replace the path with your actual PAI Packs location.
sudo -u pai bash -lc '
  HERMES_CONFIG="$HOME/.hermes/config.yaml" \
  python3 /opt/pai-hermes/tools/patch_hermes_config.py \
    --add-external-dir /opt/pai-projet/Personal_AI_Infrastructure/Packs
'

# 6. Restart Hermes (must be done by user — Hermes daemon mgmt is its own concern)
sudo -u pai bash -lc 'pkill -f hermes; nohup hermes >/var/log/pai/hermes.log 2>&1 &'

# 7. Verify
sudo -u pai bash -lc 'hermes -c "doctor"'   # if Hermes has CLI-mode flag
```

### Why ruamel.yaml, not regex (or PyYAML)

YAML allows multiple equivalent indentations, flow vs block style, anchors,
and comments. Regex substitution corrupts files when `external_dirs:` is
written inline (`[a, b]`) or under a non-default indent. PyYAML parses
correctly but its `safe_dump` discards every comment and re-flows the file.
Since 0.1.3 the patcher (`tools/patch_hermes_config.py`) uses a `ruamel.yaml`
round-trip, so your comments and layout survive; the write is atomic
(temp file + `os.replace`) and re-validated before the swap.

### `pai-accept-guard` (real-SSH-only gate)

If using `pai-accept` via the `pai-watch` flow, install the guard:

```bash
sudo ln -sf /opt/pai-hermes/bin/pai-accept-guard /usr/local/bin/pai-accept-guard
```

The guard authorizes a pin only when `sshd` is in the invoking process's
ancestry (verified via `/proc`); the spoofable `SSH_*` environment variables
are **ignored**, so a remotely-driven Hermes cannot pass it. Operate from
anywhere with a **Tailscale SSH** session. For non-SSH local admin or CI,
create a **root-owned** `/etc/pai/local-accept.allow` (mode `0600`) — a
non-root process cannot forge it.

**Do NOT run via `sudo --preserve-env` / `sudo -E`.** Under `EUID=0` the guard
also locks all path-bearing env vars to canonical locations to prevent a
`PAI_PATHS_ENV=/etc/shadow`-style overwrite. Keep the default
`Defaults env_reset` in your sudoers.

## Verify install

```bash
# Skill format + scripts
cd ~/pai-hermes
bats tests/skill-format.bats   # all 21 tests should pass

# Skills loaded in Hermes
hermes --skills | grep -E "omc|pai-(pulse|watch|doctor|accept|cost-tracker|statusline-banner)"
# should list 7 skills

# Cron jobs registered (after manual registration via Hermes — see cron/README.md)
jq '.jobs[] | {name, schedule: .schedule.expr, enabled}' ~/.hermes/cron/jobs.json
# should show 3 jobs: pai-watch, pai-cost-tracker, pai-statusline-banner

# Config patched
grep "pai-hermes" ~/.hermes/config.yaml
# should show entry under external_dirs
```

## Configure (optional)

Cron jobs ship as Hermes-managed JSON, not YAML files. To override defaults,
edit job parameters via Hermes itself (e.g. "Update cron job
pai-cost-tracker thresholds to {five_hour_alert: 70}") or edit
`~/.hermes/cron/jobs.json` directly (back it up first; Hermes may rewrite it).

### Override thresholds for cost-tracker

In a Hermes session:

> Update cron job pai-cost-tracker: set thresholds.five_hour_alert=70 and
> thresholds.seven_day_alert=80

Or programmatically, pass via cron command:

```bash
python3 /opt/pai-hermes/tools/cost_check.py \
  --thresholds '{"five_hour_alert":70,"seven_day_alert":80}'
```

### Disable banner cron

In a Hermes session:

> Disable cron job pai-statusline-banner

Or set `enabled: false` for that job in `~/.hermes/cron/jobs.json` and
restart Hermes.

### Change banner delivery time

In a Hermes session:

> Update cron job pai-statusline-banner schedule to 0 19 * * * Europe/Paris

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `install.sh` says "Hermes not installed" | install Hermes Agent first |
| `install.sh` rolls back with "patched config.yaml fails YAML parse" | inspect `~/.hermes/config.yaml.bak`; the patcher refused to leave a broken file |
| skill format bats tests fail | re-clone repo; check SKILL.md frontmatter manually |
| Hermes doesn't list pai skills | restart Hermes; check `~/.hermes/config.yaml` `external_dirs` |
| cron jobs don't fire | inspect `~/.hermes/cron/jobs.json`; verify Hermes scheduler enabled |
| Pulse `/notify` unreachable | `pai-doctor` skill → check Pulse systemd / port 31337 / Tailscale |
| pai-accept rejects with "SSH-only" | must be invoked from SSH session, not remote platform — by design |
| pai-accept-guard rejects with "as root, paths.env must be …" | running via sudo with env passthrough; drop `-E` / restore `Defaults env_reset` |

## Uninstall

```bash
./uninstall.sh
# restart Hermes to fully unload
```

`uninstall.sh` removes the skills symlink and the `external_dirs` entry
from `~/.hermes/config.yaml`. Cron jobs are Hermes-managed, NOT removed by
the uninstaller — delete via Hermes ("Delete cron job pai-watch", etc.) or
edit `~/.hermes/cron/jobs.json`.

Source repo untouched — delete `~/pai-hermes` manually if desired.

## Updating

```bash
cd ~/pai-hermes
git pull
./install.sh        # idempotent; safe to re-run
# restart Hermes (Hermes manages its own lifecycle)
```
