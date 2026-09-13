#!/usr/bin/env bats

load helper

@test "version prints the VERSION file" {
  rig version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$BATS_TEST_DIRNAME/../VERSION")" ]
}

@test "--version and -v are aliases" {
  rig --version
  [ "$status" -eq 0 ]
  rig -v
  [ "$status" -eq 0 ]
}

@test "help exits 0 and needs no configuration" {
  rig help
  [ "$status" -eq 0 ]
  assert_output_contains "commands"
  refute_output_contains "Remote address"
}

@test "no arguments prints usage and exits 1" {
  rig
  [ "$status" -eq 1 ]
  assert_output_contains "commands"
}

@test "unknown command is reported as unknown, not as a missing remote" {
  rig bogus
  [ "$status" -eq 1 ]
  assert_output_contains "unknown command 'bogus'"
  refute_output_contains "no remote configured"
}

@test "a host command without a remote fails instead of hanging on a prompt" {
  rig ssh
  [ "$status" -eq 1 ]
  assert_output_contains "no remote configured"
}

@test "ssh passes the remote through" {
  rig_env REMOTE=me@host ssh
  [ "$status" -eq 0 ]
  assert_output_contains "ssh <me@host>"
}

@test "run does not double-expand the remote command" {
  # ssh already hands its arguments to the remote login shell; an extra eval
  # made the remote parse them a second time.
  rig_env REMOTE=me@host run 'echo $HOME'
  [ "$status" -eq 0 ]
  assert_output_contains 'ssh <me@host> <echo $HOME>'
  refute_output_contains "eval"
}

@test "run requires a command" {
  rig_env REMOTE=me@host run
  [ "$status" -eq 1 ]
  assert_output_contains "usage: rig run"
}

@test "apt runs non-interactively" {
  rig_env REMOTE=me@host apt install ripgrep
  [ "$status" -eq 0 ]
  assert_output_contains "DEBIAN_FRONTEND=noninteractive"
  assert_output_contains "-y"
}

@test "push preserves paths containing spaces" {
  rig_env REMOTE=me@host push "./dir with spaces" /tmp/dest
  [ "$status" -eq 0 ]
  assert_output_contains "<./dir with spaces>"
  assert_output_contains "<me@host:/tmp/dest>"
}

@test "pull does not prefix an absolute destination with the working directory" {
  rig_env REMOTE=me@host pull /var/log/syslog /tmp/syslog
  [ "$status" -eq 0 ]
  assert_output_contains "<me@host:/var/log/syslog>"
  assert_output_contains "</tmp/syslog>"
  refute_output_contains "//tmp/syslog"
}

@test "scp uses the destination verbatim" {
  # A previous version did DEST="${2:1}", dropping the first character.
  rig_env REMOTE=me@host scp ./file /tmp/file
  [ "$status" -eq 0 ]
  assert_output_contains "<me@host:/tmp/file>"
  refute_output_contains "/tmp/ile"
}

@test "push, pull and scp all require two arguments" {
  for cmd in push pull scp; do
    rig_env REMOTE=me@host "$cmd" only-one
    [ "$status" -eq 1 ]
    assert_output_contains "usage: rig $cmd"
  done
}

@test "tunnel rejects a non-numeric port" {
  rig_env REMOTE=me@host tunnel abc
  [ "$status" -eq 1 ]
  assert_output_contains "port must be a number"
}

@test "tunnel forwards the port" {
  rig_env REMOTE=me@host tunnel 8080
  [ "$status" -eq 0 ]
  assert_output_contains "<-N> <-L> <8080:localhost:8080> <me@host>"
}

@test "install rejects an unknown target" {
  rig_env REMOTE=me@host install bogus
  [ "$status" -eq 1 ]
  assert_output_contains "unknown install target 'bogus'"
}

@test "install node validates its version argument" {
  rig_env REMOTE=me@host install node "x; rm -rf /"
  [ "$status" -eq 1 ]
  assert_output_contains "must be a number"
}

@test "install docker_compose explains its removal" {
  rig_env REMOTE=me@host install docker_compose
  [ "$status" -eq 1 ]
  assert_output_contains "docker compose"
}
