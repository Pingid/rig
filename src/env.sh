#!/usr/bin/env bash
#
# Remote resolution for rig. Sourced by bin.sh after lib.sh.
#
# A remote is either a raw host (`root@1.2.3.4`) or the name of a section in
# the global config. Resolution order, highest priority first:
#
#   1. `rig -r <name>` on the command line, or RIG_REMOTE=<name>
#   2. REMOTE=<host> in the environment            (one-off host override)
#   3. ./.rig.env                                  (REMOTE=<host>, or default=<name>)
#   4. `default = <name>` in the global config
#   5. a top-level REMOTE= in the global config    (the pre-named-remote form)
#   6. an interactive prompt

RIG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
RIG_CONFIG_GLOBAL="$RIG_CONFIG_HOME/rig/config"
RIG_CONFIG_LOCAL="./.rig.env"

# Previous versions stored config next to the script and read a bare ./.env.
# The former is inside the install prefix: read-only under Nix, and discarded
# on every `brew upgrade`. Both are still read when no new-style config
# exists, with a warning, but are never written to.
RIG_CONFIG_GLOBAL_LEGACY="$RIG_SRC/.env"
RIG_CONFIG_LOCAL_LEGACY="./.env"

# Which file to actually read, warning once if it is a deprecated location.
rig_global_config() {
  if [ -f "$RIG_CONFIG_GLOBAL" ]; then
    printf '%s' "$RIG_CONFIG_GLOBAL"
  elif [ -f "$RIG_CONFIG_GLOBAL_LEGACY" ]; then
    rig_warn "reading deprecated $RIG_CONFIG_GLOBAL_LEGACY; move it to $RIG_CONFIG_GLOBAL"
    printf '%s' "$RIG_CONFIG_GLOBAL_LEGACY"
  else
    printf '%s' "$RIG_CONFIG_GLOBAL"
  fi
}

rig_local_config() {
  if [ -f "$RIG_CONFIG_LOCAL" ]; then
    printf '%s' "$RIG_CONFIG_LOCAL"
  elif [ -f "$RIG_CONFIG_LOCAL_LEGACY" ]; then
    rig_warn "reading deprecated $RIG_CONFIG_LOCAL_LEGACY; rename it to $RIG_CONFIG_LOCAL"
    printf '%s' "$RIG_CONFIG_LOCAL_LEGACY"
  else
    printf '%s' "$RIG_CONFIG_LOCAL"
  fi
}

# Load a named remote, failing with a list of what is available.
rig_load_named() {
  local name=$1 global
  global=$(rig_global_config)
  if ! rig_config_section_load "$global" "$name"; then
    rig_strict || return 1
    rig_warn "no remote named '$name' in $global"
    local known
    known=$(rig_config_sections "$global" | tr '\n' ' ')
    if [ -n "$known" ]; then
      rig_warn "known remotes: $known"
    else
      rig_warn "no named remotes are defined; add one with: rig remotes add $name <host>"
    fi
    exit 1
  fi
  RIG_REMOTE_NAME=$name
  return 0
}

rig_resolve_remote() {
  local env_remote=${REMOTE:-} env_key=${REMOTE_KEY:-}
  local global local_file

  REMOTE=""
  REMOTE_KEY=""
  RIG_DEFAULT=""
  RIG_REMOTE_NAME=${RIG_REMOTE_NAME:-}

  global=$(rig_global_config)

  # 1. an explicitly named remote outranks everything.
  if [ -n "$RIG_REMOTE_NAME" ]; then
    rig_load_named "$RIG_REMOTE_NAME" || return 1
    [ -z "$env_key" ] || REMOTE_KEY=$env_key
    return 0
  fi

  # 2. REMOTE in the environment stays a one-off host override.
  if [ -n "$env_remote" ]; then
    REMOTE=$env_remote
    REMOTE_KEY=$env_key
    return 0
  fi

  # 3. the local config, which may name a remote instead of giving a host.
  local_file=$(rig_local_config)
  rig_config_load "$local_file"
  if [ -n "$RIG_DEFAULT" ] && [ -z "$REMOTE" ]; then
    rig_load_named "$RIG_DEFAULT" || return 1
  fi
  if [ -n "$REMOTE" ]; then
    [ -z "$env_key" ] || REMOTE_KEY=$env_key
    return 0
  fi

  # 4 and 5. the global config: a named default, else a top-level REMOTE.
  RIG_DEFAULT=""
  rig_config_load "$global"
  if [ -n "$RIG_DEFAULT" ]; then
    REMOTE=""
    REMOTE_KEY=""
    rig_load_named "$RIG_DEFAULT" || return 1
  fi

  [ -z "$env_key" ] || REMOTE_KEY=$env_key
  return 0
}

# Called by every subcommand that actually talks to a host. Subcommands that
# do not (help, version, remotes) must never reach this, so that rig is
# usable with no configuration at all.
rig_require_remote() {
  local answer

  if [ -n "$REMOTE" ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    rig_die "no remote configured; set REMOTE, pass -r <name>, or run rig interactively to save one"
  fi

  read -e -r -p "Remote address (eg root@165.227.230.38): " REMOTE || REMOTE=
  [ -n "$REMOTE" ] || rig_die "no remote given"

  while true; do
    read -r -p "Save this remote? local (l) / global (g) / don't save (n): " answer || answer=n
    case $answer in
    [Ll]*)
      rig_config_set "$RIG_CONFIG_LOCAL" REMOTE "$REMOTE"
      echo "rig: saved to $RIG_CONFIG_LOCAL" >&2
      break
      ;;
    [Gg]*)
      rig_config_set "$RIG_CONFIG_GLOBAL" REMOTE "$REMOTE"
      echo "rig: saved to $RIG_CONFIG_GLOBAL" >&2
      echo "rig: to keep several hosts, name them with: rig remotes add <name> <host>" >&2
      break
      ;;
    [Nn]*)
      break
      ;;
    *)
      echo "Please answer l, g or n." >&2
      ;;
    esac
  done

  return 0
}
