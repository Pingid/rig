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

rig_warn() {
  echo "rig: $*" >&2
}

# Read a single KEY=VALUE pair out of a config file.
#
# Deliberately narrow: only the keys rig itself uses are honoured, and only
# when the variable is not already set. The previous implementation used
# `export $(grep -v '^#' .env | xargs)`, which word-split on spaces, glob
# expanded unquoted values, and exported *every* key it found in whatever
# .env happened to be in the working directory.
rig_config_load() {
  local file=$1 line key value
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    # Trim surrounding whitespace.
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}

    case $line in
    '' | '#'*) continue ;;
    esac

    line=${line#export }
    case $line in
    *=*) ;;
    *) continue ;;
    esac

    key=${line%%=*}
    value=${line#*=}

    # Only the keys rig understands.
    case $key in
    REMOTE | REMOTE_KEY) ;;
    *) continue ;;
    esac

    # Strip one layer of matching quotes; on a bare value, honour the dotenv
    # convention that " #" starts a trailing comment.
    case $value in
    '"'*'"')
      value=${value#\"}
      value=${value%\"}
      ;;
    "'"*"'")
      value=${value#\'}
      value=${value%\'}
      ;;
    *)
      case $value in
      *" #"*) value=${value%%" #"*} ;;
      esac
      value=${value%"${value##*[![:space:]]}"}
      ;;
    esac

    eval "$key=\$value"
  done <"$file"

  return 0
}

# Write KEY=VALUE into a config file, replacing any existing entry for KEY
# rather than appending a duplicate.
rig_config_set() {
  local file=$1 key=$2 value=$3 dir tmp
  dir=$(dirname "$file")
  mkdir -p "$dir" || rig_die "cannot create $dir"

  tmp=$(mktemp "$dir/.rig.XXXXXX") || rig_die "cannot write to $dir"
  if [ -f "$file" ]; then
    grep -v "^[[:space:]]*\(export[[:space:]]*\)\?$key=" "$file" >"$tmp" || true
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  mv "$tmp" "$file" || rig_die "cannot write $file"
}
