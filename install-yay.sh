#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v makepkg >/dev/null 2>&1 || { echo "makepkg is required" >&2; exit 1; }

tmpdir="$(mktemp -d /tmp/yay-build.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cd "$tmpdir"
curl -fsSL -o PKGBUILD 'https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=yay'
makepkg --syncdeps --install --noconfirm --needed
