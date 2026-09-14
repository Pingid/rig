# Shared setup for the rig test suite.
#
# Each test runs in a scratch directory with a scratch HOME and stub
# ssh/rsync/scp binaries first on PATH. The stubs echo their argv, so the
# assertions can check exactly what rig would have executed — which is what
# catches quoting and connection-argument regressions without a network.
#
# $status, $output and $lines are set by bats' `run`, not by this file.
# shellcheck disable=SC2154

setup() {
  RIG_TEST_ROOT="$BATS_TEST_TMPDIR"
  RIG_BIN="$BATS_TEST_DIRNAME/../src/bin.sh"

  mkdir -p "$RIG_TEST_ROOT/stub" "$RIG_TEST_ROOT/home" "$RIG_TEST_ROOT/work"

  local b
  for b in ssh rsync scp ssh-copy-id; do
    # Quoted heredoc: the stub is written verbatim and names itself from $0.
    cat >"$RIG_TEST_ROOT/stub/$b" <<'STUB'
#!/bin/sh
printf '%s' "$(basename "$0")"
for a in "$@"; do printf ' <%s>' "$a"; done
printf '\n'
STUB
    chmod +x "$RIG_TEST_ROOT/stub/$b"
  done

  cd "$RIG_TEST_ROOT/work" || return 1
}

# Run rig in a pristine environment. Any KEY=VALUE arguments before the
# subcommand are passed through as environment variables.
rig() {
  run env -i \
    HOME="$RIG_TEST_ROOT/home" \
    PATH="$RIG_TEST_ROOT/stub:/usr/bin:/bin" \
    "${RIG_BASH:-bash}" "$RIG_BIN" "$@"
}

rig_env() {
  local vars=()
  while [ $# -gt 0 ]; do
    case $1 in
    *=*)
      vars+=("$1")
      shift
      ;;
    *) break ;;
    esac
  done
  run env -i \
    HOME="$RIG_TEST_ROOT/home" \
    PATH="$RIG_TEST_ROOT/stub:/usr/bin:/bin" \
    ${vars[@]+"${vars[@]}"} \
    "${RIG_BASH:-bash}" "$RIG_BIN" "$@"
}

assert_output_contains() {
  if [[ "$output" != *"$1"* ]]; then
    echo "expected output to contain: $1" >&2
    echo "actual output: $output" >&2
    return 1
  fi
}

refute_output_contains() {
  if [[ "$output" == *"$1"* ]]; then
    echo "expected output NOT to contain: $1" >&2
    echo "actual output: $output" >&2
    return 1
  fi
}
