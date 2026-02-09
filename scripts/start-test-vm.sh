#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/start-test-vm.sh --iso /path/to/archlinux.iso [options]

Options:
  --iso PATH          Path to Arch Linux ISO (required)
  --workdir PATH      Host directory to share into guest (default: repo root)
  --memory SIZE       VM memory (default: 8G)
  --cpus N            vCPU count (default: 4)
  --disk-size SIZE    Disk size (default: 80G)
  --ssh-port PORT     Host SSH forward port -> guest:22 (default: 2222)
  --name NAME         VM name label (default: arch-install-test)
  --headless          Run with serial console in current terminal
  --keep              Keep temp VM files after shutdown
  --help              Show this help
USAGE
}

log() {
  printf '[vm-test] %s\n' "$*"
}

die() {
  printf '[vm-test] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

find_first_existing() {
  local candidate
  for candidate in "$@"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ISO_PATH=""
WORKDIR="$REPO_ROOT"
MEMORY="8G"
CPUS="4"
DISK_SIZE="80G"
SSH_PORT="2222"
VM_NAME="arch-install-test"
HEADLESS=0
KEEP=0

while (($# > 0)); do
  case "$1" in
    --iso)
      ISO_PATH="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --memory)
      MEMORY="${2:-}"
      shift 2
      ;;
    --cpus)
      CPUS="${2:-}"
      shift 2
      ;;
    --disk-size)
      DISK_SIZE="${2:-}"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-}"
      shift 2
      ;;
    --name)
      VM_NAME="${2:-}"
      shift 2
      ;;
    --headless)
      HEADLESS=1
      shift
      ;;
    --keep)
      KEEP=1
      shift
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

[[ -n "$ISO_PATH" ]] || die "--iso is required"
[[ -f "$ISO_PATH" ]] || die "ISO not found: $ISO_PATH"
[[ -d "$WORKDIR" ]] || die "Workdir not found: $WORKDIR"

require_cmd qemu-system-x86_64
require_cmd qemu-img

TMP_DIR="$(mktemp -d /tmp/arch-install-vm.XXXXXX)"
VM_DISK="${TMP_DIR}/${VM_NAME}.qcow2"

cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    log "Keeping VM files at: $TMP_DIR"
    return 0
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log "Creating ephemeral VM disk: $VM_DISK (${DISK_SIZE})"
qemu-img create -f qcow2 "$VM_DISK" "$DISK_SIZE" >/dev/null

OVMF_CODE="$(
  find_first_existing \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/OVMF/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd || true
)"
OVMF_VARS_TEMPLATE="$(
  find_first_existing \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/x64/OVMF_VARS.fd \
    /usr/share/OVMF/x64/OVMF_VARS.fd \
    /usr/share/edk2-ovmf/x64/OVMF_VARS.fd || true
)"

QEMU_ARGS=(
  -enable-kvm
  -machine q35,accel=kvm
  -cpu host
  -smp "$CPUS"
  -m "$MEMORY"
  -name "$VM_NAME"
  -boot order=d
  -drive "if=virtio,format=qcow2,file=${VM_DISK}"
  -cdrom "$ISO_PATH"
  -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22"
  -device virtio-net-pci,netdev=net0
  -virtfs "local,path=${WORKDIR},mount_tag=hostshare,security_model=none,id=hostshare"
)

if [[ -n "$OVMF_CODE" && -n "$OVMF_VARS_TEMPLATE" ]]; then
  OVMF_VARS="${TMP_DIR}/OVMF_VARS.fd"
  cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
  QEMU_ARGS+=(
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"
  )
  log "Using UEFI firmware: $OVMF_CODE"
else
  log "UEFI firmware not found; falling back to BIOS boot."
fi

if [[ "$HEADLESS" -eq 1 ]]; then
  QEMU_ARGS+=(-nographic)
fi

cat <<INFO

[vm-test] VM starting with:
  RAM:        ${MEMORY}
  vCPUs:      ${CPUS}
  Disk:       ${DISK_SIZE} (ephemeral qcow2)
  ISO:        ${ISO_PATH}
  Share:      ${WORKDIR} (9p tag: hostshare)
  SSH fwd:    localhost:${SSH_PORT} -> guest:22
  Temp dir:   ${TMP_DIR}

Inside the Arch live environment, mount the shared repo with:
  mkdir -p /mnt/host
  mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host

Recommended flow to make an isolated writable copy before running tests:
  rsync -a --delete /mnt/host/ /root/arch-install/
  cd /root/arch-install

Then run the Ansible installer against the VM disk:
  printf 'rootpass' > /tmp/root_password
  printf 'userpass' > /tmp/user_password
  printf 'lukspass' > /tmp/luks_password
  ./scripts/run-ansible-install.sh --disk /dev/vda --confirm-destroy /dev/vda \\
    --hostname arch-test --username k --timezone America/Chicago \\
    --root-password-file /tmp/root_password --user-password-file /tmp/user_password \\
    --luks-password-file /tmp/luks_password

INFO

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
