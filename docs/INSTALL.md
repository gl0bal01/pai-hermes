# INSTALL — pai-hermes wiring

## Prerequisites

| Component | Required | Verify |
|-----------|----------|--------|
| Hermes Agent | YES | `hermes --version` (any) |
| Python 3 | YES (config patcher) | `python3 --version` |
| bats | YES (test runner) | `command -v bats` |
| jq | YES (skill bodies) | `command -v jq` |
| OMC CLI | YES (for omc skill) | `omc --version` ≥4.13.7 |
| PAI canonical | RECOMMENDED | dir at `~/.claude/PAI/` |
| pai-anywhere | RECOMMENDED (VPS) | `/etc/pai-anywhere/install-manifest.jsonl` |

Install missing pieces:
```bash
# OMC
npm install -g oh-my-claudecode
# or
bun install -g oh-my-claudecode

# bats + jq (Ubuntu/Debian)
sudo apt install -y bats jq python3 git curl flock
```

## Quick install (local dev)

```bash
git clone https://github.com/<you>/pai-hermes ~/pai-hermes
cd ~/pai-hermes
chmod +x install.sh
./install.sh
```

What `install.sh` does:
1. Symlinks `skills/` → `~/.hermes/skills/pai-hermes`
2. Symlinks `cron/*.yaml` → `~/.hermes/cron/`
3. Patches `~/.hermes/config.yaml` `skills.external_dirs` to include `~/.hermes/skills/pai-hermes`
4. Validates SKILL.md format via bats
5. Backs up modified config to `~/.hermes/config.yaml.bak`

Idempotent — re-run safely.

## VPS install (production with pai-anywhere)

```bash
# 0. Prerequisites — install pai-anywhere socle FIRST
curl -fsSL https://pai-anywhere.dev/install | bash
pai-anywhere doctor && pai-anywhere verify

# 1. Install Hermes (Nous Research) as the pai user
sudo -u pai bash -lc 'curl -fsSL https://hermes-agent.nousresearch.com/install | bash'
sudo -u pai hermes --version

# 2. Install OMC globally (Claude Code harness)
sudo -u pai bash -lc 'npm install -g oh-my-claudecode'

# 3. Clone pai-hermes
sudo git clone https://github.com/<you>/pai-hermes /opt/pai-hermes
sudo chown -R pai:pai /opt/pai-hermes

# 4. Install pai-hermes wiring as pai user
sudo -u pai bash -lc 'cd /opt/pai-hermes && ./install.sh'

# 5. (Optional but recommended) Wire PAI canonical Packs
# Edit ~/.hermes/config.yaml under skills.external_dirs:
sudo -u pai bash -lc '
python3 - <<PYEOF
import re, pathlib
p = pathlib.Path("/home/pai/.hermes/config.yaml")
text = p.read_text()
extra = "    - /opt/pai-projet/Personal_AI_Infrastructure/Packs"
if extra in text:
    print("already added")
else:
    text = re.sub(r"(skills:\n  external_dirs:\n)", rf"\1{extra}\n", text)
    p.write_text(text)
    print("added PAI Packs to external_dirs")
PYEOF
'

# 6. Restart Hermes (must be done by user — Hermes daemon mgmt is its own concern)
sudo -u pai bash -lc 'pkill -f hermes; nohup hermes >/var/log/pai/hermes.log 2>&1 &'

# 7. Verify
sudo -u pai bash -lc 'hermes -c "doctor"'   # if Hermes has CLI-mode flag
```

## Verify install

```bash
# Skill format
cd ~/pai-hermes
bats tests/skill-format.bats   # all 13 tests should pass

# Skills loaded in Hermes
hermes --skills | grep -E "omc|pai-(pulse|watch|doctor|accept|cost-tracker|statusline-banner)"
# should list 7 skills

# Cron registered
ls -la ~/.hermes/cron/pai-*.yaml
# should show 3 symlinks

# Config patched
grep "pai-hermes" ~/.hermes/config.yaml
# should show entry under external_dirs
```

## Configure (optional)

### Override thresholds for cost-tracker

Edit `~/.hermes/cron/pai-cost-tracker.yaml` (since it's a symlink, edit `~/pai-hermes/cron/pai-cost-tracker.yaml`):

```yaml
task:
  args:
    thresholds:
      five_hour_alert: 70   # default 80
      seven_day_alert: 80   # default 85
```

### Disable banner cron

```bash
rm ~/.hermes/cron/pai-statusline-banner.yaml
# or set enabled: false in the yaml
```

### Change banner delivery time

Edit `cron/pai-statusline-banner.yaml`:
```yaml
schedule: "0 19 * * *"     # 19:00 instead of 18:00
timezone: Europe/Paris
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `install.sh` says "Hermes not installed" | install Hermes Agent first |
| skill format bats tests fail | re-clone repo; check SKILL.md frontmatter manually |
| Hermes doesn't list pai skills | restart Hermes; check `~/.hermes/config.yaml` `external_dirs` |
| cron jobs don't fire | `hermes --cron list`; verify Hermes scheduler enabled in main config |
| Pulse `/notify` unreachable | `pai-doctor` skill → check Pulse systemd / port 31337 / Tailscale |
| pai-accept rejects with "SSH-only" | must be invoked from SSH session, not remote platform — by design |

## Uninstall

```bash
./uninstall.sh
# restart Hermes to fully unload
```

Source repo untouched — delete `~/pai-hermes` manually if desired.

## Updating

```bash
cd ~/pai-hermes
git pull
./install.sh        # re-applies any new symlinks (idempotent)
hermes restart      # or pkill + restart
```
