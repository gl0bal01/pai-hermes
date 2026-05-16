#!/usr/bin/env bash
# pai-hermes installer — idempotent wiring into Hermes Agent config
# shellcheck shell=bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
HERMES_SKILLS_DIR="$HERMES_HOME/skills/pai-hermes"
HERMES_CRON_DIR="$HERMES_HOME/cron"

echo "[pai-hermes install] repo=$REPO_DIR"
echo "[pai-hermes install] target=$HERMES_HOME"

# 0. Sanity
[[ -d "$HERMES_HOME" ]] || { echo "ERROR: Hermes not installed at $HERMES_HOME" >&2; exit 1; }
[[ -f "$HERMES_CONFIG" ]] || { echo "ERROR: $HERMES_CONFIG missing" >&2; exit 1; }

# 1. Symlink skills/ into Hermes skills dir
echo "[pai-hermes install] symlinking skills..."
mkdir -p "$(dirname "$HERMES_SKILLS_DIR")"
[[ -L "$HERMES_SKILLS_DIR" ]] && rm "$HERMES_SKILLS_DIR"
[[ -e "$HERMES_SKILLS_DIR" ]] && { echo "ERROR: $HERMES_SKILLS_DIR exists and is not a symlink" >&2; exit 1; }
ln -s "$REPO_DIR/skills" "$HERMES_SKILLS_DIR"
echo "  $HERMES_SKILLS_DIR -> $REPO_DIR/skills"

# 2. Symlink cron entries
echo "[pai-hermes install] symlinking cron entries..."
mkdir -p "$HERMES_CRON_DIR"
for cron_file in "$REPO_DIR"/cron/*.yaml; do
  [[ -f "$cron_file" ]] || continue
  base="$(basename "$cron_file")"
  target="$HERMES_CRON_DIR/$base"
  [[ -L "$target" ]] && rm "$target"
  [[ -e "$target" ]] && { echo "  WARN: $target exists, skipping" >&2; continue; }
  ln -s "$cron_file" "$target"
  echo "  $target -> $cron_file"
done

# 3. Edit config.yaml: append external_dirs entry if missing
echo "[pai-hermes install] checking config.yaml external_dirs..."
if grep -qE "^\s*-\s*${HERMES_SKILLS_DIR}\s*$" "$HERMES_CONFIG"; then
  echo "  external_dirs already includes $HERMES_SKILLS_DIR"
else
  echo "  patching config.yaml (backup: $HERMES_CONFIG.bak)"
  cp -n "$HERMES_CONFIG" "$HERMES_CONFIG.bak" 2>/dev/null || true
  # idempotent: add via marker comments
  python3 - "$HERMES_CONFIG" "$HERMES_SKILLS_DIR" <<'PYEOF'
import sys, re, pathlib
cfg_path = pathlib.Path(sys.argv[1])
skill_dir = sys.argv[2]
text = cfg_path.read_text()
# find skills.external_dirs block
m = re.search(r'^skills:\s*\n((?:^[ \t]+.*\n)+)', text, re.MULTILINE)
if not m:
    # append a new skills block
    text = text.rstrip() + f"\nskills:\n  external_dirs:\n    - {skill_dir}\n  template_vars: true\n"
else:
    block = m.group(1)
    if f'- {skill_dir}' in block:
        sys.exit(0)
    # find external_dirs line
    new_block = re.sub(
        r'^(\s*external_dirs:\s*)(\[\s*\]|\n)',
        lambda mm: f"{mm.group(1)}\n    - {skill_dir}" + ("\n" if mm.group(2) == '\n' else ""),
        block,
        count=1,
        flags=re.MULTILINE,
    )
    if new_block == block:
        # append as new list item below existing
        new_block = re.sub(
            r'^(\s*external_dirs:[^\n]*\n)',
            lambda mm: mm.group(1) + f"    - {skill_dir}\n",
            block,
            count=1,
            flags=re.MULTILINE,
        )
    text = text.replace(block, new_block)
cfg_path.write_text(text)
PYEOF
  echo "  added: external_dirs += $HERMES_SKILLS_DIR"
fi

# 4. Validate skills format
echo "[pai-hermes install] validating SKILL.md frontmatter..."
if command -v bats >/dev/null 2>&1; then
  bats "$REPO_DIR/tests/skill-format.bats" || { echo "ERROR: skill format validation failed" >&2; exit 1; }
else
  echo "  WARN: bats not installed, skipping validation"
fi

# 5. Probe Hermes can reach skills
echo ""
echo "[pai-hermes install] DONE."
echo ""
echo "Next steps:"
echo "  1. Restart Hermes:           pkill hermes && hermes"
echo "  2. Verify skills loaded:     hermes -> /skills | grep pai"
echo "  3. Verify cron registered:   hermes -> /cron list"
echo "  4. Run pai-doctor:           hermes -> 'pai doctor'"
echo "  5. Wire PAI canonical Packs (optional, gives 45 PAI skills):"
echo "     edit $HERMES_CONFIG: skills.external_dirs += <PAI canonical Packs path>"
echo ""
echo "Uninstall: $REPO_DIR/uninstall.sh"
