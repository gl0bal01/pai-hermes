#!/usr/bin/env bash
# pai-hermes uninstaller — reverses install.sh
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
HERMES_SKILLS_DIR="$HERMES_HOME/skills/pai-hermes"
HERMES_CRON_DIR="$HERMES_HOME/cron"

echo "[pai-hermes uninstall] removing wiring..."

# 1. Remove skills symlink
if [[ -L "$HERMES_SKILLS_DIR" ]]; then
  rm "$HERMES_SKILLS_DIR"
  echo "  removed: $HERMES_SKILLS_DIR"
elif [[ -e "$HERMES_SKILLS_DIR" ]]; then
  echo "  WARN: $HERMES_SKILLS_DIR exists but is not a symlink — leaving alone"
fi

# 2. Remove cron symlinks
for cron_file in "$REPO_DIR"/cron/*.yaml; do
  [[ -f "$cron_file" ]] || continue
  base="$(basename "$cron_file")"
  target="$HERMES_CRON_DIR/$base"
  if [[ -L "$target" ]]; then
    rm "$target"
    echo "  removed: $target"
  fi
done

# 3. Strip external_dirs entry from config.yaml
if [[ -f "$HERMES_CONFIG" ]] && grep -qE "^\s*-\s*${HERMES_SKILLS_DIR}\s*$" "$HERMES_CONFIG"; then
  cp -n "$HERMES_CONFIG" "$HERMES_CONFIG.bak" 2>/dev/null || true
  python3 - "$HERMES_CONFIG" "$HERMES_SKILLS_DIR" <<'PYEOF'
import sys, re, pathlib
cfg, target = pathlib.Path(sys.argv[1]), sys.argv[2]
text = cfg.read_text()
text = re.sub(rf'^\s*-\s*{re.escape(target)}\s*\n', '', text, flags=re.MULTILINE)
cfg.write_text(text)
PYEOF
  echo "  removed external_dirs entry from $HERMES_CONFIG"
fi

echo "[pai-hermes uninstall] DONE. Restart Hermes to fully unload."
echo "Note: skills/ source repo at $REPO_DIR untouched. Delete manually if desired."
