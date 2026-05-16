#!/usr/bin/env bash
# pai-hermes uninstaller — reverses install.sh (0.1.1)
#
# Does NOT remove cron jobs from ~/.hermes/cron/jobs.json — they were never
# symlinked. Remove via Hermes itself: "Delete cron job pai-watch", etc.
#
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
HERMES_SKILLS_DIR="$HERMES_HOME/skills/pai-hermes"

echo "[pai-hermes uninstall] removing wiring..."

# === 1. Remove skills symlink =============================================
if [[ -L "$HERMES_SKILLS_DIR" ]]; then
  rm "$HERMES_SKILLS_DIR"
  echo "  removed symlink: $HERMES_SKILLS_DIR"
elif [[ -e "$HERMES_SKILLS_DIR" ]]; then
  echo "  WARN: $HERMES_SKILLS_DIR exists but is not a symlink — leaving alone"
fi

# === 2. Remove external_dirs entry from config.yaml (pyyaml) =============
if [[ -f "$HERMES_CONFIG" ]]; then
  BACKUP="${HERMES_CONFIG}.bak"
  cp "$HERMES_CONFIG" "$BACKUP"
  if HERMES_CONFIG="$HERMES_CONFIG" SKILL_DIR="$HERMES_SKILLS_DIR" python3 <<'PYEOF'
import os, sys, yaml, pathlib
cfg = pathlib.Path(os.environ["HERMES_CONFIG"])
target = os.environ["SKILL_DIR"]
data = yaml.safe_load(cfg.read_text()) or {}
skills = data.get("skills") or {}
ext = skills.get("external_dirs") or []
if target in ext:
    ext = [e for e in ext if e != target]
    skills["external_dirs"] = ext
    data["skills"] = skills
    cfg.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False, allow_unicode=True))
    print("REMOVED")
else:
    print("NOT_PRESENT")
PYEOF
  then
    # validate post-edit
    if python3 -c "import yaml; yaml.safe_load(open('$HERMES_CONFIG').read())" 2>/dev/null; then
      echo "  removed external_dirs entry from $HERMES_CONFIG (backup: $BACKUP)"
    else
      echo "ERROR: config.yaml broke after uninstall edit — restoring backup" >&2
      mv "$BACKUP" "$HERMES_CONFIG"
      exit 1
    fi
  else
    echo "ERROR: uninstall edit failed — restoring backup" >&2
    mv "$BACKUP" "$HERMES_CONFIG"
    exit 1
  fi
fi

# === 3. Cron job reminder (jobs.json is Hermes-managed) ==================
cat <<EOF

[pai-hermes uninstall] DONE.

Reminder: cron jobs (pai-watch, pai-cost-tracker, pai-statusline-banner) live
in ~/.hermes/cron/jobs.json and were NOT symlinked. Remove them via Hermes:

  In a Hermes session: "Delete cron job pai-watch"
                       "Delete cron job pai-cost-tracker"
                       "Delete cron job pai-statusline-banner"

  Or inspect directly: jq '.jobs[].name' ~/.hermes/cron/jobs.json

Source repo at $REPO_DIR untouched. Delete manually if desired.
Restart Hermes to fully unload skills.
EOF
