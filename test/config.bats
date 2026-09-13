#!/usr/bin/env bats

load helper

global_config() {
  mkdir -p "$RIG_TEST_ROOT/home/.config/rig"
  cat >"$RIG_TEST_ROOT/home/.config/rig/config"
}

@test "the global config supplies a remote" {
  global_config <<<"REMOTE=global@host"
  rig ssh
  [ "$status" -eq 0 ]
  assert_output_contains "ssh <global@host>"
}

@test "a local .rig.env outranks the global config" {
  global_config <<<"REMOTE=global@host"
  echo "REMOTE=local@host" >.rig.env
  rig ssh
  assert_output_contains "ssh <local@host>"
}

@test "the environment outranks both config files" {
  global_config <<<"REMOTE=global@host"
  echo "REMOTE=local@host" >.rig.env
  rig_env REMOTE=env@host ssh
  assert_output_contains "ssh <env@host>"
}

@test "comments and blank lines are ignored" {
  cat >.rig.env <<'EOF'
# leading comment

REMOTE=me@host
EOF
  rig ssh
  assert_output_contains "ssh <me@host>"
}

@test "quoted values keep their spaces and lose their quotes" {
  cat >.rig.env <<'EOF'
REMOTE="me@host"
REMOTE_KEY="/keys/my key.pem"
EOF
  rig ssh
  assert_output_contains "ssh <-i> </keys/my key.pem> <me@host>"
}

@test "single quotes are stripped too" {
  echo "REMOTE='me@host'" >.rig.env
  rig ssh
  assert_output_contains "ssh <me@host>"
}

@test "a trailing comment is stripped from a bare value" {
  echo "REMOTE=me@host   # the box" >.rig.env
  rig ssh
  assert_output_contains "ssh <me@host>"
  refute_output_contains "the box"
}

@test "export prefixes are tolerated" {
  echo "export REMOTE=me@host" >.rig.env
  rig ssh
  assert_output_contains "ssh <me@host>"
}

@test "keys other than REMOTE and REMOTE_KEY are not read" {
  # The old parser exported every key it found in whatever .env was in the
  # working directory.
  cat >.rig.env <<'EOF'
REMOTE=me@host
SECRET=leaked
EOF
  rig_env REMOTE=me@host run 'echo'
  [ "$status" -eq 0 ]
  refute_output_contains "leaked"
}

@test "a legacy ./.env is still read, with a deprecation notice" {
  echo "REMOTE=legacy@host" >.env
  rig ssh
  [ "$status" -eq 0 ]
  assert_output_contains "deprecated ./.env"
  assert_output_contains "ssh <legacy@host>"
}

@test "a new-style config wins over the legacy file without warning" {
  echo "REMOTE=legacy@host" >.env
  echo "REMOTE=current@host" >.rig.env
  rig ssh
  assert_output_contains "ssh <current@host>"
  refute_output_contains "deprecated"
}

@test "REMOTE_KEY reaches rsync via -e, not as rsync's -i" {
  # rsync's -i is --itemize-changes; passing the key there meant the key was
  # never used and was treated as another source path.
  cat >.rig.env <<'EOF'
REMOTE=me@host
REMOTE_KEY=/keys/id_ed25519
EOF
  rig push ./a /tmp/b
  [ "$status" -eq 0 ]
  assert_output_contains "<-e> <ssh -i /keys/id_ed25519>"
}

@test "REMOTE_KEY reaches ssh and scp as -i" {
  cat >.rig.env <<'EOF'
REMOTE=me@host
REMOTE_KEY=/keys/id_ed25519
EOF
  rig ssh
  assert_output_contains "ssh <-i> </keys/id_ed25519> <me@host>"
  rig scp ./a /tmp/b
  assert_output_contains "scp <-i> </keys/id_ed25519>"
}

@test "an absent REMOTE_KEY adds no connection arguments" {
  # Guards the bash 3.2 empty-array expansion.
  echo "REMOTE=me@host" >.rig.env
  rig ssh
  [ "$status" -eq 0 ]
  # The banner rig prints goes to stderr, so assert on the invocation itself.
  [ "${lines[${#lines[@]} - 1]}" = "ssh <me@host>" ]
}
