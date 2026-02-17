#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

AUR_FILE="${HOME}/aur.txt"

if [[ ! -f "$AUR_FILE" ]]; then
    printf '[install-aur] error: missing package list: %s\n' "$AUR_FILE" >&2
    exit 1
fi

yay -S --noconfirm --needed - < "$AUR_FILE"
