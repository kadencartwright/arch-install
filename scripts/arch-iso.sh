#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/arch-iso.sh <command> [options]

Commands:
  download   Download official Arch ISO from trusted mirrors and verify
  build      Build an ISO locally using mkarchiso

Download options:
  --version YYYY.MM.DD   ISO version (default: latest)
  --outdir PATH          Output directory (default: ./iso)
  --base-url URL         Mirror base URL (default: https://geo.mirror.pkgbuild.com/iso)
  --skip-gpg             Skip GPG signature verification (not recommended)

Build options:
  --profile PATH         Archiso profile path (default: /usr/share/archiso/configs/releng)
  --workdir PATH         Working directory (default: ./archiso-work)
  --outdir PATH          Output directory (default: ./iso)

Examples:
  ./scripts/arch-iso.sh download
  ./scripts/arch-iso.sh download --version 2026.02.01 --outdir ./iso
  ./scripts/arch-iso.sh build
  ./scripts/arch-iso.sh build --profile ./my-archiso-profile --outdir ./iso
USAGE
}

log() {
  printf '[arch-iso] %s\n' "$*"
}

die() {
  printf '[arch-iso] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

download_with_retry() {
  local url="$1"
  local dest="$2"
  curl --fail --location --retry 3 --retry-delay 2 --show-error --silent "$url" -o "$dest"
}

download_iso() {
  local version="latest"
  local outdir="./iso"
  local base_url="https://geo.mirror.pkgbuild.com/iso"
  local skip_gpg=0

  while (($# > 0)); do
    case "$1" in
      --version)
        version="${2:-}"
        shift 2
        ;;
      --outdir)
        outdir="${2:-}"
        shift 2
        ;;
      --base-url)
        base_url="${2:-}"
        shift 2
        ;;
      --skip-gpg)
        skip_gpg=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown download option: $1"
        ;;
    esac
  done

  require_cmd curl
  require_cmd sha256sum
  require_cmd awk
  require_cmd grep

  mkdir -p "$outdir"

  local release_path
  if [[ "$version" == "latest" ]]; then
    release_path="latest"
  else
    release_path="$version"
  fi

  local release_url="${base_url%/}/${release_path}"
  local sums_file="${outdir}/sha256sums.txt"

  log "Fetching checksums from ${release_url}/sha256sums.txt"
  download_with_retry "${release_url}/sha256sums.txt" "$sums_file"

  local iso_name
  iso_name="$(awk '/archlinux-.*-x86_64\.iso$/ {print $2; exit}' "$sums_file")"
  [[ -n "$iso_name" ]] || die "Could not determine ISO filename from sha256sums.txt"

  local iso_path="${outdir}/${iso_name}"
  local sig_path="${iso_path}.sig"

  log "Downloading ${iso_name}"
  download_with_retry "${release_url}/${iso_name}" "$iso_path"

  log "Downloading signature ${iso_name}.sig"
  download_with_retry "${release_url}/${iso_name}.sig" "$sig_path"

  log "Verifying SHA256 checksum"
  (
    cd "$outdir"
    grep " ${iso_name}$" sha256sums.txt | sha256sum -c -
  )

  if [[ "$skip_gpg" -eq 0 ]]; then
    require_cmd gpg
    if ! gpg --list-keys >/dev/null 2>&1; then
      log "Initializing local GPG keyring"
      gpg --list-keys >/dev/null 2>&1 || true
    fi

    log "Verifying GPG signature (requires Arch release signing key in your keyring)"
    if ! gpg --verify "$sig_path" "$iso_path"; then
      cat >&2 <<'MSG'
[arch-iso] GPG verification failed.
Import Arch Linux release signing keys and re-run, for example:
  gpg --auto-key-locate clear,wkd,nodefault --locate-keys pierre@archlinux.org
Then run the download command again.
MSG
      exit 1
    fi
  else
    log "Skipping GPG verification by request"
  fi

  log "Download and verification complete: ${iso_path}"
}

build_iso() {
  local profile="/usr/share/archiso/configs/releng"
  local workdir="./archiso-work"
  local outdir="./iso"

  while (($# > 0)); do
    case "$1" in
      --profile)
        profile="${2:-}"
        shift 2
        ;;
      --workdir)
        workdir="${2:-}"
        shift 2
        ;;
      --outdir)
        outdir="${2:-}"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown build option: $1"
        ;;
    esac
  done

  require_cmd mkarchiso
  [[ -d "$profile" ]] || die "Profile not found: $profile"

  mkdir -p "$workdir" "$outdir"

  log "Building Arch ISO with profile: $profile"
  log "Workdir: $workdir"
  log "Outdir: $outdir"

  mkarchiso -v -w "$workdir" -o "$outdir" "$profile"

  log "ISO build complete. Output files are in: $outdir"
}

main() {
  local command="${1:-}"
  case "$command" in
    download)
      shift
      download_iso "$@"
      ;;
    build)
      shift
      build_iso "$@"
      ;;
    --help|-h|help|"")
      usage
      ;;
    *)
      die "Unknown command: $command"
      ;;
  esac
}

main "$@"
