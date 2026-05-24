#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VM_DIR="${REPO_ROOT}/.vm/qemu"

COMMAND="test"
DISK_PATH="${DISK_PATH:-${VM_DIR}/arch-install.qcow2}"
DISK_SIZE="${DISK_SIZE:-80G}"
MEMORY_MB="${MEMORY_MB:-8192}"
VCPUS="${VCPUS:-4}"
TIMEOUT_INSTALL="${TIMEOUT_INSTALL:-90m}"
TIMEOUT_BOOT="${TIMEOUT_BOOT:-8m}"
FULL_INSTALL=0
REBUILD_ISO=0
SUDO=(sudo)
if (( EUID == 0 )); then
    SUDO=()
fi

usage() {
    cat <<'EOF'
Usage: scripts/vm-qemu-test.sh [command] [options]

Commands:
  test             Build the autoinstall ISO if needed, install, then boot-check
  build-iso        Build only the autoinstall ISO
  install          Run only the installer VM
  boot-check       Boot the installed disk and wait for a login prompt
  clean            Remove generated VM artifacts

Options:
  --disk <path>    VM qcow2 disk path
  --disk-size <n>  Disk size for new qcow2 disk (default: 80G)
  --memory <mb>    VM memory in MiB (default: 8192)
  --cpus <n>       VM vCPU count (default: 4)
  --full           Include AUR and dotfiles steps instead of smoke-test skips
  --rebuild-iso    Force rebuild of generated autoinstall ISO
  --help           Show this help text

Environment:
  DISK_PATH, DISK_SIZE, MEMORY_MB, VCPUS, TIMEOUT_INSTALL, TIMEOUT_BOOT
EOF
}

log() {
    printf '[vm-qemu] %s\n' "$*"
}

fatal() {
    printf '[vm-qemu] error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fatal "Required command not found: $cmd"
}

ensure_sudo() {
    if (( EUID == 0 )); then
        return 0
    fi

    if ! sudo -v; then
        fatal "sudo is required for mkarchiso/root-owned build artifacts"
    fi
}

detect_ovmf_file() {
    local basename="$1"
    local candidate
    for candidate in \
        "/usr/share/edk2/x64/${basename}" \
        "/usr/share/edk2-ovmf/x64/${basename}" \
        "/usr/share/OVMF/${basename}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

prepare_profile() {
    require_cmd mkarchiso
    require_cmd rsync
    ensure_sudo

    local releng_profile="/usr/share/archiso/configs/releng"
    local profile_dir="${VM_DIR}/profile"
    local airootfs="${profile_dir}/airootfs"
    local skip_args=(
        --skip-aur
        --skip-dotfiles
    )
    local rendered_skip_args=""

    if (( FULL_INSTALL )); then
        skip_args=()
    fi

    if ((${#skip_args[@]})); then
        printf -v rendered_skip_args '%q ' "${skip_args[@]}"
    fi

    [[ -d "$releng_profile" ]] || fatal "Archiso releng profile not found: ${releng_profile}"

    "${SUDO[@]}" rm -rf "$profile_dir"
    mkdir -p "$VM_DIR"
    cp -a "$releng_profile" "$profile_dir"

    mkdir -p "${airootfs}/root/arch-install"
    rsync -a --delete \
        --exclude '.git' \
        --exclude '.vm' \
        --exclude 'result' \
        --exclude 'result-*' \
        "${REPO_ROOT}/" "${airootfs}/root/arch-install/"

    install -d -m 0755 "${airootfs}/etc/systemd/system/multi-user.target.wants"
    install -d -m 0755 "${airootfs}/etc/systemd/system" "${airootfs}/root"

    cat >"${airootfs}/etc/systemd/system/arch-install-vm.service" <<'EOF'
[Unit]
Description=Run arch-install VM smoke test
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/root/run-arch-install-vm.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

    ln -s ../arch-install-vm.service "${airootfs}/etc/systemd/system/multi-user.target.wants/arch-install-vm.service"

    cat >"${airootfs}/root/run-arch-install-vm.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a /root/arch-install-vm.log /dev/ttyS0) 2>&1

echo "ARCH_INSTALL_VM_START"
systemctl start NetworkManager || true
for _ in {1..60}; do
    ping -c 1 -W 1 archlinux.org >/dev/null 2>&1 && break
    sleep 2
done

install -d -m 0700 /root/arch-install-vm-secrets
printf '%s' 'archtest' >/root/arch-install-vm-secrets/root_password
printf '%s' 'archtest' >/root/arch-install-vm-secrets/user_password
printf '%s' 'archtest' >/root/arch-install-vm-secrets/luks_passphrase
chmod 0600 /root/arch-install-vm-secrets/*

cd /root/arch-install
vm_extra_args=(${rendered_skip_args})
./install.sh \\
    --disk /dev/vda \\
    --hostname arch-vm \\
    --username k \\
    --timezone America/Chicago \\
    --confirm-destroy \\
    --non-interactive \\
    --root-password-file /root/arch-install-vm-secrets/root_password \\
    --user-password-file /root/arch-install-vm-secrets/user_password \\
    --luks-passphrase-file /root/arch-install-vm-secrets/luks_passphrase \\
    "\${vm_extra_args[@]}" \\
    --vm-test

echo "ARCH_INSTALL_VM_SUCCESS"
sync
systemctl poweroff
EOF
    chmod 0755 "${airootfs}/root/run-arch-install-vm.sh"
}

build_iso() {
    local out_dir="${VM_DIR}/out"
    local work_dir="${VM_DIR}/mkarchiso-work"
    local auto_iso="${VM_DIR}/arch-install-autoinstall.iso"

    if [[ -f "$auto_iso" && "$REBUILD_ISO" -eq 0 ]]; then
        log "Using existing autoinstall ISO: ${auto_iso}"
        return 0
    fi

    prepare_profile
    ensure_sudo
    "${SUDO[@]}" rm -rf "$out_dir" "$work_dir"
    mkdir -p "$out_dir"

    log "Building autoinstall ISO"
    "${SUDO[@]}" mkarchiso -v -w "$work_dir" -o "$out_dir" "${VM_DIR}/profile"

    local built_iso
    built_iso="$(find "$out_dir" -maxdepth 1 -type f -name '*.iso' | sort | tail -n 1)"
    [[ -n "$built_iso" && -f "$built_iso" ]] || fatal "mkarchiso did not produce an ISO"
    cp -f "$built_iso" "$auto_iso"
    log "Built ${auto_iso}"
}

prepare_qemu_state() {
    require_cmd qemu-img
    require_cmd qemu-system-x86_64
    require_cmd swtpm
    require_cmd timeout

    mkdir -p "$VM_DIR"
    if [[ ! -f "$DISK_PATH" ]]; then
        log "Creating disk ${DISK_PATH} (${DISK_SIZE})"
        qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE" >/dev/null
    fi

    local ovmf_vars_src
    ovmf_vars_src="$(detect_ovmf_file OVMF_VARS.fd)" || fatal "Could not find OVMF_VARS.fd"
    if [[ ! -f "${VM_DIR}/OVMF_VARS.fd" ]]; then
        cp "$ovmf_vars_src" "${VM_DIR}/OVMF_VARS.fd"
    fi
}

start_swtpm() {
    local tpm_dir="${VM_DIR}/tpm"
    local tpm_sock="${VM_DIR}/swtpm.sock"
    rm -f "$tpm_sock"
    mkdir -p "$tpm_dir"
    swtpm socket --tpm2 --tpmstate dir="$tpm_dir" --ctrl type=unixio,path="$tpm_sock" --daemon
}

qemu_common_args() {
    local ovmf_code
    ovmf_code="$(detect_ovmf_file OVMF_CODE.fd)" || fatal "Could not find OVMF_CODE.fd"
    printf '%s\n' \
        -enable-kvm \
        -machine q35,smm=on \
        -cpu host \
        -m "$MEMORY_MB" \
        -smp "$VCPUS" \
        -drive "if=pflash,format=raw,readonly=on,file=${ovmf_code}" \
        -drive "if=pflash,format=raw,file=${VM_DIR}/OVMF_VARS.fd" \
        -drive "file=${DISK_PATH},format=qcow2,if=virtio" \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -chardev "socket,id=chrtpm,path=${VM_DIR}/swtpm.sock" \
        -tpmdev emulator,id=tpm0,chardev=chrtpm \
        -device tpm-tis,tpmdev=tpm0 \
        -display none \
        -no-reboot
}

run_install() {
    build_iso
    prepare_qemu_state
    start_swtpm

    local log_file="${VM_DIR}/install.serial.log"
    : >"$log_file"

    log "Running unattended installer VM"
    set +e
    timeout "$TIMEOUT_INSTALL" qemu-system-x86_64 \
        $(qemu_common_args) \
        -cdrom "${VM_DIR}/arch-install-autoinstall.iso" \
        -boot d \
        -serial "file:${log_file}"
    local qemu_status=$?
    set -e

    if ! grep -q 'ARCH_INSTALL_VM_SUCCESS' "$log_file"; then
        tail -n 120 "$log_file" >&2 || true
        fatal "Installer VM did not report success (qemu exit ${qemu_status}); log: ${log_file}"
    fi

    log "Installer VM completed successfully"
}

boot_check() {
    prepare_qemu_state
    start_swtpm

    local log_file="${VM_DIR}/boot.serial.log"
    : >"$log_file"

    log "Booting installed disk for serial login check"
    set +e
    timeout "$TIMEOUT_BOOT" qemu-system-x86_64 \
        $(qemu_common_args) \
        -boot c \
        -serial "file:${log_file}"
    local qemu_status=$?
    set -e

    if grep -Eq 'arch-vm login:|Reached target.*Multi-User System|Reached target.*Graphical Interface' "$log_file"; then
        log "Installed disk reached a bootable login/target state"
        return 0
    fi

    tail -n 120 "$log_file" >&2 || true
    fatal "Installed disk did not reach login before timeout/exit ${qemu_status}; log: ${log_file}"
}

clean() {
    ensure_sudo
    "${SUDO[@]}" rm -rf "$VM_DIR"
    log "Removed ${VM_DIR}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        test|build-iso|install|boot-check|clean)
            COMMAND="$1"
            shift
            ;;
        --disk)
            DISK_PATH="${2:-}"
            shift 2
            ;;
        --disk-size)
            DISK_SIZE="${2:-}"
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
        --full)
            FULL_INSTALL=1
            shift
            ;;
        --rebuild-iso)
            REBUILD_ISO=1
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

case "$COMMAND" in
    build-iso)
        build_iso
        ;;
    install)
        run_install
        ;;
    boot-check)
        boot_check
        ;;
    test)
        run_install
        boot_check
        ;;
    clean)
        clean
        ;;
esac
