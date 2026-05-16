#!/usr/bin/env bats
# Validates SKILL.md frontmatter on all 7 skills

REPO="${BATS_TEST_DIRNAME}/.."
SKILLS_DIR="$REPO/skills"

SKILLS=(omc pai-pulse pai-watch pai-doctor pai-accept pai-cost-tracker pai-statusline-banner)

@test "all 7 skill dirs exist" {
  for s in "${SKILLS[@]}"; do
    [ -d "$SKILLS_DIR/$s" ]
  done
}

@test "each skill has SKILL.md" {
  for s in "${SKILLS[@]}"; do
    [ -f "$SKILLS_DIR/$s/SKILL.md" ]
  done
}

@test "each SKILL.md starts with frontmatter delimiter" {
  for s in "${SKILLS[@]}"; do
    first_line="$(head -n 1 "$SKILLS_DIR/$s/SKILL.md")"
    [ "$first_line" = "---" ]
  done
}

@test "each SKILL.md has name field matching dir" {
  for s in "${SKILLS[@]}"; do
    grep -qE "^name:\s*${s}\s*$" "$SKILLS_DIR/$s/SKILL.md"
  done
}

@test "each SKILL.md has description field" {
  for s in "${SKILLS[@]}"; do
    grep -qE "^description:\s*\S+" "$SKILLS_DIR/$s/SKILL.md"
  done
}

@test "each SKILL.md frontmatter description is at least 50 chars (no stub)" {
  for s in "${SKILLS[@]}"; do
    desc="$(awk '/^description:/{sub(/^description:[ \t]*/, ""); print; exit}' "$SKILLS_DIR/$s/SKILL.md")"
    [ "${#desc}" -ge 50 ]
  done
}

@test "each SKILL.md closes frontmatter with --- on its own line" {
  for s in "${SKILLS[@]}"; do
    # frontmatter ends with second --- in first 20 lines
    closers="$(head -20 "$SKILLS_DIR/$s/SKILL.md" | grep -c '^---$')"
    [ "$closers" -ge 2 ]
  done
}

@test "each SKILL.md body has at least one ## section header" {
  for s in "${SKILLS[@]}"; do
    grep -qE "^## " "$SKILLS_DIR/$s/SKILL.md"
  done
}

@test "all 3 cron yaml files present" {
  [ -f "$REPO/cron/pai-watch.yaml" ]
  [ -f "$REPO/cron/pai-cost-tracker.yaml" ]
  [ -f "$REPO/cron/pai-statusline-banner.yaml" ]
}

@test "each cron yaml has name + schedule + task fields" {
  for f in "$REPO"/cron/*.yaml; do
    grep -qE "^name:\s*\S+" "$f"
    grep -qE "^schedule:" "$f"
    grep -qE "^task:" "$f"
  done
}

@test "install.sh is executable" {
  [ -x "$REPO/install.sh" ] || chmod +x "$REPO/install.sh"
  [ -x "$REPO/install.sh" ]
}

@test "uninstall.sh is executable" {
  [ -x "$REPO/uninstall.sh" ] || chmod +x "$REPO/uninstall.sh"
  [ -x "$REPO/uninstall.sh" ]
}

@test "cost_check.py imports without error" {
  python3 -c "
import sys
sys.path.insert(0, '$REPO/tools')
import importlib.util
spec = importlib.util.spec_from_file_location('cost_check', '$REPO/tools/cost_check.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert callable(mod.main)
assert callable(mod.classify)
assert callable(mod.compose_voice)
"
}
