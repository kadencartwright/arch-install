#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
umask 077

log() {
    printf '[install-yay] %s\n' "$*"
}

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ -z "${YAY_REF:-}" ]]; then
    log "warning: installing unpinned yay HEAD from AUR (set YAY_REF to pin a ref)"
fi

git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"

if [[ -n "${YAY_REF:-}" ]]; then
    git -C "$TMP_DIR/yay" checkout "$YAY_REF"
fi

(
    cd "$TMP_DIR/yay"
    makepkg -si --noconfirm --needed
)
