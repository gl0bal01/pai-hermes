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

echo "[pai-hermes install] repo=$REPO_DIR"
echo "[pai-hermes install] target=$HERMES_HOME"

# === 0. Sanity ============================================================
[[ -d "$HERMES_HOME" ]] || { echo "ERROR: Hermes not installed at $HERMES_HOME" >&2; exit 1; }
[[ -f "$HERMES_CONFIG" ]] || { echo "ERROR: $HERMES_CONFIG missing" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required" >&2; exit 1; }
python3 -c "import yaml" 2>/dev/null || {
  echo "ERROR: PyYAML required (pip install pyyaml). Hermes ships with PyYAML; check your venv." >&2
  exit 1
}

# === 1. Symlink skills ====================================================
# L1 fix: avoid -L/-e race by failing fast if non-symlink exists, then using
# `ln -snf` to replace symlinks atomically without a separate `rm` step.
echo "[pai-hermes install] symlinking skills..."
mkdir -p "$(dirname "$HERMES_SKILLS_DIR")"
if [[ -e "$HERMES_SKILLS_DIR" && ! -L "$HERMES_SKILLS_DIR" ]]; then
  echo "ERROR: $HERMES_SKILLS_DIR exists and is not a symlink" >&2
  exit 1
fi
ln -snf "$REPO_DIR/skills" "$HERMES_SKILLS_DIR"
echo "  $HERMES_SKILLS_DIR -> $REPO_DIR/skills"

# === 2. Patch config.yaml (pyyaml + validate-rollback) ===================
echo "[pai-hermes install] patching config.yaml external_dirs..."
BACKUP="${HERMES_CONFIG}.bak"
cp "$HERMES_CONFIG" "$BACKUP"   # always backup before patch
echo "  backup: $BACKUP"

if PYYAML_OK=$(HERMES_CONFIG="$HERMES_CONFIG" SKILL_DIR="$HERMES_SKILLS_DIR" python3 <<'PYEOF'
import os, sys, yaml, pathlib

cfg_path = pathlib.Path(os.environ["HERMES_CONFIG"])
skill_dir = os.environ["SKILL_DIR"]

raw = cfg_path.read_text()
try:
    data = yaml.safe_load(raw) or {}
except yaml.YAMLError as exc:
    print(f"YAML_PARSE_FAIL: {exc}", file=sys.stderr)
    sys.exit(2)

if not isinstance(data, dict):
    print("YAML_ROOT_NOT_MAPPING", file=sys.stderr)
    sys.exit(2)

skills = data.setdefault("skills", {})
if not isinstance(skills, dict):
    print("SKILLS_KEY_NOT_MAPPING", file=sys.stderr)
    sys.exit(2)

ext = skills.get("external_dirs")
if ext is None:
    skills["external_dirs"] = [skill_dir]
elif isinstance(ext, list):
    if skill_dir not in ext:
        ext.append(skill_dir)
    else:
        print("ALREADY_PRESENT")
        sys.exit(0)
else:
    print("EXTERNAL_DIRS_NOT_LIST", file=sys.stderr)
    sys.exit(2)

skills.setdefault("template_vars", True)

new_yaml = yaml.safe_dump(data, sort_keys=False, default_flow_style=False, allow_unicode=True)
cfg_path.write_text(new_yaml)
print("PATCHED")
PYEOF
); then
  # H1 fix: validate BEFORE any branch deletes the backup, and treat any
  # unexpected patcher output as fatal (was previously a silent warning).
  validate_yaml() {
    python3 -c "import sys, yaml; yaml.safe_load(open('$HERMES_CONFIG').read())" 2>/dev/null
  }
  case "$PYYAML_OK" in
    PATCHED)
      if ! validate_yaml; then
        echo "ERROR: patched config.yaml fails YAML parse. Rolling back from $BACKUP." >&2
        mv "$BACKUP" "$HERMES_CONFIG"
        exit 1
      fi
      echo "  added: external_dirs += $HERMES_SKILLS_DIR"
      echo "  validated: post-patch YAML parses OK"
      rm "$BACKUP"
      ;;
    ALREADY_PRESENT)
      # No write occurred, but still validate current on-disk YAML
      # before discarding rollback source (covers prior manual breakage).
      if ! validate_yaml; then
        echo "ERROR: config.yaml fails YAML parse (pre-existing). Restoring from $BACKUP." >&2
        mv "$BACKUP" "$HERMES_CONFIG"
        exit 1
      fi
      echo "  external_dirs already includes $HERMES_SKILLS_DIR (no change)"
      rm "$BACKUP"
      ;;
    *)
      echo "ERROR: unexpected patcher output: $PYYAML_OK — restoring from $BACKUP." >&2
      mv "$BACKUP" "$HERMES_CONFIG"
      exit 1
      ;;
  esac
else
  echo "ERROR: config.yaml patch failed. Restoring from $BACKUP." >&2
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
