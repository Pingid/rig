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

rig_config_load_all

# Connection arguments, built once. REMOTE_KEY is optional, so every
# expansion is guarded for bash 3.2's empty-array handling under `set -u`.
ssh_args=()
rsync_args=()
if [ -n "$REMOTE_KEY" ]; then
  ssh_args=(-i "$REMOTE_KEY")
  # rsync's -i is --itemize-changes, not an identity file: the key has to go
  # through -e instead, or rsync treats it as another source path.
  rsync_args=(-e "ssh -i $(printf '%q' "$REMOTE_KEY")")
fi

rig_version() {
  if [ -f "$RIG_ROOT/VERSION" ]; then
    cat "$RIG_ROOT/VERSION"
  else
    echo "unknown"
  fi
}

rig_usage() {
  cat <<-END
rig

  REMOTE=${REMOTE:-<not set>}

  commands
    ssh                  ssh into the remote
    run <cmd>            run a command on the remote
    apt <args>           run apt on the remote
    push <from> <to>     rsync files to the remote
    pull <from> <to>     rsync files from the remote
    scp <from> <to>      copy a file to the remote
    install <target>     install a program on the remote
    tunnel <port>        forward a local port to the remote
    version              print the rig version
    help                 show this message
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
  rig_usage
  exit 0
  ;;

'version' | '--version' | '-v')
  rig_version
  exit 0
  ;;

'')
  rig_usage >&2
  exit 1
  ;;

# Commands that need a host. Validated here so that an unknown command is
# reported as such, rather than as a missing remote.
'ssh' | 'run' | 'apt' | 'push' | 'pull' | 'scp' | 'install' | 'tunnel') ;;

*)
  echo "rig: unknown command '$command_name'" >&2
  rig_usage >&2
  exit 1
  ;;
esac

rig_require_remote

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

'install')
  # shellcheck source=src/install.sh
  source "$RIG_SRC/install.sh"
  ;;

'tunnel')
  rig_tunnel "$@"
  ;;
esac
