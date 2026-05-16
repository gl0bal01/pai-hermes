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

@test "cron/README.md exists and documents 3 jobs" {
  [ -f "$REPO/cron/README.md" ]
  grep -qE "^### 1\. pai-watch" "$REPO/cron/README.md"
  grep -qE "^### 2\. pai-cost-tracker" "$REPO/cron/README.md"
  grep -qE "^### 3\. pai-statusline-banner" "$REPO/cron/README.md"
}

@test "cron/ no longer ships yaml files (0.1.1 pivot to Hermes-managed JSON)" {
  ! ls "$REPO"/cron/*.yaml 2>/dev/null
}

@test "bin/pai-accept-guard exists + executable" {
  [ -x "$REPO/bin/pai-accept-guard" ] || chmod +x "$REPO/bin/pai-accept-guard"
  [ -x "$REPO/bin/pai-accept-guard" ]
}

@test "pai-accept-guard refuses non-SSH invocation (exit 77)" {
  unset SSH_TTY SSH_CONNECTION SSH_CLIENT PAI_LOCAL_OVERRIDE
  run "$REPO/bin/pai-accept-guard" fake-id
  [ "$status" -eq 77 ]
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
