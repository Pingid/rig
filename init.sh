#!/usr/bin/env bash
# Bootstrap a remote server: copies ./remote to it and runs remote/init.sh there.
#
#   ./init.sh root@134.209.221.173
#   ./init.sh myhost -p 2222        # extra args are passed to ssh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE="/tmp/rig"

REMOTE="${1:-}"
if [[ -z "${REMOTE}" ]]; then
    read -r -p "Enter remote eg root@134.209.221.173: " REMOTE
fi
shift || true
SSH_ARGS=("$@")

echo "==> Copying setup files to ${REMOTE}:${STAGE}"
# Keep macOS metadata (._ files, xattrs like com.apple.provenance) out of the archive
COPYFILE_DISABLE=1 tar --no-xattrs --exclude pkg.example.nix -C "${SCRIPT_DIR}/remote" -czf - . \
    | ssh ${SSH_ARGS[@]+"${SSH_ARGS[@]}"} "${REMOTE}" "rm -rf ${STAGE} && mkdir -p ${STAGE} && tar -xzf - -C ${STAGE}"

echo "==> Running setup on ${REMOTE}"
ssh -t ${SSH_ARGS[@]+"${SSH_ARGS[@]}"} "${REMOTE}" "bash ${STAGE}/init.sh"
