#!/usr/bin/env bats
# install-config.bats — exercises the real install.sh / uninstall.sh against a
# synthetic $HERMES_HOME, plus the tools/patch_hermes_config.py contract.
#
# Hardening coverage:
#   H9/H2/H5/H7 — config patching extracted to tools/patch_hermes_config.py and
#   driven by both scripts; append-not-replace; comments survive; idempotent;
#   never empty; no template_vars; rejects single-quote injection paths.

REPO="${BATS_TEST_DIRNAME}/.."
PATCH_TOOL="$REPO/tools/patch_hermes_config.py"

setup() {
  WORK="$(mktemp -d)"
  HH="$WORK/.hermes"
  CFG="$HH/config.yaml"
  SKILL_DIR="$HH/skills/pai-hermes"
  mkdir -p "$HH"
  # Hand-written config WITH comments and a pre-existing external_dirs entry.
  cat > "$CFG" <<'YAML'
# Hermes user config — hand edited, keep my comments!
model: claude-sonnet
skills:
  cache: true                      # leave skill cache enabled
  external_dirs:
    - /home/me/private-skills      # PRE-EXISTING — must not be dropped
  template_dir: ~/.hermes/templates
# trailing comment at EOF
YAML
}

teardown() {
  rm -rf "$WORK"
}

# ruamel is required by the patcher; skip the whole file gracefully if absent
# rather than reporting spurious failures on a host that hasn't bootstrapped it.
require_ruamel() {
  python3 -c "import ruamel.yaml" 2>/dev/null || skip "ruamel.yaml not importable"
}

# Run install.sh with a hermetic PATH so the real pip is never invoked and the
# nested skill-format bats run is skipped (keeps this file decoupled + fast).
run_install() {
  local fakebin="$WORK/fakebin"
  mkdir -p "$fakebin"
  # Shadow `bats` so install.sh section 3 prints its "not installed" WARN and
  # does not recurse into skill-format.bats from inside this test.
  PATH="$fakebin:$PATH" HERMES_HOME="$HH" run bash "$REPO/install.sh"
}

run_uninstall() {
  HERMES_HOME="$HH" run bash "$REPO/uninstall.sh"
}

@test "install.sh appends pai-hermes WITHOUT dropping the pre-existing entry" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  grep -qF '/home/me/private-skills' "$CFG"
  grep -qF "$SKILL_DIR" "$CFG"
}

@test "install.sh preserves user comments through the round-trip (H7)" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  grep -qF 'keep my comments!' "$CFG"
  grep -qF 'leave skill cache enabled' "$CFG"
  grep -qF 'PRE-EXISTING — must not be dropped' "$CFG"
  grep -qF 'trailing comment at EOF' "$CFG"
}

@test "install.sh injects NO template_vars key (H4)" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  ! grep -qE '^\s*template_vars\s*:' "$CFG"
}

@test "install.sh is idempotent — second run makes no duplicate, no breakage" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  run_install
  [ "$status" -eq 0 ]
  # exactly one occurrence of the pai-hermes path in external_dirs
  count="$(grep -cF "$SKILL_DIR" "$CFG")"
  [ "$count" -eq 1 ]
  # pre-existing entry still present exactly once
  pre="$(grep -cF '/home/me/private-skills' "$CFG")"
  [ "$pre" -eq 1 ]
}

@test "config is never left empty after install (H2)" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  [ -s "$CFG" ]
  # and it still parses as a YAML mapping
  HERMES_CONFIG="$CFG" python3 -c \
    'import os; from ruamel.yaml import YAML; d=YAML(typ="rt").load(open(os.environ["HERMES_CONFIG"]).read()); assert isinstance(d, dict)'
}

@test "no leftover backup after a successful install" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  [ ! -e "${CFG}.bak" ]
}

@test "uninstall.sh removes ONLY pai-hermes, keeps the pre-existing entry" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  run_uninstall
  [ "$status" -eq 0 ]
  ! grep -qF "$SKILL_DIR" "$CFG"
  grep -qF '/home/me/private-skills' "$CFG"
  grep -qF 'keep my comments!' "$CFG"
  [ -s "$CFG" ]
}

@test "uninstall.sh leaves no fixed .bak clobber file (H8)" {
  require_ruamel
  run_install
  [ "$status" -eq 0 ]
  run_uninstall
  [ "$status" -eq 0 ]
  [ ! -e "${CFG}.bak" ]
}

@test "patch tool rejects a config path containing a single quote without executing it (H5)" {
  require_ruamel
  # A basename crafted to break out of a `python3 -c '...'` string and run code
  # if the path were ever interpolated. The payload writes the flag via a
  # bare (slash-free) name so the *filename* stays a single path component;
  # `cd` into WORK first so a leaked write would land where we can detect it.
  cd "$WORK"
  FLAG_NAME="INJECTED.flag"
  EVIL_CFG="$WORK/x'; __import__('os').system('touch $FLAG_NAME'); '.yaml"
  cp "$CFG" "$EVIL_CFG"
  HERMES_CONFIG="$EVIL_CFG" run python3 "$PATCH_TOOL" --add-external-dir /some/dir
  # It must operate on the file as a literal path (success), never execute it.
  [ "$status" -eq 0 ]
  [ ! -e "$WORK/$FLAG_NAME" ]
  # The single-quote path's config was patched in place, proving it was treated
  # as a filesystem path and not shell/python code.
  grep -qF '/some/dir' "$EVIL_CFG"
}

@test "patch tool: missing config path errors (exit 2), never executes argv" {
  require_ruamel
  run python3 "$PATCH_TOOL" --add-external-dir /x "/no/such/dir/x'; bad .yaml"
  [ "$status" -eq 2 ]
}

@test "patch tool: mutually exclusive add/remove enforced" {
  require_ruamel
  run python3 "$PATCH_TOOL" --add-external-dir /a --remove-external-dir /b "$CFG"
  [ "$status" -ne 0 ]
}
