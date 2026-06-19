#!/usr/bin/env bats
# tests/wrappers.bats — safety wrapper tests for pai-pulse-send
#
# Tests:
#   1. Injection strings ($(…) and backticks) in --message are inert: no file
#      created, literal text appears in the JSON body sent to curl.
#   2. Non-loopback --url is refused with exit 77.
#   3. localhost URL passes validation.

REPO="${BATS_TEST_DIRNAME}/.."
BIN="${REPO}/bin/pai-pulse-send"

setup() {
  WORK="$(mktemp -d)"
  # Fake curl: dumps --data argument to $WORK/curl-data.txt, exits 0.
  # pai-pulse-send passes the JSON body via --data; we capture it here.
  FAKE_CURL="${WORK}/curl"
  cat > "${FAKE_CURL}" <<'FAKECURL'
#!/usr/bin/env bash
# Minimal curl stub for pai-pulse-send tests.
# Scan positional args for -w / --data / -X / -H / -s / -o flags and capture
# the --data value into $WORK/curl-data.txt.
data_next=0
for arg in "$@"; do
  if [[ "$data_next" == "1" ]]; then
    echo "$arg" > "${WORK}/curl-data.txt"
    data_next=0
    continue
  fi
  case "$arg" in
    --data|-d) data_next=1 ;;
    # -w format string: print a fake HTTP status so pai-pulse-send is happy.
    -w|--write-out) : ;;
  esac
done
# Print the HTTP status code pai-pulse-send reads via -w '%{http_code}'
echo "200"
FAKECURL
  # Embed $WORK into the fake curl so it knows where to write.
  # Replace the placeholder with the actual WORK path.
  sed -i "s|\${WORK}|${WORK}|g" "${FAKE_CURL}"
  chmod +x "${FAKE_CURL}"

  export PATH="${WORK}:${PATH}"
  export WORK
}

teardown() {
  rm -rf "${WORK}"
}

# ---------------------------------------------------------------------------
# Test 1: injection payload in --message is inert
# ---------------------------------------------------------------------------
@test "injection in --message is sent as literal text, no command executed" {
  # The payload contains $(), backticks, and ${} — all injection patterns.
  PWNED_FILE="${WORK}/PWNED_pulse"
  PAYLOAD="\$(touch ${PWNED_FILE}) \`touch ${PWNED_FILE}\` \${HOME}"

  run "${BIN}" --message "${PAYLOAD}" --url "http://127.0.0.1:31337"

  # The wrapper must succeed (curl stub returns 200).
  [ "$status" -eq 0 ]

  # No command must have executed — the pwned file must not exist.
  [ ! -e "${PWNED_FILE}" ]

  # The JSON body written to curl-data.txt must contain the literal string.
  [ -f "${WORK}/curl-data.txt" ]
  grep -qF '$(touch' "${WORK}/curl-data.txt"
  grep -qF '`touch'  "${WORK}/curl-data.txt"
  grep -qF '${HOME}' "${WORK}/curl-data.txt"
}

# ---------------------------------------------------------------------------
# Test 2: non-loopback URL is refused with exit 77
# ---------------------------------------------------------------------------
@test "non-loopback --url is refused with exit 77" {
  run "${BIN}" --message "hello" --url "http://evil.com/notify"
  [ "$status" -eq 77 ]
}

@test "https non-loopback --url is refused with exit 77" {
  run "${BIN}" --message "hello" --url "https://evil.com/notify"
  [ "$status" -eq 77 ]
}

@test "external IP --url is refused with exit 77" {
  run "${BIN}" --message "hello" --url "http://10.0.0.1:31337"
  [ "$status" -eq 77 ]
}

# ---------------------------------------------------------------------------
# Test 3: localhost URL is accepted
# ---------------------------------------------------------------------------
@test "localhost URL passes validation" {
  run "${BIN}" --message "hello" --url "http://localhost:31337"
  [ "$status" -eq 0 ]
}

@test "127.0.0.1 URL passes validation" {
  run "${BIN}" --message "ping" --url "http://127.0.0.1:31337"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Additional: missing --message exits 2
# ---------------------------------------------------------------------------
@test "missing --message exits 2" {
  run "${BIN}"
  [ "$status" -eq 2 ]
}

@test "message over 4096 bytes is rejected with exit 2" {
  LONG_MSG="$(python3 -c 'print("x" * 4097)')"
  run "${BIN}" --message "${LONG_MSG}" --url "http://127.0.0.1:31337"
  [ "$status" -eq 2 ]
}
