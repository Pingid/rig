#!/usr/bin/env bash
# Runs on the target machine. Safe to re-run: installs Nix if missing, writes
# ~/.config/rig/config.nix on first run, then applies the home-manager config.
#
# Detected values can be overridden with env vars:
#   RIG_SYSTEM, RIG_HOSTNAME, RIG_USERNAME, RIG_HOME
# Set RIG_RECONFIGURE=1 to regenerate config.nix.
# Set RIG_SET_SHELL=0 to keep the current login shell instead of switching to fish.
# Set RIG_SWAP_MB=0 to skip creating swap on low-memory machines (default 2048).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="rig"
CONFIG_DIR="${HOME}/.config/${NAME}"
CONFIG_FILE="${CONFIG_DIR}/config.nix"

log() { echo "==> $*"; }

sudo_cmd() {
    if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

load_nix() {
    # Non-interactive ssh shells don't source the Nix profile, so do it here
    local profile
    for profile in \
        /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
        "${HOME}/.nix-profile/etc/profile.d/nix.sh"; do
        if [[ -f "${profile}" ]]; then
            set +u
            # shellcheck disable=SC1090
            source "${profile}"
            set -u
            return
        fi
    done
}

ensure_swap() {
    # Evaluating nixpkgs needs ~1-2GB of RAM, so small VPSes get OOM-killed without swap
    [[ -r /proc/meminfo ]] || return 0
    local mem_kb swap_kb size_mb="${RIG_SWAP_MB:-2048}"
    mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    swap_kb="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
    if [[ "${size_mb}" -eq 0 || "${swap_kb}" -gt 0 || "${mem_kb}" -ge 2097152 ]]; then
        return 0
    fi

    log "Only $((mem_kb / 1024))MB RAM and no swap, creating ${size_mb}MB /swapfile"
    if [[ ! -f /swapfile ]]; then
        sudo_cmd fallocate -l "${size_mb}M" /swapfile \
            || sudo_cmd dd if=/dev/zero of=/swapfile bs=1M count="${size_mb}" status=none
        sudo_cmd chmod 600 /swapfile
        sudo_cmd mkswap /swapfile > /dev/null
    fi
    sudo_cmd swapon /swapfile
    if ! grep -qs '^/swapfile ' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo_cmd tee -a /etc/fstab > /dev/null
    fi
}

set_login_shell() {
    [[ "${RIG_SET_SHELL:-1}" == "1" ]] || return 0
    local fish="${HOME}/.nix-profile/bin/fish" user
    user="$(id -un)"

    # Only switch if fish actually runs, otherwise a broken profile would lock us out of ssh
    if ! "${fish}" -c true > /dev/null 2>&1; then
        log "fish not working at ${fish}, leaving login shell unchanged"
        return 0
    fi
    if ! grep -qxF "${fish}" /etc/shells; then
        log "Adding ${fish} to /etc/shells"
        echo "${fish}" | sudo_cmd tee -a /etc/shells > /dev/null
    fi
    if [[ "$(getent passwd "${user}" | cut -d: -f7)" != "${fish}" ]]; then
        log "Setting login shell for ${user} to fish"
        sudo_cmd chsh -s "${fish}" "${user}"
    fi
}

install_nix() {
    load_nix
    if command -v nix > /dev/null 2>&1; then
        log "Nix already installed ($(nix --version))"
        return
    fi

    log "Installing Nix (multi-user)"
    if ! command -v curl > /dev/null 2>&1 || ! command -v xz > /dev/null 2>&1; then
        if command -v apt-get > /dev/null 2>&1; then
            sudo_cmd apt-get update -qq
            sudo_cmd apt-get install -y -qq curl xz-utils
        elif command -v dnf > /dev/null 2>&1; then
            sudo_cmd dnf install -y curl xz
        fi
    fi
    curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon --yes
    load_nix
}

enable_flakes() {
    local conf="${HOME}/.config/nix/nix.conf"
    if ! grep -qs "flakes" "${conf}"; then
        log "Enabling flakes in ${conf}"
        mkdir -p "$(dirname "${conf}")"
        echo "extra-experimental-features = nix-command flakes" >> "${conf}"
    fi
}

migrate_old_name() {
    # Carry config.nix and flake.lock over from when this was called "boxer"
    local old="${HOME}/.config/boxer"
    if [[ -d "${old}" && ! -e "${CONFIG_DIR}" ]]; then
        log "Moving ${old} to ${CONFIG_DIR}"
        mv "${old}" "${CONFIG_DIR}"
    fi
}

write_config() {
    if [[ -f "${CONFIG_FILE}" && "${RIG_RECONFIGURE:-0}" != "1" ]]; then
        log "Using existing ${CONFIG_FILE}"
        return
    fi

    local arch os
    case "$(uname -m)" in
        arm64 | aarch64) arch="aarch64" ;;
        x86_64 | amd64) arch="x86_64" ;;
        *) arch="$(uname -m)" ;;
    esac
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    local system_type="${RIG_SYSTEM:-${arch}-${os}}"
    local host_name="${RIG_HOSTNAME:-$(hostname -s 2> /dev/null || hostname)}"
    local user_name="${RIG_USERNAME:-$(id -un)}"
    local home_dir="${RIG_HOME:-${HOME}}"

    log "Writing ${CONFIG_FILE}"
    echo "    system: ${system_type}"
    echo "    host:   ${host_name}"
    echo "    user:   ${user_name}"
    echo "    home:   ${home_dir}"

    mkdir -p "${CONFIG_DIR}"
    cat > "${CONFIG_FILE}" << EOF
{
  systemType    = "${system_type}";
  hostname      = "${host_name}";
  username      = "${user_name}";
  homeDirectory = "${home_dir}";
}
EOF
}

ensure_swap
install_nix
enable_flakes
migrate_old_name
write_config

# Always refresh these so local edits are picked up on re-run
find "${CONFIG_DIR}" -maxdepth 1 -type f -name "*.nix" ! -name "config.nix" -delete
cp "${SCRIPT_DIR}"/*.nix "${SCRIPT_DIR}/justfile" "${CONFIG_DIR}/"

log "Applying home-manager configuration"
username="$(sed -n 's/^ *username *= *"\(.*\)";/\1/p' "${CONFIG_FILE}")"
nix run "${CONFIG_DIR}" -- \
    switch -b backup --flake "${CONFIG_DIR}#${username}"

set_login_shell

log "Done. Log out and back in (or run 'exec \$SHELL -l') to pick up the new environment."
