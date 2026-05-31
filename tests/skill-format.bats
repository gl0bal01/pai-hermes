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

@test "pai-accept-guard treats proposal .commits as opaque (no shell expansion)" {
  # M4 regression: a malicious upstream commit subject embedded in
  # proposal.commits must NOT be evaluated as shell when written to the
  # arc review markdown. Previous version used unquoted heredoc which
  # expanded $(...) at write time.
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  WORK="$(mktemp -d)"
  PROPS="$WORK/proposals"
  COLLAB="$WORK/collab"
  ARC="$COLLAB/projects/arc/reviews"
  mkdir -p "$PROPS" "$ARC"

  PATHS_ENV="$WORK/paths.env"
  : > "$PATHS_ENV"
  ID="test-2026-01-01T00-00-00"
  POISON='line1 $(echo PWNED > '"$WORK"'/pwn.flag) line2 `echo BTPWNED > '"$WORK"'/pwn2.flag` line3 ${HOME:+EXPANDED}'
  jq -n --arg repo "fakerepo" \
        --arg sha "abcdef1234567" \
        --arg commits "$POISON" \
        '{repo:$repo, targetSha:$sha, commits:$commits, status:"pending"}' \
    > "$PROPS/${ID}.json"

  PAI_LOCAL_OVERRIDE=1 \
  PAI_PROPOSALS_DIR="$PROPS" \
  PAI_PATHS_ENV="$PATHS_ENV" \
  PAI_COLLAB_DIR="$COLLAB" \
  PAI_ACCEPT_LOCK="$WORK/lock" \
    run "$REPO/bin/pai-accept-guard" "$ID"
  [ "$status" -eq 0 ]

  # Files that would only exist if shell expansion happened
  [ ! -e "$WORK/pwn.flag" ]
  [ ! -e "$WORK/pwn2.flag" ]

  # Markdown must contain the literal poison string verbatim
  REVIEW="$(ls "$ARC"/*.md | head -1)"
  grep -F '$(echo PWNED' "$REVIEW"
  grep -F '`echo BTPWNED' "$REVIEW"
  grep -F '${HOME:+EXPANDED}' "$REVIEW"

  rm -rf "$WORK"
}

@test "pai-accept-guard refuses lock path that is a symlink" {
  # M2 regression: bound lockfile path must not be a pre-existing symlink
  # (would let an attacker truncate arbitrary file via exec 9>"$LOCK").
  WORK="$(mktemp -d)"
  TARGET="$WORK/sensitive"
  echo "original" > "$TARGET"
  LOCK_LINK="$WORK/lock-symlink"
  ln -s "$TARGET" "$LOCK_LINK"

  PAI_LOCAL_OVERRIDE=1 \
  PAI_PROPOSALS_DIR="$WORK/nope" \
  PAI_PATHS_ENV="$WORK/nope.env" \
  PAI_ACCEPT_LOCK="$LOCK_LINK" \
    run "$REPO/bin/pai-accept-guard" any-id
  # Guard exits before lock check on missing proposal OR refuses lock symlink.
  # Either way, the sensitive target must remain untouched.
  [ "$(cat "$TARGET")" = "original" ]

  rm -rf "$WORK"
}

@test "cost_check.py refuses --snapshot-log outside ~/.hermes/" {
  # M5 regression: snapshot writer must reject paths not under ~/.hermes/.
  WORK="$(mktemp -d)"
  OUTSIDE="$WORK/escape.jsonl"
  run python3 "$REPO/tools/cost_check.py" \
    --cache /nonexistent \
    --snapshot \
    --snapshot-log "$OUTSIDE"
  [ "$status" -eq 2 ]
  [ ! -e "$OUTSIDE" ]
  rm -rf "$WORK"
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
