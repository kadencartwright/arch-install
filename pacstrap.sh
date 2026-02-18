#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

log() {
    printf '[pacstrap] %s\n' "$*"
}

attempt=1
max_attempts=3

while (( attempt <= max_attempts )); do
    if ( umask 022; pacstrap -K /mnt base linux base-devel linux-firmware lvm2 neovim git networkmanager amd-ucode intel-ucode man-db man-pages dracut bluez bluez-utils rpcbind go ); then
        log "Pacstrap completed"
        exit 0
    fi

    if (( attempt == max_attempts )); then
        break
    fi

    log "Pacstrap failed (attempt ${attempt}/${max_attempts}), retrying in 5 seconds"
    sleep 5
    attempt=$((attempt + 1))
done

printf '[pacstrap] error: pacstrap failed after %d attempts\n' "$max_attempts" >&2
exit 1
