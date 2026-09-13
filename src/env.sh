#!/usr/bin/env bash
#
# Configuration loading for rig. Sourced by bin.sh after lib.sh.
#
# Precedence, lowest to highest:
#   1. global config  ${XDG_CONFIG_HOME:-$HOME/.config}/rig/config
#   2. local config   ./.rig.env
#   3. the real environment
#
# so `REMOTE=other rig ssh` is always a one-off override.

RIG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
RIG_CONFIG_GLOBAL="$RIG_CONFIG_HOME/rig/config"
RIG_CONFIG_LOCAL="./.rig.env"

# Previous versions stored config next to the script and read a bare ./.env.
# The former is inside the install prefix: read-only under Nix, and discarded
# on every `brew upgrade`. Both are still read when no new-style config exists,
# with a warning, but are never written to.
RIG_CONFIG_GLOBAL_LEGACY="$RIG_SRC/.env"
RIG_CONFIG_LOCAL_LEGACY="./.env"

rig_config_load_all() {
  local env_remote=${REMOTE:-} env_remote_key=${REMOTE_KEY:-}

  if [ -f "$RIG_CONFIG_GLOBAL" ]; then
    rig_config_load "$RIG_CONFIG_GLOBAL"
  elif [ -f "$RIG_CONFIG_GLOBAL_LEGACY" ]; then
    rig_warn "reading deprecated $RIG_CONFIG_GLOBAL_LEGACY; move it to $RIG_CONFIG_GLOBAL"
    rig_config_load "$RIG_CONFIG_GLOBAL_LEGACY"
  fi

  if [ -f "$RIG_CONFIG_LOCAL" ]; then
    rig_config_load "$RIG_CONFIG_LOCAL"
  elif [ -f "$RIG_CONFIG_LOCAL_LEGACY" ]; then
    rig_warn "reading deprecated $RIG_CONFIG_LOCAL_LEGACY; rename it to $RIG_CONFIG_LOCAL"
    rig_config_load "$RIG_CONFIG_LOCAL_LEGACY"
  fi

  # The real environment outranks both files.
  [ -z "$env_remote" ] || REMOTE=$env_remote
  [ -z "$env_remote_key" ] || REMOTE_KEY=$env_remote_key

  REMOTE=${REMOTE:-}
  REMOTE_KEY=${REMOTE_KEY:-}

  return 0
}

# Called by every subcommand that actually talks to a host. Subcommands that
# do not (help, version) must never reach this, so that `rig` is usable with
# no configuration at all.
rig_require_remote() {
  local answer

  if [ -n "$REMOTE" ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    rig_die "no remote configured; set REMOTE, or run rig interactively to save one"
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
