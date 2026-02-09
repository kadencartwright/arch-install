#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

AUR_LIST="${HOME}/aur.txt"
[[ -f "$AUR_LIST" ]] || { echo "Missing package list: $AUR_LIST" >&2; exit 1; }
command -v yay >/dev/null 2>&1 || { echo "yay is not installed" >&2; exit 1; }

yay -S --noconfirm - < "$AUR_LIST"
