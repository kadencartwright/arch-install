#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VM_NAME="arch-install-test"
LIBVIRT_CONNECT="qemu:///system"
ISO_PATH="${HOME}/Downloads/archlinux-2026.02.01-x86_64.iso"
DISK_PATH="${REPO_ROOT}/.vm/${VM_NAME}.qcow2"
DISK_SIZE_GB="120"
MEMORY_MB="8192"
VCPUS="4"
REPO_SHARE_PATH="${REPO_ROOT}"
NETWORK_ARG=""

usage() {
    cat <<'USAGE'
Usage: scripts/vm-libvirt-create.sh [options]

Options:
  --name <name>         VM name (default: arch-install-test)
  --connect <uri>       Libvirt connection URI (default: qemu:///system)
  --iso <path>          Arch ISO path (default: ~/Downloads/archlinux-2026.02.01-x86_64.iso)
  --disk <path>         qcow2 disk path (default: ./.vm/<name>.qcow2)
  --disk-size <gb>      Disk size in GiB for new disk (default: 120)
  --memory <mb>         VM memory in MiB (default: 8192)
  --cpus <count>        Number of vCPUs (default: 4)
  --repo <path>         Host repo path to share as virtiofs tag 'hostrepo'
  --network <arg>       virt-install --network argument override
  --help                Show this help text
USAGE
}

log() {
    printf '[vm-create] %s\n' "$*"
}

fatal() {
    printf '[vm-create] error: %s\n' "$*" >&2
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
        --iso)
            ISO_PATH="${2:-}"
            shift 2
            ;;
        --disk)
            DISK_PATH="${2:-}"
            shift 2
            ;;
        --disk-size)
            DISK_SIZE_GB="${2:-}"
            shift 2
            ;;
        --memory)
            MEMORY_MB="${2:-}"
            shift 2
            ;;
        --cpus)
            VCPUS="${2:-}"
            shift 2
            ;;
        --repo)
            REPO_SHARE_PATH="${2:-}"
            shift 2
            ;;
        --network)
            NETWORK_ARG="${2:-}"
            shift 2
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
[[ -n "$ISO_PATH" ]] || fatal "ISO path cannot be empty"
[[ -n "$DISK_PATH" ]] || fatal "Disk path cannot be empty"
[[ -n "$DISK_SIZE_GB" ]] || fatal "Disk size cannot be empty"
[[ -n "$MEMORY_MB" ]] || fatal "Memory cannot be empty"
[[ -n "$VCPUS" ]] || fatal "vCPU count cannot be empty"
[[ -n "$REPO_SHARE_PATH" ]] || fatal "Repo path cannot be empty"
if [[ -z "$NETWORK_ARG" ]]; then
    if [[ "$LIBVIRT_CONNECT" == "qemu:///session" ]]; then
        NETWORK_ARG="user,model=virtio"
    else
        NETWORK_ARG="network=default,model=virtio"
    fi
fi

require_cmd virsh
require_cmd virt-install
require_cmd qemu-img
require_cmd systemctl

command -v swtpm >/dev/null 2>&1 || fatal "swtpm is required for TPM emulation"

[[ -f "$ISO_PATH" ]] || fatal "ISO not found: $ISO_PATH"
[[ -d "$REPO_SHARE_PATH" ]] || fatal "Repo path not found: $REPO_SHARE_PATH"

if [[ "$LIBVIRT_CONNECT" == "qemu:///system" ]] && ! systemctl is-active --quiet libvirtd; then
    fatal "libvirtd is not active; start it with: sudo systemctl start libvirtd"
fi

if virsh --connect "$LIBVIRT_CONNECT" dominfo "$VM_NAME" >/dev/null 2>&1; then
    fatal "VM already exists in libvirt: $VM_NAME"
fi

mkdir -p "$(dirname "$DISK_PATH")"
if [[ ! -f "$DISK_PATH" ]]; then
    log "Creating disk: $DISK_PATH (${DISK_SIZE_GB}G)"
    qemu-img create -f qcow2 "$DISK_PATH" "${DISK_SIZE_GB}G" >/dev/null
fi

log "Defining and starting VM: $VM_NAME"
virt-install \
    --connect "$LIBVIRT_CONNECT" \
    --name "$VM_NAME" \
    --memory "$MEMORY_MB" \
    --memorybacking access.mode=shared \
    --vcpus "$VCPUS" \
    --machine q35 \
    --cpu host-passthrough \
    --boot uefi \
    --disk "path=${DISK_PATH},format=qcow2,bus=virtio" \
    --cdrom "$ISO_PATH" \
    --controller type=scsi,model=virtio-scsi \
    --network "$NETWORK_ARG" \
    --graphics spice \
    --video qxl \
    --channel spicevmc,target.type=virtio,name=com.redhat.spice.0 \
    --rng /dev/urandom \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
    --filesystem "source=${REPO_SHARE_PATH},target=hostrepo,driver.type=virtiofs" \
    --noautoconsole

log "VM is running. Open it with virt-manager and connect via SPICE."
log "Inside the guest, mount the shared repo with: mount -t virtiofs hostrepo /root/host-repo"
