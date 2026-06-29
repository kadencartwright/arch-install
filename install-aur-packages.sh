#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

AUR_FILE="${HOME}/aur.txt"

if [[ ! -f "$AUR_FILE" ]]; then
    printf '[install-aur] error: missing package list: %s\n' "$AUR_FILE" >&2
    exit 1
fi

mapfile -t aur_packages < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$AUR_FILE")

if [[ ${#aur_packages[@]} -eq 0 ]]; then
    printf '[install-aur] no packages listed in %s\n' "$AUR_FILE"
    exit 0
fi

yay -S --noconfirm --needed "${aur_packages[@]}"
