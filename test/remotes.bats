#!/usr/bin/env bats

load helper

config_path() { echo "$RIG_TEST_ROOT/home/.config/rig/config"; }

@test "remotes needs no configuration and explains how to start" {
  rig remotes
  [ "$status" -eq 0 ]
  assert_output_contains "No named remotes"
  assert_output_contains "rig remotes add"
}

@test "the first remote added becomes the default" {
  rig remotes add prod root@1.2.3.4
  [ "$status" -eq 0 ]
  assert_output_contains "is now the default remote"
  grep -q '^DEFAULT=prod' "$(config_path)"
}

@test "a second remote does not steal the default" {
  rig remotes add prod root@1.2.3.4
  rig remotes add staging deploy@5.6.7.8
  refute_output_contains "is now the default"
  grep -q '^DEFAULT=prod' "$(config_path)"
}

@test "list marks the default and shows the identity" {
  rig remotes add prod root@1.2.3.4 /keys/prod
  rig remotes add staging deploy@5.6.7.8
  rig remotes
  assert_output_contains "* prod"
  assert_output_contains "root@1.2.3.4"
  assert_output_contains "(/keys/prod)"
  assert_output_contains "  staging"
}

@test "use can select a remote at any position in the file" {
  # Regression: the membership check was `rig_config_sections | grep -qxF`.
  # grep exits on the first match, the producer takes EPIPE on its next
  # write, and pipefail reported the pipeline as failed -- so selecting the
  # *first* remote in the file always failed while later ones worked.
  for n in alpha bravo charlie delta; do
    rig remotes add "$n" "$n@host"
  done
  for n in alpha bravo charlie delta alpha; do
    rig remotes use "$n"
    [ "$status" -eq 0 ]
    grep -q "^DEFAULT=$n\$" "$(config_path)"
  done
}

@test "use rejects an unknown remote" {
  rig remotes add prod root@1.2.3.4
  rig remotes use ghost
  [ "$status" -eq 1 ]
  assert_output_contains "no remote named 'ghost'"
}

@test "the default is never duplicated in the file" {
  rig remotes add a a@h
  rig remotes add b b@h
  rig remotes use b
  rig remotes use a
  [ "$(grep -c '^DEFAULT=' "$(config_path)")" -eq 1 ]
}

@test "add updates an existing remote in place" {
  rig remotes add prod old@host
  rig remotes add prod new@host
  [ "$(grep -c '^\[prod\]' "$(config_path)")" -eq 1 ]
  rig remotes
  assert_output_contains "new@host"
  refute_output_contains "old@host"
}

@test "remove reassigns the default when it removed it" {
  rig remotes add alpha a@h
  rig remotes add bravo b@h
  rig remotes use alpha
  rig remotes remove alpha
  [ "$status" -eq 0 ]
  assert_output_contains "default is now 'bravo'"
  grep -q '^DEFAULT=bravo' "$(config_path)"
}

@test "removing the last remote clears the default" {
  rig remotes add only o@h
  rig remotes remove only
  assert_output_contains "default cleared"
  run grep -c 'DEFAULT' "$(config_path)"
  [ "$output" = "0" ]
}

@test "remove rejects an unknown remote" {
  rig remotes remove ghost
  [ "$status" -eq 1 ]
  assert_output_contains "no remote named 'ghost'"
}

@test "remote names with structural characters are rejected" {
  for bad in "has space" "br[ack]et" "eq=uals" "hash#mark"; do
    rig remotes add "$bad" some@host
    [ "$status" -eq 1 ]
    assert_output_contains "remote name cannot"
  done
}

@test "an unknown remotes subcommand is reported" {
  rig remotes bogus
  [ "$status" -eq 1 ]
  assert_output_contains "unknown remotes command 'bogus'"
}

# --- selecting a remote ------------------------------------------------------

setup_two() {
  rig remotes add prod root@1.2.3.4 /keys/prod
  rig remotes add staging deploy@5.6.7.8
}

@test "the default remote is used when nothing else is given" {
  setup_two
  rig ssh
  assert_output_contains "ssh <-i> </keys/prod> <root@1.2.3.4>"
}

@test "-r selects a named remote" {
  setup_two
  rig -r staging ssh
  assert_output_contains "ssh <deploy@5.6.7.8>"
}

@test "--remote=, -rNAME and RIG_REMOTE all select a remote" {
  setup_two
  rig --remote=staging ssh
  assert_output_contains "<deploy@5.6.7.8>"
  rig -rstaging ssh
  assert_output_contains "<deploy@5.6.7.8>"
  rig --remote staging ssh
  assert_output_contains "<deploy@5.6.7.8>"
  rig_env RIG_REMOTE=staging ssh
  assert_output_contains "<deploy@5.6.7.8>"
}

@test "-r without a value is an error" {
  rig -r
  [ "$status" -eq 1 ]
  assert_output_contains "needs a remote name"
}

@test "-r with an unknown name lists what is available" {
  setup_two
  rig -r ghost ssh
  [ "$status" -eq 1 ]
  assert_output_contains "no remote named 'ghost'"
  assert_output_contains "known remotes:"
  assert_output_contains "prod"
}

@test "a local .rig.env can pin a directory to a named remote" {
  setup_two
  echo "default = staging" >.rig.env
  rig ssh
  assert_output_contains "<deploy@5.6.7.8>"
}

@test "-r overrides a local pin" {
  setup_two
  echo "default = staging" >.rig.env
  rig -r prod ssh
  assert_output_contains "<root@1.2.3.4>"
}

@test "a local raw REMOTE outranks the global default" {
  setup_two
  echo "REMOTE=raw@local" >.rig.env
  rig ssh
  assert_output_contains "ssh <raw@local>"
}

@test "REMOTE in the environment outranks the config, but not -r" {
  setup_two
  rig_env REMOTE=env@host ssh
  assert_output_contains "ssh <env@host>"
  rig_env REMOTE=env@host -r staging ssh
  assert_output_contains "<deploy@5.6.7.8>"
}

@test "a flat pre-named-remotes config still works" {
  mkdir -p "$RIG_TEST_ROOT/home/.config/rig"
  echo "REMOTE=flat@host" >"$(config_path)"
  rig ssh
  assert_output_contains "ssh <flat@host>"
}

@test "a default naming a missing remote does not break help" {
  mkdir -p "$RIG_TEST_ROOT/home/.config/rig"
  echo "DEFAULT=ghost" >"$(config_path)"
  rig help
  [ "$status" -eq 0 ]
  assert_output_contains "commands"
}

@test "a default naming a missing remote does fail a host command" {
  mkdir -p "$RIG_TEST_ROOT/home/.config/rig"
  echo "DEFAULT=ghost" >"$(config_path)"
  rig ssh
  [ "$status" -eq 1 ]
  assert_output_contains "no remote named 'ghost'"
}

@test "a tilde in an identity path is expanded" {
  rig remotes add prod root@1.2.3.4 '~/.ssh/prod'
  rig ssh
  assert_output_contains "<$RIG_TEST_ROOT/home/.ssh/prod>"
  refute_output_contains "<~/.ssh/prod>"
}

@test "section keys are case-insensitive and accept the short spellings" {
  mkdir -p "$RIG_TEST_ROOT/home/.config/rig"
  cat >"$(config_path)" <<'EOF'
default = prod

[prod]
  host = root@1.2.3.4
  key  = /keys/prod
EOF
  rig ssh
  assert_output_contains "ssh <-i> </keys/prod> <root@1.2.3.4>"
}

# --- copy-id -----------------------------------------------------------------

@test "copy-id installs the remote's configured identity" {
  rig remotes add prod root@1.2.3.4 /keys/prod
  rig copy-id
  [ "$status" -eq 0 ]
  assert_output_contains "ssh-copy-id <-i> </keys/prod> <root@1.2.3.4>"
}

@test "copy-id falls back to the default ssh identity" {
  rig remotes add plain deploy@5.6.7.8
  rig copy-id
  [ "$status" -eq 0 ]
  assert_output_contains "ssh-copy-id <deploy@5.6.7.8>"
  refute_output_contains "<-i>"
}

@test "copy-id accepts an explicit identity" {
  rig remotes add plain deploy@5.6.7.8
  touch explicit.pub
  rig copy-id ./explicit.pub
  [ "$status" -eq 0 ]
  assert_output_contains "ssh-copy-id <-i> <./explicit.pub> <deploy@5.6.7.8>"
}

@test "copy-id rejects an identity that does not exist" {
  rig remotes add plain deploy@5.6.7.8
  rig copy-id ./missing.pub
  [ "$status" -eq 1 ]
  assert_output_contains "no such identity file"
}

@test "copy-id takes at most one argument" {
  rig remotes add plain deploy@5.6.7.8
  rig copy-id a b
  [ "$status" -eq 1 ]
  assert_output_contains "usage: rig copy-id"
}

@test "copy-id expands a tilde in an explicit identity" {
  rig remotes add plain deploy@5.6.7.8
  mkdir -p "$RIG_TEST_ROOT/home/.ssh"
  touch "$RIG_TEST_ROOT/home/.ssh/given.pub"
  rig copy-id '~/.ssh/given.pub'
  [ "$status" -eq 0 ]
  assert_output_contains "<$RIG_TEST_ROOT/home/.ssh/given.pub>"
}
