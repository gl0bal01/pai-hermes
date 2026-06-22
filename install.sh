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

# === 3a. pai-watch runtime environment ====================================
# pai-watch + pai-statusline-banner read PAI_PROJET_ROOT / PAI_PROPOSALS_DIR /
# PAI_WATCH_SOURCES from the gateway's process environment. The historical skill
# defaults (/opt/pai-projet, /var/lib/pai-anywhere/proposals) almost never match
# a real host — and the latter is owned by pai-anywhere's `pai` user, unwritable
# by the gateway — so pai-watch silently no-ops on a fresh install. Detect sane
# values, persist them to an EnvironmentFile, and wire them into the systemd
# --user gateway when that is how Hermes runs here. Idempotent.
echo "[pai-hermes install] configuring pai-watch environment..."

# Root: the parent of this checkout is the canonical pai-projet root when it
# holds sibling sub-projects (or is literally named pai-projet); else fall back
# to the documented default.
parent_dir="$(dirname "$REPO_DIR")"
if [[ -d "$parent_dir/Personal_AI_Infrastructure" || -d "$parent_dir/pai-anywhere" \
      || "$(basename "$parent_dir")" == "pai-projet" ]]; then
  PAI_PROJET_ROOT="$parent_dir"
else
  PAI_PROJET_ROOT="/opt/pai-projet"
fi

# Sources: keep only the default repos that actually exist as git clones, so the
# hourly watcher never wastes a run on absent repos.
PAI_WATCH_SOURCES=""
for repo in oh-my-claudecode Personal_AI_Infrastructure pai-anywhere pai-review-mode; do
  [[ -d "$PAI_PROJET_ROOT/$repo/.git" ]] && \
    PAI_WATCH_SOURCES="${PAI_WATCH_SOURCES:+$PAI_WATCH_SOURCES }$repo"
done

# Proposals dir: Hermes-writable XDG state location, created now.
PAI_PROPOSALS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pai-hermes/proposals"
mkdir -p "$PAI_PROPOSALS_DIR"

# Persist as a systemd EnvironmentFile (KEY=VALUE; values with spaces need no
# quoting in this format, unlike inline Environment= lines).
ENV_FILE="$HERMES_HOME/pai-hermes.env"
if [[ -L "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE is a symlink, refusing to overwrite" >&2
  exit 1
fi
( umask 077
  cat > "$ENV_FILE" <<ENV
# Written by pai-hermes install.sh — consumed by the Hermes gateway so pai-watch
# and pai-statusline-banner resolve the right paths. Re-run install.sh to refresh.
PAI_PROJET_ROOT=$PAI_PROJET_ROOT
PAI_PROPOSALS_DIR=$PAI_PROPOSALS_DIR
PAI_WATCH_SOURCES=$PAI_WATCH_SOURCES
ENV
)
chmod 600 "$ENV_FILE"
echo "  wrote $ENV_FILE"
echo "    PAI_PROJET_ROOT=$PAI_PROJET_ROOT"
echo "    PAI_PROPOSALS_DIR=$PAI_PROPOSALS_DIR"
echo "    PAI_WATCH_SOURCES=${PAI_WATCH_SOURCES:-<none found>}"
if [[ -z "$PAI_WATCH_SOURCES" ]]; then
  echo "  WARN: no watch sources found under $PAI_PROJET_ROOT — clone repos there"
  echo "        or edit PAI_WATCH_SOURCES in $ENV_FILE, then restart the gateway."
fi

# Wire into the systemd --user gateway when present (additive drop-in; reversed
# by uninstall.sh). Non-systemd launches get printed instructions instead.
GATEWAY_UNIT="hermes-gateway.service"
if command -v systemctl >/dev/null 2>&1 && systemctl --user cat "$GATEWAY_UNIT" >/dev/null 2>&1; then
  DROPIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/${GATEWAY_UNIT}.d"
  mkdir -p "$DROPIN_DIR"
  cat > "$DROPIN_DIR/pai-hermes.conf" <<DROPIN
[Service]
EnvironmentFile=$ENV_FILE
DROPIN
  systemctl --user daemon-reload 2>/dev/null || true
  if systemctl --user is-active --quiet "$GATEWAY_UNIT"; then
    systemctl --user restart "$GATEWAY_UNIT" 2>/dev/null \
      && echo "  wired EnvironmentFile into $GATEWAY_UNIT and restarted it" \
      || echo "  wired EnvironmentFile into $GATEWAY_UNIT (manual restart needed)"
  else
    echo "  wired EnvironmentFile into $GATEWAY_UNIT (start it to apply)"
  fi
else
  echo "  NOTE: Hermes gateway is not a systemd --user service here. Make your"
  echo "        gateway load $ENV_FILE before launch, e.g.:"
  echo "          set -a; . \"$ENV_FILE\"; set +a"
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
  - pai-watch env written to: $ENV_FILE (edit + restart gateway to change roots/sources)
  - Restart Hermes:           pkill hermes && hermes
  - Verify skills loaded:     hermes -> /skills | grep pai
  - Run pai-doctor:           hermes -> 'pai doctor'
  - Wire PAI canonical Packs (optional, gives 45 PAI skills):
    edit $HERMES_CONFIG: skills.external_dirs += <PAI canonical Packs path>
  - For pai-accept SSH-only enforcement, symlink the guard:
      ln -sf "$REPO_DIR/bin/pai-accept-guard" /usr/local/bin/pai-accept-guard

Uninstall: $REPO_DIR/uninstall.sh
EOF
