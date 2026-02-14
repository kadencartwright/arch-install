#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/postinstall-check.sh --target user@host [options]

Options:
  --target USER@HOST   SSH target to validate (required)
  --username NAME      Expected primary user (default: k)
  --hostname NAME      Expected hostname (optional)
  --help               Show help
USAGE
}

log() {
  printf '[postcheck] %s\n' "$*"
}

die() {
  printf '[postcheck] ERROR: %s\n' "$*" >&2
  exit 1
}

TARGET=""
USERNAME="k"
HOSTNAME_EXPECTED=""

while (($# > 0)); do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --username)
      USERNAME="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME_EXPECTED="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$TARGET" ]] || die "--target is required"

remote() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$TARGET" "$@"
}

log "Checking host connectivity"
remote true

log "Checking host identity"
if [[ -n "$HOSTNAME_EXPECTED" ]]; then
  actual_hostname="$(remote hostnamectl --static)"
  [[ "$actual_hostname" == "$HOSTNAME_EXPECTED" ]] || die "Hostname mismatch: expected '$HOSTNAME_EXPECTED', got '$actual_hostname'"
fi

log "Checking encrypted LVM layout"
remote 'lsblk -f | grep -q cryptlvm'
remote 'lvs vg1/root >/dev/null'
remote 'lvs vg1/home >/dev/null'

log "Checking bootloader and networking"
remote 'bootctl status >/dev/null'
remote 'systemctl is-enabled NetworkManager | grep -q enabled'

log "Checking user and shell"
remote "id ${USERNAME} >/dev/null"
remote "getent passwd ${USERNAME} | grep -q /run/current-system/sw/bin/zsh"

log "Checking key desktop packages"
remote 'command -v Hyprland >/dev/null'
remote 'command -v waybar >/dev/null'
remote 'command -v pavucontrol >/dev/null'

log "Checking dotfiles bootstrap status"
remote "test -f /home/${USERNAME}/.local/state/dotfiles_bootstrapped"

log "Post-install checks passed"
