#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-vm-ci-test.sh --iso /path/to/archlinux.iso [options]

Options:
  --iso PATH            Path to Arch Linux ISO (required)
  --workdir PATH        Host repo/workdir to share (default: repo root)
  --memory SIZE         VM memory (default: 8G)
  --cpus N              VM vCPUs (default: 4)
  --disk-size SIZE      VM disk size (default: 80G)
  --name NAME           VM name (default: arch-install-ci)
  --hostname NAME       Hostname passed to installer (default: arch-ci)
  --username NAME       Username passed to installer (default: k)
  --timezone TZ         Timezone passed to installer (default: America/Chicago)
  --root-password PASS  Root password for test install (default: rootpass)
  --user-password PASS  User password for test install (default: userpass)
  --luks-password PASS  LUKS password for test install (default: lukspass)
  --installer MODE      Installer mode: ansible|shell (default: ansible)
  --timeout SEC         Global expect timeout in seconds (default: 5400)
  --keep                Keep VM temp dir and logs
  --help                Show this help

Notes:
  - This is a best-effort unattended harness driven via serial console + expect.
  - It assumes the Arch live ISO presents a root shell/login on the serial console.
USAGE
}

log() {
  printf '[vm-ci] %s\n' "$*"
}

die() {
  printf '[vm-ci] ERROR: %s\n' "$*" >&2
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

b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

ISO_PATH=""
WORKDIR="$REPO_ROOT"
MEMORY="8G"
CPUS="4"
DISK_SIZE="80G"
VM_NAME="arch-install-ci"
HOSTNAME_VALUE="arch-ci"
USERNAME_VALUE="k"
TIMEZONE_VALUE="America/Chicago"
ROOT_PASSWORD="rootpass"
USER_PASSWORD="userpass"
LUKS_PASSWORD="lukspass"
INSTALLER_MODE="ansible"
EXPECT_TIMEOUT="5400"
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
    --name)
      VM_NAME="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME_VALUE="${2:-}"
      shift 2
      ;;
    --username)
      USERNAME_VALUE="${2:-}"
      shift 2
      ;;
    --timezone)
      TIMEZONE_VALUE="${2:-}"
      shift 2
      ;;
    --root-password)
      ROOT_PASSWORD="${2:-}"
      shift 2
      ;;
    --user-password)
      USER_PASSWORD="${2:-}"
      shift 2
      ;;
    --luks-password)
      LUKS_PASSWORD="${2:-}"
      shift 2
      ;;
    --installer)
      INSTALLER_MODE="${2:-}"
      shift 2
      ;;
    --timeout)
      EXPECT_TIMEOUT="${2:-}"
      shift 2
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
require_cmd expect
require_cmd base64
require_cmd rsync

[[ "$INSTALLER_MODE" == "ansible" || "$INSTALLER_MODE" == "shell" ]] || die "--installer must be ansible or shell"

TMP_DIR="$(mktemp -d /tmp/arch-install-ci.XXXXXX)"
DISK_PATH="${TMP_DIR}/${VM_NAME}.qcow2"
EXPECT_LOG="${TMP_DIR}/expect-session.log"
EXPECT_SCRIPT="${TMP_DIR}/runner.expect"

cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    log "Keeping artifacts at: $TMP_DIR"
    return 0
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

log "Creating ephemeral disk ${DISK_PATH} (${DISK_SIZE})"
qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE" >/dev/null

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

QEMU_CMD=(
  qemu-system-x86_64
  -enable-kvm
  -machine q35,accel=kvm
  -cpu host
  -smp "$CPUS"
  -m "$MEMORY"
  -name "$VM_NAME"
  -boot order=d
  -drive "if=virtio,format=qcow2,file=${DISK_PATH}"
  -cdrom "$ISO_PATH"
  -netdev user,id=net0
  -device virtio-net-pci,netdev=net0
  -virtfs "local,path=${WORKDIR},mount_tag=hostshare,security_model=none,id=hostshare"
  -nographic
)

if [[ -n "$OVMF_CODE" && -n "$OVMF_VARS_TEMPLATE" ]]; then
  OVMF_VARS="${TMP_DIR}/OVMF_VARS.fd"
  cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"
  QEMU_CMD+=(
    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"
  )
fi

ROOT_PASSWORD_B64="$(b64 "$ROOT_PASSWORD")"
USER_PASSWORD_B64="$(b64 "$USER_PASSWORD")"
LUKS_PASSWORD_B64="$(b64 "$LUKS_PASSWORD")"

cat >"$EXPECT_SCRIPT" <<'EXPECT'
#!/usr/bin/env expect
set timeout $env(EXPECT_TIMEOUT)
log_user 1
match_max 100000

set qemu_cmd $env(QEMU_CMD)
set log_file_path $env(EXPECT_LOG)
log_file -a $log_file_path

proc send_cmd {cmd} {
  send -- "$cmd\r"
  expect {
    -re {# $} {}
    timeout { puts "TIMEOUT waiting for prompt after: $cmd"; exit 20 }
    eof { puts "EOF while waiting for prompt after: $cmd"; exit 21 }
  }
}

spawn -noecho sh -c $qemu_cmd

set got_prompt 0
expect {
  -re {archiso login:} {
    send -- "root\r"
    exp_continue
  }
  -re {login:} {
    send -- "root\r"
    exp_continue
  }
  -re {root@archiso.*# $} {
    set got_prompt 1
  }
  -re {# $} {
    set got_prompt 1
  }
  timeout {
    puts "TIMEOUT waiting for archiso shell prompt"
    exit 10
  }
  eof {
    puts "EOF before shell prompt"
    exit 11
  }
}

if {!$got_prompt} {
  puts "Failed to acquire shell prompt"
  exit 12
}

send_cmd "set -euo pipefail"
send_cmd "mkdir -p /mnt/host /root/arch-install"
send_cmd "mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host"
send_cmd "rsync -a --delete /mnt/host/ /root/arch-install/"
send_cmd "cd /root/arch-install"

send_cmd "printf '%s' '$env(ROOT_PASSWORD_B64)' | base64 -d > /tmp/root_password"
send_cmd "printf '%s' '$env(USER_PASSWORD_B64)' | base64 -d > /tmp/user_password"
send_cmd "printf '%s' '$env(LUKS_PASSWORD_B64)' | base64 -d > /tmp/luks_password"

set install_cmd "./install.sh --disk /dev/vda --hostname $env(HOSTNAME_VALUE) --username $env(USERNAME_VALUE) --timezone $env(TIMEZONE_VALUE) --root-password-file /tmp/root_password --user-password-file /tmp/user_password --luks-password-file /tmp/luks_password --confirm-destroy /dev/vda --non-interactive"
if {$env(INSTALLER_MODE) == "ansible"} {
  send_cmd "pacman -S --noconfirm --needed ansible rsync python"
  set install_cmd "./scripts/run-ansible-install.sh --disk /dev/vda --confirm-destroy /dev/vda --hostname $env(HOSTNAME_VALUE) --username $env(USERNAME_VALUE) --timezone $env(TIMEZONE_VALUE) --root-password-file /tmp/root_password --user-password-file /tmp/user_password --luks-password-file /tmp/luks_password"
}
send -- "$install_cmd > /root/install-run.log 2>&1 ; echo __INSTALL_RC:$?\r"

expect {
  -re {__INSTALL_RC:([0-9]+)} {
    set rc $expect_out(1,string)
    if {$rc != 0} {
      puts "INSTALL FAILED with rc=$rc"
      send_cmd "tail -n 200 /root/install-run.log || true"
      exit 30
    }
  }
  timeout {
    puts "TIMEOUT waiting for installer completion"
    exit 31
  }
  eof {
    puts "EOF while waiting for installer completion"
    exit 32
  }
}

send_cmd "echo INSTALL_OK"
send_cmd "poweroff -f"

expect {
  eof {}
  timeout {}
}

exit 0
EXPECT
chmod +x "$EXPECT_SCRIPT"

QEMU_CMD_STR="$(printf '%q ' "${QEMU_CMD[@]}")"
export QEMU_CMD="$QEMU_CMD_STR"
export EXPECT_TIMEOUT
export EXPECT_LOG
export ROOT_PASSWORD_B64
export USER_PASSWORD_B64
export LUKS_PASSWORD_B64
export HOSTNAME_VALUE
export USERNAME_VALUE
export TIMEZONE_VALUE
export INSTALLER_MODE

log "Starting unattended VM run"
log "Logs: ${EXPECT_LOG}"
log "Installer mode: ${INSTALLER_MODE}"

if ! expect "$EXPECT_SCRIPT"; then
  log "Unattended run failed. Inspect: ${EXPECT_LOG}"
  exit 1
fi

log "Unattended VM test completed successfully"
log "Session log: ${EXPECT_LOG}"
