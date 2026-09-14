#!/usr/bin/env bash
#
# rig - CLI for managing remote boxes over SSH.
#
# Targets bash 3.2, the /bin/bash on macOS. See src/lib.sh for the
# consequences of that.

set -euo pipefail

# Resolve this script's directory, following symlinks. Both the Homebrew and
# Nix installs symlink bin/rig at src/bin.sh, so $0 is not enough, and
# `readlink -f` is a GNU extension missing from older macOS and the BSDs.
# Inlined rather than sourced, because finding lib.sh is what it is for.
_src=${BASH_SOURCE[0]}
while [ -h "$_src" ]; do
  _dir=$(cd -P "$(dirname "$_src")" && pwd)
  _src=$(readlink "$_src")
  case $_src in
  /*) ;;
  *) _src=$_dir/$_src ;;
  esac
done
RIG_SRC=$(cd -P "$(dirname "$_src")" && pwd)
RIG_ROOT=$(dirname "$RIG_SRC")
unset _src _dir

# shellcheck source=src/lib.sh
source "$RIG_SRC/lib.sh"
# shellcheck source=src/env.sh
source "$RIG_SRC/env.sh"

# Global options, which must precede the subcommand: `rig -r staging ssh`.
RIG_REMOTE_NAME=${RIG_REMOTE:-}
while [ $# -gt 0 ]; do
  case $1 in
  -r | --remote)
    [ $# -ge 2 ] || rig_die "-r/--remote needs a remote name"
    RIG_REMOTE_NAME=$2
    shift 2
    ;;
  --remote=*)
    RIG_REMOTE_NAME=${1#--remote=}
    shift
    ;;
  -r?*)
    RIG_REMOTE_NAME=${1#-r}
    shift
    ;;
  --)
    shift
    break
    ;;
  *) break ;;
  esac
done

# Connection arguments are derived from the resolved remote, so they are
# built after resolution. REMOTE_KEY is optional, so every expansion is
# guarded for bash 3.2's empty-array handling under `set -u`.
ssh_args=()
rsync_args=()
rig_connection_args() {
  ssh_args=()
  rsync_args=()
  if [ -n "$REMOTE_KEY" ]; then
    ssh_args=(-i "$REMOTE_KEY")
    # rsync's -i is --itemize-changes, not an identity file: the key has to
    # go through -e instead, or rsync treats it as another source path.
    rsync_args=(-e "ssh -i $(printf '%q' "$REMOTE_KEY")")
  fi
}

rig_version() {
  if [ -f "$RIG_ROOT/VERSION" ]; then
    cat "$RIG_ROOT/VERSION"
  else
    echo "unknown"
  fi
}

rig_usage() {
  local shown=${REMOTE:-<not set>}
  [ -z "${RIG_REMOTE_NAME:-}" ] || shown="$RIG_REMOTE_NAME ($shown)"
  cat <<-END
rig [-r <name>] <command>

  REMOTE=$shown

  commands
    ssh                  ssh into the remote
    run <cmd>            run a command on the remote
    apt <args>           run apt on the remote
    push <from> <to>     rsync files to the remote
    pull <from> <to>     rsync files from the remote
    scp <from> <to>      copy a file to the remote
    copy-id [<identity>] install your ssh public key on the remote
    install <target>     install a program on the remote
    tunnel <port>        forward a local port to the remote
    remotes <sub>        manage named remotes (list, add, remove, use)
    version              print the rig version
    help                 show this message

  options
    -r, --remote <name>  use the named remote for this invocation
END
}

rig_run() {
  # ssh already concatenates its arguments and hands the result to the remote
  # login shell. The old code added `eval` on top of that, so the remote
  # parsed the string a second time and anything surviving the first pass was
  # expanded again. Join explicitly and let the remote shell parse it once.
  #
  # SC2029: expanding on the client side is the documented contract here --
  # `rig run` takes a command the caller has already quoted as they want it.
  # shellcheck disable=SC2029
  ssh ${ssh_args[@]+"${ssh_args[@]}"} "$REMOTE" "$*"
}

rig_push() {
  [ $# -eq 2 ] || rig_die "usage: rig push <from> <to>"
  rsync -avzP --stats ${rsync_args[@]+"${rsync_args[@]}"} \
    --exclude=.git --exclude=node_modules -- "$1" "$REMOTE:$2"
}

rig_pull() {
  [ $# -eq 2 ] || rig_die "usage: rig pull <from> <to>"
  # rsync already resolves a relative destination against the working
  # directory; the old "$PWD/$2" turned an absolute one into $PWD//abs/path.
  rsync -avzP --stats ${rsync_args[@]+"${rsync_args[@]}"} \
    --exclude=.git --exclude=node_modules -- "$REMOTE:$1" "$2"
}

rig_scp() {
  [ $# -eq 2 ] || rig_die "usage: rig scp <from> <to>"
  # The destination is used verbatim. A previous version did DEST="${2:1}",
  # silently dropping its first character.
  scp ${ssh_args[@]+"${ssh_args[@]}"} -- "$1" "$REMOTE:$2"
}

rig_copy_id() {
  local identity=""
  [ $# -le 1 ] || rig_die "usage: rig copy-id [<identity>]"

  if [ $# -eq 1 ]; then
    identity=$(rig_expand_tilde "$1")
    [ -e "$identity" ] || rig_die "no such identity file: $identity"
  elif [ -n "$REMOTE_KEY" ]; then
    # ssh-copy-id accepts either half of the pair and appends .pub itself.
    identity=$REMOTE_KEY
  fi

  command -v ssh-copy-id >/dev/null 2>&1 ||
    rig_die "ssh-copy-id not found; install the OpenSSH client tools"

  # The connection arguments are deliberately not threaded through here: the
  # whole point is that the key is not on the remote yet, so forcing it as
  # the connection identity would rule out the password auth this needs.
  if [ -n "$identity" ]; then
    echo "rig: installing $identity on $REMOTE" >&2
    ssh-copy-id -i "$identity" "$REMOTE"
  else
    echo "rig: installing your default ssh identity on $REMOTE" >&2
    ssh-copy-id "$REMOTE"
  fi
}

rig_tunnel() {
  [ $# -eq 1 ] || rig_die "usage: rig tunnel <port>"
  case $1 in
  '' | *[!0-9]*) rig_die "port must be a number, got '$1'" ;;
  esac
  ssh ${ssh_args[@]+"${ssh_args[@]}"} -N -L "$1:localhost:$1" "$REMOTE"
}

# CLI HANDLERS
command_name=${1:-}
[ $# -eq 0 ] || shift

case $command_name in
'help' | '-h' | '--help')
  # Soft resolution: a config naming a default that no longer exists should
  # not stop rig from printing its own help.
  RIG_STRICT=0 rig_resolve_remote || true
  rig_usage
  exit 0
  ;;

'version' | '--version' | '-v')
  rig_version
  exit 0
  ;;

'remotes' | 'remote')
  rig_resolve_remote || true
  # shellcheck source=src/remotes.sh
  source "$RIG_SRC/remotes.sh"
  exit 0
  ;;

'')
  RIG_STRICT=0 rig_resolve_remote || true
  rig_usage >&2
  exit 1
  ;;

# Commands that need a host. Validated here so that an unknown command is
# reported as such, rather than as a missing remote.
'ssh' | 'run' | 'apt' | 'push' | 'pull' | 'scp' | 'copy-id' | 'install' | 'tunnel') ;;

*)
  echo "rig: unknown command '$command_name'" >&2
  RIG_STRICT=0 rig_resolve_remote || true
  rig_usage >&2
  exit 1
  ;;
esac

rig_resolve_remote
rig_require_remote
rig_connection_args

case $command_name in
'ssh')
  echo "$REMOTE" >&2
  # SC2029: $REMOTE is the host, not a remote command -- nothing is executed.
  # shellcheck disable=SC2029
  ssh ${ssh_args[@]+"${ssh_args[@]}"} "$REMOTE"
  ;;

'run')
  [ $# -gt 0 ] || rig_die "usage: rig run <cmd>"
  echo "$REMOTE ($*)" >&2
  rig_run "$@"
  ;;

'apt')
  [ $# -gt 0 ] || rig_die "usage: rig apt <args>"
  rig_run "sudo DEBIAN_FRONTEND=noninteractive apt-get -y $*"
  ;;

'push')
  rig_push "$@"
  ;;

'pull')
  rig_pull "$@"
  ;;

'scp')
  rig_scp "$@"
  ;;

'copy-id')
  rig_copy_id "$@"
  ;;

'install')
  # shellcheck source=src/install.sh
  source "$RIG_SRC/install.sh"
  ;;

'tunnel')
  rig_tunnel "$@"
  ;;
esac
