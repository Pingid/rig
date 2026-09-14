#!/usr/bin/env bash
#
# Shared helpers for rig. Sourced by bin.sh; must stay compatible with the
# bash 3.2 that ships as /bin/bash on macOS (no associative arrays, no
# mapfile, and "${arr[@]}" on an empty array is an error under `set -u`,
# so empty-capable arrays are expanded as ${arr[@]+"${arr[@]}"}).

rig_die() {
  echo "rig: $*" >&2
  exit 1
}

# When RIG_STRICT is 0, a failure to resolve a named remote warns and returns
# non-zero instead of exiting. Used by commands that print information and
# should not be taken down by an unrelated bad entry in the config.
rig_strict() {
  [ "${RIG_STRICT:-1}" != "0" ]
}

rig_warn() {
  echo "rig: $*" >&2
}

# --- config file parsing ----------------------------------------------------
#
# The config is INI-shaped. Keys before the first [section] header are
# top-level; each [name] section defines a named remote:
#
#     default = prod
#
#     [prod]
#     remote = root@165.227.230.38
#     key    = ~/.ssh/prod_ed25519
#
# The flat `REMOTE=...` form older versions wrote is just a file with no
# sections, so it keeps working unchanged.
#
# Deliberately narrow: only the keys rig itself understands are honoured. The
# original implementation used `export $(grep -v '^#' .env | xargs)`, which
# word-split on spaces, glob-expanded unquoted values, and exported *every*
# key it found in whatever .env happened to be in the working directory.

# Parse one line into the globals _section, _key and _value. Returns 1 for a
# line with nothing in it (blank or comment). Globals rather than a subshell
# so that callers can drive a read loop without forking per line.
_rig_parse_line() {
  local line=$1
  _section=""
  _key=""
  _value=""

  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}

  case $line in
  '' | '#'* | ';'*) return 1 ;;
  '['*']')
    _section=${line#\[}
    _section=${_section%\]}
    _section=${_section#"${_section%%[![:space:]]*}"}
    _section=${_section%"${_section##*[![:space:]]}"}
    return 0
    ;;
  esac

  line=${line#export }
  case $line in
  *=*) ;;
  *) return 1 ;;
  esac

  _key=${line%%=*}
  _value=${line#*=}

  _key=${_key%"${_key##*[![:space:]]}"}
  _key=$(printf '%s' "$_key" | tr '[:lower:]' '[:upper:]')
  _value=${_value#"${_value%%[![:space:]]*}"}

  # Strip one layer of matching quotes; on a bare value, honour the dotenv
  # convention that " #" starts a trailing comment.
  case $_value in
  '"'*'"')
    _value=${_value#\"}
    _value=${_value%\"}
    ;;
  "'"*"'")
    _value=${_value#\'}
    _value=${_value%\'}
    ;;
  *)
    case $_value in
    *" #"*) _value=${_value%%" #"*} ;;
    esac
    _value=${_value%"${_value##*[![:space:]]}"}
    ;;
  esac

  return 0
}

# `key = ~/.ssh/id` is read as data, so the shell never expands the tilde.
#
# SC2088: the tildes below are case *patterns* matching a literal "~" in the
# value, not paths this script wants expanded.
# shellcheck disable=SC2088
rig_expand_tilde() {
  case $1 in
  '~') printf '%s' "$HOME" ;;
  '~/'*) printf '%s%s' "$HOME" "${1#\~}" ;;
  *) printf '%s' "$1" ;;
  esac
}

# Canonical name for a config key, so that `key`, `KEY`, `remote` and
# `REMOTE` all land on the variable rig actually reads.
_rig_canonical_key() {
  case $1 in
  REMOTE | HOST) echo REMOTE ;;
  REMOTE_KEY | KEY | IDENTITY) echo REMOTE_KEY ;;
  DEFAULT | DEFAULT_REMOTE) echo DEFAULT ;;
  *) echo "" ;;
  esac
}

# Load the top-level keys of a file into REMOTE / REMOTE_KEY / RIG_DEFAULT,
# stopping at the first section header.
#
# SC2034: setting those three globals is the entire point; they are read in
# env.sh and bin.sh, which shellcheck analyses separately.
# shellcheck disable=SC2034
rig_config_load() {
  local file=$1 line canon
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    _rig_parse_line "$line" || continue
    [ -z "$_section" ] || break

    canon=$(_rig_canonical_key "$_key")
    case $canon in
    REMOTE) REMOTE=$_value ;;
    REMOTE_KEY) REMOTE_KEY=$(rig_expand_tilde "$_value") ;;
    DEFAULT) RIG_DEFAULT=$_value ;;
    esac
  done <"$file"

  return 0
}

# Print one top-level key, last occurrence winning. Unlike rig_config_load
# this assigns none of rig's globals, so it is safe to call after a remote has
# already been resolved.
rig_config_get() {
  local file=$1 want=$2 line canon out=""
  [ -f "$file" ] || return 0
  want=$(_rig_canonical_key "$want")

  while IFS= read -r line || [ -n "$line" ]; do
    _rig_parse_line "$line" || continue
    [ -z "$_section" ] || break
    canon=$(_rig_canonical_key "$_key")
    [ "$canon" = "$want" ] || continue
    out=$_value
  done <"$file"

  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}

# Load one named section into REMOTE / REMOTE_KEY. Returns 1 if the section
# is not present.
#
# shellcheck disable=SC2034  # REMOTE/REMOTE_KEY are read by env.sh and bin.sh
rig_config_section_load() {
  local file=$1 want=$2 line canon cur="" found=1
  [ -f "$file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    _rig_parse_line "$line" || continue

    if [ -n "$_section" ]; then
      cur=$_section
      [ "$cur" != "$want" ] || found=0
      continue
    fi

    [ "$cur" = "$want" ] || continue

    canon=$(_rig_canonical_key "$_key")
    case $canon in
    REMOTE) REMOTE=$_value ;;
    REMOTE_KEY) REMOTE_KEY=$(rig_expand_tilde "$_value") ;;
    esac
  done <"$file"

  return $found
}

# Print the name of every section, one per line, in file order.
rig_config_sections() {
  local file=$1 line
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    _rig_parse_line "$line" || continue
    [ -z "$_section" ] || printf '%s\n' "$_section"
  done <"$file"
  return 0
}

# Print one key from one section.
rig_config_section_get() {
  local file=$1 want=$2 key=$3 line cur="" canon
  [ -f "$file" ] || return 0
  key=$(_rig_canonical_key "$key")
  while IFS= read -r line || [ -n "$line" ]; do
    _rig_parse_line "$line" || continue
    if [ -n "$_section" ]; then
      cur=$_section
      continue
    fi
    [ "$cur" = "$want" ] || continue
    canon=$(_rig_canonical_key "$_key")
    [ "$canon" = "$key" ] || continue
    printf '%s\n' "$_value"
  done <"$file"
  return 0
}

# --- config file writing ----------------------------------------------------

_rig_mktemp_beside() {
  local dir=$1
  mkdir -p "$dir" || rig_die "cannot create $dir"
  mktemp "$dir/.rig.XXXXXX" || rig_die "cannot write to $dir"
}

# Write a top-level KEY=VALUE, replacing any existing top-level entry. The
# value is inserted before the first section header, so that it cannot be
# swallowed into whichever section happens to be last in the file.
rig_config_set() {
  local file=$1 key=$2 value=$3 tmp line top=1
  tmp=$(_rig_mktemp_beside "$(dirname "$file")")

  # Written at the very top, so a top-level key can never be captured by a
  # section and its placement does not depend on what is already in the file.
  printf '%s=%s\n' "$key" "$value" >>"$tmp"

  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if _rig_parse_line "$line" && [ -n "$_section" ]; then
        top=0
      elif [ "$top" -eq 1 ] && [ "$(_rig_canonical_key "$_key")" = "$key" ]; then
        continue
      fi
      printf '%s\n' "$line" >>"$tmp"
    done <"$file"
  fi

  mv "$tmp" "$file" || rig_die "cannot write $file"
}

# Remove a top-level key entirely.
rig_config_unset() {
  local file=$1 key=$2 tmp line top=1
  [ -f "$file" ] || return 0
  tmp=$(_rig_mktemp_beside "$(dirname "$file")")

  while IFS= read -r line || [ -n "$line" ]; do
    if _rig_parse_line "$line" && [ -n "$_section" ]; then
      top=0
    elif [ "$top" -eq 1 ] && [ "$(_rig_canonical_key "$_key")" = "$key" ]; then
      continue
    fi
    printf '%s\n' "$line" >>"$tmp"
  done <"$file"

  mv "$tmp" "$file" || rig_die "cannot write $file"
}

# Write KEY=VALUE inside [name], creating the section if it does not exist.
rig_config_section_set() {
  local file=$1 name=$2 key=$3 value=$4 tmp line cur="" written=0 seen=0
  tmp=$(_rig_mktemp_beside "$(dirname "$file")")

  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      if _rig_parse_line "$line" && [ -n "$_section" ]; then
        # Leaving the target section without having written the key.
        if [ "$cur" = "$name" ] && [ "$written" -eq 0 ]; then
          printf '  %s = %s\n' "$key" "$value" >>"$tmp"
          written=1
        fi
        cur=$_section
        [ "$cur" != "$name" ] || seen=1
      elif [ "$cur" = "$name" ] &&
        [ "$(_rig_canonical_key "$_key")" = "$key" ]; then
        # Replace rather than duplicate.
        printf '  %s = %s\n' "$key" "$value" >>"$tmp"
        written=1
        continue
      fi
      printf '%s\n' "$line" >>"$tmp"
    done <"$file"
  fi

  if [ "$seen" -eq 1 ]; then
    [ "$written" -eq 1 ] || printf '  %s = %s\n' "$key" "$value" >>"$tmp"
  elif [ -s "$tmp" ]; then
    printf '\n[%s]\n  %s = %s\n' "$name" "$key" "$value" >>"$tmp"
  else
    # No blank line at the top of a file we are creating.
    printf '[%s]\n  %s = %s\n' "$name" "$key" "$value" >>"$tmp"
  fi

  mv "$tmp" "$file" || rig_die "cannot write $file"
}

# Delete a whole section.
rig_config_section_remove() {
  local file=$1 name=$2 tmp line cur="" removed=1
  [ -f "$file" ] || return 1
  tmp=$(_rig_mktemp_beside "$(dirname "$file")")

  while IFS= read -r line || [ -n "$line" ]; do
    if _rig_parse_line "$line" && [ -n "$_section" ]; then
      cur=$_section
      if [ "$cur" = "$name" ]; then
        removed=0
        continue
      fi
    fi
    [ "$cur" != "$name" ] || continue
    printf '%s\n' "$line" >>"$tmp"
  done <"$file"

  if [ "$removed" -eq 0 ]; then
    mv "$tmp" "$file" || rig_die "cannot write $file"
  else
    rm -f "$tmp"
  fi
  return $removed
}
