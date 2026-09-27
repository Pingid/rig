#!/usr/bin/env bash
set -euo pipefail

source ./vars.sh

nix_installed=$(which nix) || -d "/nix"
if [[ -z "$nix_installed" ]]; then
    echo "Nix not installed"
    exit 1
fi

echo "Nix installed"


if [[ ! -f "${NIX_CONFIG_FILE}" ]]; then
    ./config.sh
fi

nix run home-manager/master -- switch --flake "${NIX_CONFIG_DIR}/flake.nix"