#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CODE_DIR="${HOME}/code"
mkdir -p "$CODE_DIR"
cd "$CODE_DIR"

if [[ ! -d dotfiles ]]; then
  git clone https://github.com/kadencartwright/dotfiles
fi

if [[ ! -d dotman ]]; then
  git clone https://github.com/kadencartwright/dotman
fi

cd dotman
make

cd "${CODE_DIR}/dotfiles"
"${CODE_DIR}/dotman/bin/dotman" link -f ./dotman.toml
