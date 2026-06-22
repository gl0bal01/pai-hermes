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
PATCH_TOOL="$REPO_DIR/tools/patch_hermes_config.py"

echo "[pai-hermes uninstall] removing wiring..."

# === 1. Remove skills symlink =============================================
if [[ -L "$HERMES_SKILLS_DIR" ]]; then
  rm "$HERMES_SKILLS_DIR"
  echo "  removed symlink: $HERMES_SKILLS_DIR"
elif [[ -e "$HERMES_SKILLS_DIR" ]]; then
  echo "  WARN: $HERMES_SKILLS_DIR exists but is not a symlink — leaving alone"
fi

# === 2. Remove external_dirs entry from config.yaml (ruamel round-trip) ===
# H5: path passed as arg/env to the external tool, never interpolated into a
# `python3 -c` string. H2: the tool writes atomically (temp in same dir, fsync,
# os.replace) and re-parses before swapping.
if [[ -f "$HERMES_CONFIG" && ! -L "$HERMES_CONFIG" ]]; then
  [[ -f "$PATCH_TOOL" ]] || { echo "ERROR: $PATCH_TOOL missing" >&2; exit 1; }
  python3 -c "import ruamel.yaml" 2>/dev/null || {
    echo "ERROR: ruamel.yaml required to edit config.yaml (pip install --user ruamel.yaml)." >&2
    exit 1
  }
  # H8: avoid the fixed `${HERMES_CONFIG}.bak` TOCTOU/clobber. Use a unique
  # mktemp-named backup in the same directory (set -C also guards against an
  # accidental clobber of an existing path via the noclobber redirect).
  BACKUP="$(set -C; mktemp "${HERMES_CONFIG}.uninstall-bak.XXXXXX")" || {
    echo "ERROR: could not create backup temp file next to $HERMES_CONFIG" >&2
    exit 1
  }
  cp --no-dereference --remove-destination "$HERMES_CONFIG" "$BACKUP"
  validate_yaml() {
    HERMES_CONFIG="$HERMES_CONFIG" python3 -c \
      'import os; from ruamel.yaml import YAML; YAML(typ="rt").load(open(os.environ["HERMES_CONFIG"]).read())' \
      2>/dev/null
  }
  if PATCH_OUT=$(HERMES_CONFIG="$HERMES_CONFIG" python3 "$PATCH_TOOL" \
        --remove-external-dir "$HERMES_SKILLS_DIR" 2>&1); then
    case "$PATCH_OUT" in
      REMOVED|NOT_PRESENT) : ;;
      *)
        echo "ERROR: unexpected patcher output: $PATCH_OUT — restoring backup" >&2
        mv "$BACKUP" "$HERMES_CONFIG"
        exit 1
        ;;
    esac
    if validate_yaml; then
      echo "  removed external_dirs entry from $HERMES_CONFIG (backup: $BACKUP)"
    else
      echo "ERROR: config.yaml broke after uninstall edit — restoring backup" >&2
      mv "$BACKUP" "$HERMES_CONFIG"
      exit 1
    fi
  else
    echo "ERROR: uninstall edit failed ($PATCH_OUT) — restoring backup" >&2
    mv "$BACKUP" "$HERMES_CONFIG"
    exit 1
  fi
fi

# === 2a. Remove pai-watch env file + gateway drop-in =====================
# Reverses install.sh's "3a. pai-watch runtime environment" step. The proposals
# dir under XDG state is left in place (it may hold proposals; user data).
ENV_FILE="$HERMES_HOME/pai-hermes.env"
if [[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]]; then
  rm -f "$ENV_FILE"
  echo "  removed $ENV_FILE"
fi
DROPIN="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/hermes-gateway.service.d/pai-hermes.conf"
if [[ -f "$DROPIN" && ! -L "$DROPIN" ]]; then
  rm -f "$DROPIN"
  echo "  removed gateway drop-in $DROPIN"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user is-active --quiet hermes-gateway.service; then
      systemctl --user restart hermes-gateway.service 2>/dev/null || true
    fi
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
