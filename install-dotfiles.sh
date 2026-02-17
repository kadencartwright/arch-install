#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

log() {
    printf '[dotfiles] %s\n' "$*"
}

CODE_DIR="${HOME}/code"
DOTFILES_DIR="${CODE_DIR}/dotfiles"
DOTMAN_DIR="${CODE_DIR}/dotman"

mkdir -p "$CODE_DIR"

if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    git clone https://github.com/kadencartwright/dotfiles "$DOTFILES_DIR"
fi

if [[ ! -d "$DOTMAN_DIR/.git" ]]; then
    git clone https://github.com/kadencartwright/dotman "$DOTMAN_DIR"
fi

if [[ -n "${DOTFILES_REF:-}" ]]; then
    git -C "$DOTFILES_DIR" checkout "$DOTFILES_REF"
else
    log "warning: dotfiles repo is unpinned (set DOTFILES_REF to pin)"
fi

if [[ -n "${DOTMAN_REF:-}" ]]; then
    git -C "$DOTMAN_DIR" checkout "$DOTMAN_REF"
else
    log "warning: dotman repo is unpinned (set DOTMAN_REF to pin)"
fi

make -C "$DOTMAN_DIR"
"$DOTMAN_DIR/bin/dotman" link -c "$DOTFILES_DIR/dotman.toml"
