#!/usr/bin/env bash
#
# `rig install` subcommands. Sourced by bin.sh with the positional parameters
# already shifted past "install", so rig_run and rig_die are in scope.

install_node() {
  local version=${1:-}
  case $version in
  '') rig_die "usage: rig install node <major-version>" ;;
  *[!0-9]*) rig_die "node version must be a number, got '$version'" ;;
  esac
  # apt-get needs -y here: without it the install prompts, and there is no tty
  # on the other end of the ssh connection to answer it.
  rig_run "curl -fsSL https://deb.nodesource.com/setup_${version}.x -o /tmp/nodesource_setup.sh \
    && sudo bash /tmp/nodesource_setup.sh \
    && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs \
    && rm -f /tmp/nodesource_setup.sh \
    && node -v"
}

install_docker() {
  # Installs the Compose v2 plugin (`docker compose`) as a side effect.
  #
  # SC2016: single quotes are deliberate -- $tmp and $rc must be expanded by
  # the remote shell, not this one.
  # shellcheck disable=SC2016
  rig_run 'tmp=$(mktemp) \
    && curl -fsSL https://get.docker.com -o "$tmp" \
    && sudo sh "$tmp"; \
    rc=$?; rm -f "$tmp"; exit $rc'
}

install_tailscale() {
  rig_run 'curl -fsSL https://tailscale.com/install.sh | sh'
}

install_usage() {
  cat <<-END
rig install

  commands
    node <version>   install nodejs at the given major version
    docker           install the latest docker, including 'docker compose'
    tailscale        install the latest tailscale
END
}

install_command=${1:-}
[ $# -eq 0 ] || shift

case $install_command in
'node')
  install_node "$@"
  exit 0
  ;;

'docker')
  install_docker
  exit 0
  ;;

'tailscale')
  install_tailscale
  exit 0
  ;;

'help' | '-h' | '--help')
  install_usage
  exit 0
  ;;

'docker_compose' | 'docker-compose')
  rig_die "docker_compose was removed; 'rig install docker' provides 'docker compose'"
  ;;

*)
  if [ -n "$install_command" ]; then
    echo "rig: unknown install target '$install_command'" >&2
  fi
  install_usage >&2
  exit 1
  ;;
esac
