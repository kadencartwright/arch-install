#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VM_NAME="arch-install-test"
LIBVIRT_CONNECT="qemu:///system"
DISK_PATH="${REPO_ROOT}/.vm/${VM_NAME}.qcow2"
PURGE_NVRAM=0

usage() {
    cat <<'USAGE'
Usage: scripts/vm-libvirt-clean.sh [options]

Options:
  --name <name>        VM name (default: arch-install-test)
  --connect <uri>      Libvirt connection URI (default: qemu:///system)
  --disk <path>        qcow2 disk path to remove (default: ./.vm/<name>.qcow2)
  --purge-nvram        Remove VM NVRAM vars file during undefine
  --help               Show this help text
USAGE
}

log() {
    printf '[vm-clean] %s\n' "$*"
}

fatal() {
    printf '[vm-clean] error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fatal "Required command not found: $cmd"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            VM_NAME="${2:-}"
            shift 2
            ;;
        --connect)
            LIBVIRT_CONNECT="${2:-}"
            shift 2
            ;;
        --disk)
            DISK_PATH="${2:-}"
            shift 2
            ;;
        --purge-nvram)
            PURGE_NVRAM=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            fatal "Unknown option: $1"
            ;;
    esac
done

[[ -n "$VM_NAME" ]] || fatal "VM name cannot be empty"
[[ -n "$LIBVIRT_CONNECT" ]] || fatal "Libvirt connection URI cannot be empty"
[[ -n "$DISK_PATH" ]] || fatal "Disk path cannot be empty"

require_cmd virsh

if virsh --connect "$LIBVIRT_CONNECT" dominfo "$VM_NAME" >/dev/null 2>&1; then
    state="$(virsh --connect "$LIBVIRT_CONNECT" domstate "$VM_NAME" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$state" != "shutoff" ]]; then
        log "Stopping VM: $VM_NAME"
        virsh --connect "$LIBVIRT_CONNECT" destroy "$VM_NAME" >/dev/null
    fi

    log "Undefining VM: $VM_NAME"
    if (( PURGE_NVRAM )); then
        virsh --connect "$LIBVIRT_CONNECT" undefine "$VM_NAME" --nvram >/dev/null
    else
        virsh --connect "$LIBVIRT_CONNECT" undefine "$VM_NAME" >/dev/null
    fi
else
    log "VM not defined, skipping undefine: $VM_NAME"
fi

if [[ -f "$DISK_PATH" ]]; then
    log "Removing disk: $DISK_PATH"
    rm -f "$DISK_PATH"
else
    log "Disk not found, skipping: $DISK_PATH"
fi

log "Cleanup complete"
