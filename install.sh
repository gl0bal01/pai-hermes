#!/usr/bin/env bash
# pai-hermes installer — idempotent wiring into Hermes Agent config
#
# What this does (0.1.1):
#   1. Symlink pai-hermes/skills/ into ~/.hermes/skills/pai-hermes
#   2. Patch ~/.hermes/config.yaml: add skills.external_dirs entry (pyyaml-based,
#      not regex). Backup .bak. Validate YAML after patch; restore from .bak if
#      validation fails (rollback).
#   3. Print instructions for registering 3 cron jobs via Hermes itself
#      (cron is JSON-based; see cron/README.md for why we don't symlink).
#
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
HERMES_SKILLS_DIR="$HERMES_HOME/skills/pai-hermes"
PATCH_TOOL="$REPO_DIR/tools/patch_hermes_config.py"

echo "[pai-hermes install] repo=$REPO_DIR"
echo "[pai-hermes install] target=$HERMES_HOME"

# === 0. Sanity ============================================================
[[ -d "$HERMES_HOME" ]] || { echo "ERROR: Hermes not installed at $HERMES_HOME" >&2; exit 1; }
[[ -f "$HERMES_CONFIG" ]] || { echo "ERROR: $HERMES_CONFIG missing" >&2; exit 1; }
[[ -f "$PATCH_TOOL" ]] || { echo "ERROR: $PATCH_TOOL missing" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required" >&2; exit 1; }

# === 0a. Ensure ruamel.yaml (config patcher dependency) ===================
# H7: the patcher uses ruamel.yaml round-trip so user comments/anchors survive
# (PyYAML safe_dump destroyed them). PyYAML ships with Hermes; ruamel may not,
# so — unlike the old hard-fail PyYAML gate — detect, then pip-install on miss,
# then re-check and fail with an actionable message if it still can't import.
if ! python3 -c "import ruamel.yaml" 2>/dev/null; then
  echo "[pai-hermes install] ruamel.yaml missing — attempting pip install --user..."
  # Try the plain --user install first (matches the repo's documented
  # `pip install --user` convention). On PEP-668 externally-managed Pythons
  # outside a venv, retry once with --break-system-packages so a stock
  # Debian/Ubuntu host can still bootstrap the dependency.
  if ! python3 -m pip install --user ruamel.yaml >/dev/null 2>&1; then
    python3 -m pip install --user --break-system-packages ruamel.yaml >/dev/null 2>&1 || true
  fi
  if ! python3 -c "import ruamel.yaml" 2>/dev/null; then
    echo "ERROR: ruamel.yaml is required but could not be installed." >&2
    echo "       Install it into the Python that runs Hermes, e.g.:" >&2
    echo "         python3 -m pip install --user ruamel.yaml" >&2
    echo "         # or inside the Hermes venv: pip install ruamel.yaml" >&2
    echo "         # or on Debian/Ubuntu: sudo apt install python3-ruamel.yaml" >&2
    exit 1
  fi
  echo "  ruamel.yaml installed."
fi

# === 0b. Single-flight lock + ownership guard (H3) ========================
# Serialize concurrent installs and refuse to scatter root-owned files into a
# user's ~/.hermes. flock auto-releases when the script (fd 9) exits.
mkdir -p "$HERMES_HOME"
LOCK_FILE="$HERMES_HOME/.pai-hermes-install.lock"
if [[ -L "$LOCK_FILE" ]]; then
  echo "ERROR: $LOCK_FILE is a symlink, refusing to use it" >&2
  exit 1
fi
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "ERROR: another pai-hermes install holds $LOCK_FILE" >&2; exit 1; }
else
  echo "  WARN: flock not found — proceeding without single-flight lock"
fi
# Ownership guard: writing as a different owner (e.g. root into a user's home)
# would leave files the user cannot manage. Require either the config or
# HERMES_HOME to be owned by the invoker.
if [[ ! -O "$HERMES_CONFIG" && ! -O "$HERMES_HOME" ]]; then
  echo "ERROR: neither $HERMES_CONFIG nor $HERMES_HOME is owned by you (uid $(id -u))." >&2
  echo "       Refusing to write — re-run as the owner of ~/.hermes to avoid" >&2
  echo "       leaving root-owned files behind." >&2
  exit 1
fi

# === 1. Symlink skills ====================================================
# L1 fix: avoid -L/-e race by failing fast if non-symlink exists.
# H6: `ln -snf` is NOT atomic — it unlinks the old name then creates the new
# one, leaving a brief window with no target. We do an atomic swap instead:
# create the symlink under a temp name, then `mv -T` (rename) it into place,
# which is a single atomic syscall with no missing-target window.
echo "[pai-hermes install] symlinking skills..."
mkdir -p "$(dirname "$HERMES_SKILLS_DIR")"
if [[ -e "$HERMES_SKILLS_DIR" && ! -L "$HERMES_SKILLS_DIR" ]]; then
  echo "ERROR: $HERMES_SKILLS_DIR exists and is not a symlink" >&2
  exit 1
fi
LINK_TMP="${HERMES_SKILLS_DIR}.tmp.$$"
ln -s "$REPO_DIR/skills" "$LINK_TMP"
mv -T "$LINK_TMP" "$HERMES_SKILLS_DIR"
echo "  $HERMES_SKILLS_DIR -> $REPO_DIR/skills"

# === 2. Patch config.yaml (ruamel round-trip + validate-rollback) ========
# H5: config path is passed as an argument/env to the external tool, never
# interpolated into a `python3 -c` string. H2: the tool writes atomically
# (temp in same dir, fsync, os.replace) and re-parses before swapping.
echo "[pai-hermes install] patching config.yaml external_dirs..."
BACKUP="${HERMES_CONFIG}.bak"
# H1: refuse if backup target is a symlink (could overwrite an arbitrary file
# the user can write). Mirror uninstall.sh's guard before the cp.
if [[ -L "$BACKUP" ]]; then
  echo "ERROR: $BACKUP is a symlink, refusing to overwrite" >&2
  exit 1
fi
cp --no-dereference --remove-destination "$HERMES_CONFIG" "$BACKUP"   # always backup before patch
echo "  backup: $BACKUP"

validate_yaml() {
  HERMES_CONFIG="$HERMES_CONFIG" python3 -c \
    'import os; from ruamel.yaml import YAML; YAML(typ="rt").load(open(os.environ["HERMES_CONFIG"]).read())' \
    2>/dev/null
}

if PATCH_OUT=$(HERMES_CONFIG="$HERMES_CONFIG" python3 "$PATCH_TOOL" \
      --add-external-dir "$HERMES_SKILLS_DIR" 2>&1); then
  case "$PATCH_OUT" in
    ADDED|ALREADY_PRESENT)
      if ! validate_yaml; then
        echo "ERROR: config.yaml fails YAML parse after patch. Restoring from $BACKUP." >&2
        mv "$BACKUP" "$HERMES_CONFIG"
        exit 1
      fi
      if [[ "$PATCH_OUT" == "ADDED" ]]; then
        echo "  added: external_dirs += $HERMES_SKILLS_DIR"
      else
        echo "  external_dirs already includes $HERMES_SKILLS_DIR (no change)"
      fi
      echo "  validated: post-patch YAML parses OK"
      rm "$BACKUP"
      ;;
    *)
      echo "ERROR: unexpected patcher output: $PATCH_OUT — restoring from $BACKUP." >&2
      mv "$BACKUP" "$HERMES_CONFIG"
      exit 1
      ;;
  esac
else
  echo "ERROR: config.yaml patch failed ($PATCH_OUT). Restoring from $BACKUP." >&2
  mv "$BACKUP" "$HERMES_CONFIG"
  exit 1
fi

# === 3. Validate skills format ============================================
echo "[pai-hermes install] validating SKILL.md frontmatter..."
if command -v bats >/dev/null 2>&1; then
  bats "$REPO_DIR/tests/skill-format.bats" || { echo "ERROR: skill format validation failed" >&2; exit 1; }
else
  echo "  WARN: bats not installed, skipping validation"
fi

# === 4. Cron registration instructions ====================================
cat <<EOF

[pai-hermes install] DONE.

═══════════════════════════════════════════════════════════════════
NEXT STEP: register cron jobs via Hermes (NOT symlinked files).

0.1.1 corrects 0.1.0's wrong assumption that ~/.hermes/cron/*.yaml
is loaded automatically. Real Hermes cron is JSON-based, managed by
Hermes's cronjob tool, NOT by filesystem drops.

Open a Hermes session (TUI/Telegram/etc) and run the 3 registration
prompts documented in:

  $REPO_DIR/cron/README.md

After registration, verify:

  jq '.jobs[] | {name, schedule: .schedule.expr, enabled}' \\
    ~/.hermes/cron/jobs.json

Expected: 3 jobs (pai-watch, pai-cost-tracker, pai-statusline-banner).
═══════════════════════════════════════════════════════════════════

Other follow-ups:
  - Restart Hermes:           pkill hermes && hermes
  - Verify skills loaded:     hermes -> /skills | grep pai
  - Run pai-doctor:           hermes -> 'pai doctor'
  - Wire PAI canonical Packs (optional, gives 45 PAI skills):
    edit $HERMES_CONFIG: skills.external_dirs += <PAI canonical Packs path>
  - For pai-accept SSH-only enforcement, symlink the guard:
      ln -sf "$REPO_DIR/bin/pai-accept-guard" /usr/local/bin/pai-accept-guard

Uninstall: $REPO_DIR/uninstall.sh
EOF
