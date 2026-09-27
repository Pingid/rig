#!/usr/bin/env bash
set -euo pipefail

source ./vars.sh

# Determine system type
arch="$(uname -m)"     
case "$arch" in
  arm64)   nix_arch="aarch64" ;;
  x86_64)  nix_arch="x86_64" ;;
  *)       nix_arch="$arch" ;;
esac

# Determine system type
os="$(uname -s | tr '[:upper:]' '[:lower:]')" # darwin, linux, etc
system_type="${nix_arch}-${os}"

# Determin hostname
if [[ -n "$HOSTNAME" ]]; then
  # remove any domain suffix (e.g. “.local”)
  hostname="${HOSTNAME%%.*}"
else
  hostname="$(scutil --get ComputerName 2>/dev/null || hostname)"
fi

username="$USER"
home_directory="$HOME"

echo_info() {
    echo ""
    echo "--------------------------------"
    echo "Found system information:"
    echo "--------------------------------"
    echo "    arch: $arch"
    echo "    system: $system_type"
    echo "    host: $hostname"
    echo "    user: $username"
    echo "    home: $home_directory"
    echo ""

    # Confirm
    echo "Is this correct? (y/n) "
    read -p "" confirm

    if [[ "$confirm" != "y" ]]; then

    echo "Architecture [${arch}]: "
    read -p "" arch
    arch="${arch:-$arch}"

    echo "System Type [${system_type}]: "
    read -p "" updated_system_type
    system_type="${updated_system_type:-$system_type}"

    echo "Hostname [${hostname}]: "
    read -p "" updated_hostname
    hostname="${updated_hostname:-$hostname}"

    echo "User [${username}]: "
    read -p "" updated_username
    username="${updated_username:-$username}"

    echo "Home Directory [${home_directory}]: "
    read -p "" updated_home_directory
    home_directory="${updated_home_directory:-$home_directory}"

    echo_info
    fi
}

echo_info

echo "Creating config file in ~/.config/${NAME}/config.nix"
mkdir -p "${NIX_CONFIG_DIR}"
touch "${NIX_CONFIG_FILE}"
cat > "${NIX_CONFIG_FILE}" <<EOF
{
  systemType     = "${system_type}";
  hostname       = "${hostname}";
  username       = "${username}";
  homeDirectory  = "${home_directory}";
}
EOF

cp ./*.nix "${NIX_CONFIG_DIR}"