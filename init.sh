#!/usr/bin/env bash
set -euo pipefail

# Capture first argument
REMOTE="${1}"

if [[ -z "${REMOTE}" ]]; then
    read -r -p "Enter remote eg root@134.209.221.173: " REMOTE
fi

scp -r ./remote ${REMOTE}:/tmp/remote > /dev/null 2>&1
ssh ${REMOTE} "chmod +x /tmp/remote/*.sh && /tmp/remote/init.sh"
