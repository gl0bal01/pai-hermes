# INSTALL — pai-hermes wiring

## Prerequisites

| Component | Required | Verify |
|-----------|----------|--------|
| Hermes Agent | YES | `hermes --version` (any) |
| Python 3 + PyYAML | YES (config patcher) | `python3 -c "import yaml"` |
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

# bats + jq + flock + pyyaml (Ubuntu/Debian)
sudo apt install -y bats jq python3 python3-yaml git curl util-linux
```

## Quick install (local dev)

```bash
git clone https://github.com/gl0bal01/pai-hermes ~/pai-hermes
cd ~/pai-hermes
chmod +x install.sh
./install.sh
```

What `install.sh` does (0.1.1):
1. Symlinks `skills/` → `~/.hermes/skills/pai-hermes` (atomic `ln -snf`)
2. Patches `~/.hermes/config.yaml` `skills.external_dirs` to include `~/.hermes/skills/pai-hermes`
   via PyYAML safe-load/safe-dump (NOT regex — see "Why PyYAML" below)
3. Backs up config to `~/.hermes/config.yaml.bak` BEFORE patching
4. Validates post-patch YAML; rolls back from backup if parse fails
5. Validates SKILL.md format via bats

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

# 5. (Optional) Wire PAI canonical Packs via PyYAML — never via regex.
#    Replace the path with your actual PAI canonical Packs location.
sudo -u pai bash -lc '
HERMES_CONFIG="$HOME/.hermes/config.yaml" \
PACKS_DIR="/opt/pai-projet/Personal_AI_Infrastructure/Packs" \
python3 <<"PYEOF"
import os, sys, pathlib, yaml
cfg = pathlib.Path(os.environ["HERMES_CONFIG"])
target = os.environ["PACKS_DIR"]
data = yaml.safe_load(cfg.read_text()) or {}
skills = data.setdefault("skills", {})
ext = skills.setdefault("external_dirs", [])
if target in ext:
    print("already added"); sys.exit(0)
ext.append(target)
cfg.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False, allow_unicode=True))
print("added PAI Packs to external_dirs")
PYEOF
'

# 6. Restart Hermes (must be done by user — Hermes daemon mgmt is its own concern)
sudo -u pai bash -lc 'pkill -f hermes; nohup hermes >/var/log/pai/hermes.log 2>&1 &'

# 7. Verify
sudo -u pai bash -lc 'hermes -c "doctor"'   # if Hermes has CLI-mode flag
```

### Why PyYAML, not regex

YAML allows multiple equivalent indentations, flow vs block style, anchors,
and comment lines that survive round-trip only via a real parser. Regex
substitution on YAML produces corrupt files when the user's `external_dirs:`
is written inline (`[a, b]`) or under a non-default indent. The 0.1.1
installer was rewritten to load → mutate → safe_dump for this reason.

### `pai-accept-guard` (SSH-only gate)

If using pai-accept via pai-watch flow, install the guard:

```bash
sudo ln -sf /opt/pai-hermes/bin/pai-accept-guard /usr/local/bin/pai-accept-guard
```

**MUST NOT be run with `sudo --preserve-env` / `sudo -E`**. When the guard
detects `EUID=0`, it locks all path-bearing env vars to canonical locations
to prevent `PAI_PATHS_ENV=/etc/shadow` style overwrite. Best practice: keep
the default `Defaults env_reset` in your sudoers.

## Verify install

```bash
# Skill format + scripts
cd ~/pai-hermes
bats tests/skill-format.bats   # all 15 tests should pass

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
