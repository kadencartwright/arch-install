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
RECREATE=0

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
  --network <arg>       virt-install --network argument override (default: bridge=br0,model=virtio)
  --recreate            Destroy/undefine existing VM with the same name before create
  --help                Show this help text
USAGE
}

log() {
    printf '[vm-create] %s\n' "$*"
}

warn() {
    printf '[vm-create] warning: %s\n' "$*" >&2
}

fatal() {
    printf '[vm-create] error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fatal "Required command not found: $cmd"
}

extract_bridge_name() {
    local net_arg="$1"
    local bridge_name

    bridge_name="$(awk -F'[=,]' '{for (i=1;i<=NF;i++) if ($i=="bridge") {print $(i+1); exit}}' <<<"$net_arg")"
    printf '%s' "$bridge_name"
}

ensure_bridge_exists() {
    local bridge_name="$1"
    local uplink_iface=""
    local uplink_type=""
    local slave_conn=""
    local bridge_state=""

    [[ -n "$bridge_name" ]] || return 0

    if ip link show "$bridge_name" >/dev/null 2>&1; then
        return 0
    fi

    require_cmd sudo

    log "Bridge ${bridge_name} not found; attempting to create it"

    if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; then
        if ! sudo nmcli -t -f NAME connection show | grep -Fxq "$bridge_name"; then
            sudo nmcli connection add type bridge ifname "$bridge_name" con-name "$bridge_name" autoconnect yes >/dev/null
        fi

        uplink_iface="$(ip route show default 2>/dev/null | awk '$5 !~ /^virbr/ {print $5; exit}')"
        if [[ -z "$uplink_iface" ]]; then
            uplink_iface="$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$3 == "connected" && ($2 == "ethernet" || $2 == "wifi") { print $1; exit }')"
        fi

        if [[ -n "$uplink_iface" ]]; then
            uplink_type="$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: -v d="$uplink_iface" '$1 == d { print $2; exit }')"
            if [[ "$uplink_type" == "ethernet" ]]; then
                slave_conn="${bridge_name}-slave-${uplink_iface}"
                if ! sudo nmcli -t -f NAME connection show | grep -Fxq "$slave_conn"; then
                    sudo nmcli connection add type ethernet ifname "$uplink_iface" master "$bridge_name" con-name "$slave_conn" autoconnect yes >/dev/null
                fi
                sudo nmcli connection up "$bridge_name" >/dev/null || true
                sudo nmcli connection up "$slave_conn" >/dev/null || true
            else
                warn "Uplink ${uplink_iface} is type '${uplink_type:-unknown}', not ethernet; skipping bridge slave attachment"
                sudo nmcli connection up "$bridge_name" >/dev/null || true
            fi
        else
            warn "Could not determine uplink interface for ${bridge_name}; bridge may have no external connectivity"
            sudo nmcli connection up "$bridge_name" >/dev/null || true
        fi

        bridge_state="$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v dev="$bridge_name" '$1 == dev {print $2; exit}')"
        [[ "$bridge_state" == "connected" ]] || warn "Bridge ${bridge_name} is present but not connected"
    else
        warn "NetworkManager unavailable; creating bare bridge ${bridge_name} without uplink enslaving"
        sudo ip link add name "$bridge_name" type bridge
        sudo ip link set "$bridge_name" up
    fi

    ip link show "$bridge_name" >/dev/null 2>&1 || fatal "Failed to create bridge interface: ${bridge_name}"
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
        --recreate)
            RECREATE=1
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
[[ -n "$ISO_PATH" ]] || fatal "ISO path cannot be empty"
[[ -n "$DISK_PATH" ]] || fatal "Disk path cannot be empty"
[[ -n "$DISK_SIZE_GB" ]] || fatal "Disk size cannot be empty"
[[ -n "$MEMORY_MB" ]] || fatal "Memory cannot be empty"
[[ -n "$VCPUS" ]] || fatal "vCPU count cannot be empty"
[[ -n "$REPO_SHARE_PATH" ]] || fatal "Repo path cannot be empty"

if [[ -z "$NETWORK_ARG" ]]; then
    NETWORK_ARG="bridge=br0,model=virtio"
fi

require_cmd virsh
require_cmd virt-install
require_cmd qemu-img
require_cmd systemctl
require_cmd ip
command -v swtpm >/dev/null 2>&1 || fatal "swtpm is required for TPM emulation"

[[ -f "$ISO_PATH" ]] || fatal "ISO not found: $ISO_PATH"
[[ -d "$REPO_SHARE_PATH" ]] || fatal "Repo path not found: $REPO_SHARE_PATH"

if [[ "$LIBVIRT_CONNECT" == "qemu:///system" ]] && ! systemctl is-active --quiet libvirtd; then
    fatal "libvirtd is not active; start it with: sudo systemctl start libvirtd"
fi

if [[ "$NETWORK_ARG" == bridge=* ]]; then
    BRIDGE_NAME="$(extract_bridge_name "$NETWORK_ARG")"
    [[ -n "$BRIDGE_NAME" ]] || fatal "Unable to parse bridge name from --network: $NETWORK_ARG"
    ensure_bridge_exists "$BRIDGE_NAME"
fi

if virsh --connect "$LIBVIRT_CONNECT" dominfo "$VM_NAME" >/dev/null 2>&1; then
    if (( RECREATE )); then
        log "Recreating existing VM: $VM_NAME"
        vm_state="$(virsh --connect "$LIBVIRT_CONNECT" domstate "$VM_NAME" 2>/dev/null | tr -d '[:space:]')"
        if [[ "$vm_state" != "shutoff" ]]; then
            virsh --connect "$LIBVIRT_CONNECT" destroy "$VM_NAME" >/dev/null || true
        fi
        virsh --connect "$LIBVIRT_CONNECT" undefine "$VM_NAME" --nvram >/dev/null 2>&1 || virsh --connect "$LIBVIRT_CONNECT" undefine "$VM_NAME" >/dev/null
    else
        fatal "VM already exists in libvirt: $VM_NAME (use --recreate to replace it)"
    fi
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
