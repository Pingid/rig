#!/usr/bin/env bash
#
# `rig remotes` - manage the named remotes in the global config. Sourced by
# bin.sh with the positional parameters already shifted past "remotes".
#
# Writes always go to RIG_CONFIG_GLOBAL, never to a deprecated location.

# The configured default remote name, read without disturbing the remote
# already resolved for this invocation.
rig_default_name() {
  rig_config_get "$1" DEFAULT
}

# Is NAME a defined section? Deliberately not `rig_config_sections | grep -q`:
# grep exits on the first match, the producer takes EPIPE on its next write,
# and `set -o pipefail` then reports the whole pipeline as failed -- so the
# check failed exactly when the match was the *first* remote in the file.
remotes_has() {
  local file=$1 want=$2 sections n found=1
  sections=$(rig_config_sections "$file")
  while IFS= read -r n; do
    [ "$n" != "$want" ] || found=0
  done <<EOF
$sections
EOF
  return $found
}

# First section name, or empty. Parameter expansion rather than `| head -1`,
# for the same reason.
remotes_first() {
  local sections
  sections=$(rig_config_sections "$1")
  printf '%s' "${sections%%$'\n'*}"
}

remotes_warn_shadow() {
  if [ ! -f "$RIG_CONFIG_GLOBAL" ] && [ -f "$RIG_CONFIG_GLOBAL_LEGACY" ]; then
    rig_warn "writing $RIG_CONFIG_GLOBAL, which will take precedence over"
    rig_warn "the deprecated $RIG_CONFIG_GLOBAL_LEGACY -- move any settings across"
  fi
}

remotes_check_name() {
  case $1 in
  '') rig_die "remote name cannot be empty" ;;
  *[][=#\ $'\t']*) rig_die "remote name cannot contain spaces, '=', '#', '[' or ']'" ;;
  esac
}

remotes_list() {
  local global default names name host key width=0 marker n
  global=$(rig_global_config)
  default=$(rig_default_name "$global")
  names=$(rig_config_sections "$global")

  if [ -z "$names" ]; then
    echo "No named remotes in $global" >&2
    echo "Add one with: rig remotes add <name> <user@host> [identity]" >&2
    # A pre-named-remotes config still has a usable top-level host.
    if [ -n "${REMOTE:-}" ]; then
      echo >&2
      echo "Current remote (unnamed): $REMOTE" >&2
    fi
    return 0
  fi

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ "${#n}" -le "$width" ] || width=${#n}
  done <<EOF
$names
EOF

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    host=$(rig_config_section_get "$global" "$name" REMOTE)
    key=$(rig_config_section_get "$global" "$name" REMOTE_KEY)
    if [ "$name" = "$default" ]; then marker="*"; else marker=" "; fi
    printf '%s %-*s  %s' "$marker" "$width" "$name" "${host:-<no host>}"
    [ -z "$key" ] || printf '  (%s)' "$key"
    printf '\n'
  done <<EOF
$names
EOF
}

remotes_add() {
  if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    rig_die "usage: rig remotes add <name> <user@host> [identity]"
  fi
  local name=$1 host=$2 identity=${3:-}
  remotes_check_name "$name"
  [ -n "$host" ] || rig_die "host cannot be empty"
  remotes_warn_shadow

  rig_config_section_set "$RIG_CONFIG_GLOBAL" "$name" REMOTE "$host"
  [ -z "$identity" ] ||
    rig_config_section_set "$RIG_CONFIG_GLOBAL" "$name" REMOTE_KEY "$identity"

  echo "rig: saved '$name' to $RIG_CONFIG_GLOBAL" >&2

  # The first remote added becomes the default, so that a single-remote setup
  # needs no second step.
  if [ -z "$(rig_default_name "$RIG_CONFIG_GLOBAL")" ]; then
    rig_config_set "$RIG_CONFIG_GLOBAL" DEFAULT "$name"
    echo "rig: '$name' is now the default remote" >&2
  fi
}

remotes_remove() {
  [ $# -eq 1 ] || rig_die "usage: rig remotes remove <name>"
  local name=$1 default remaining
  rig_config_section_remove "$RIG_CONFIG_GLOBAL" "$name" ||
    rig_die "no remote named '$name' in $RIG_CONFIG_GLOBAL"
  echo "rig: removed '$name'" >&2

  default=$(rig_default_name "$RIG_CONFIG_GLOBAL")
  [ "$default" = "$name" ] || return 0

  # The default pointed at what was just removed; move it or drop it.
  remaining=$(remotes_first "$RIG_CONFIG_GLOBAL")
  if [ -n "$remaining" ]; then
    rig_config_set "$RIG_CONFIG_GLOBAL" DEFAULT "$remaining"
    echo "rig: default is now '$remaining'" >&2
  else
    rig_config_unset "$RIG_CONFIG_GLOBAL" DEFAULT
    echo "rig: no remotes left; default cleared" >&2
  fi
}

remotes_use() {
  [ $# -eq 1 ] || rig_die "usage: rig remotes use <name>"
  local name=$1 global
  global=$(rig_global_config)
  remotes_has "$global" "$name" ||
    rig_die "no remote named '$name' in $global"
  remotes_warn_shadow
  rig_config_set "$RIG_CONFIG_GLOBAL" DEFAULT "$name"
  echo "rig: default remote is now '$name'" >&2
}

remotes_usage() {
  cat <<-END
rig remotes

  commands
    list                              list named remotes (the default)
    add <name> <user@host> [identity] define or update a remote
    remove <name>                     delete a remote
    use <name>                        make a remote the default

  The default remote is used when no -r/--remote is given. A local
  ./.rig.env can pin a directory to one with: default = <name>
END
}

remotes_command=${1:-list}
[ $# -eq 0 ] || shift

case $remotes_command in
'list' | 'ls') remotes_list "$@" ;;
'add' | 'set') remotes_add "$@" ;;
'remove' | 'rm' | 'delete') remotes_remove "$@" ;;
'use' | 'default') remotes_use "$@" ;;
'help' | '-h' | '--help') remotes_usage ;;
*)
  echo "rig: unknown remotes command '$remotes_command'" >&2
  remotes_usage >&2
  exit 1
  ;;
esac
