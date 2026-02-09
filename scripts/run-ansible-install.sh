#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-ansible-install.sh --disk /dev/vda --hostname arch-test [options]

Options:
  --disk PATH                Target disk (required)
  --confirm-destroy PATH     Must exactly match --disk (required)
  --hostname NAME            Hostname (required)
  --username NAME            Username (default: k)
  --timezone TZ              Timezone (default: America/Chicago)
  --root-password-file PATH  Root password file (required)
  --user-password-file PATH  User password file (required)
  --luks-password-file PATH  LUKS passphrase file (required)
  --disable-tpm-enroll       Skip TPM enrollment (default: enabled)
  --help                     Show help
USAGE
}

die() {
  printf '[ansible-install] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

DISK=""
CONFIRM_DESTROY=""
HOSTNAME=""
USERNAME="k"
TIMEZONE="America/Chicago"
ROOT_PASSWORD_FILE=""
USER_PASSWORD_FILE=""
LUKS_PASSWORD_FILE=""
ENABLE_TPM_ENROLL="true"

while (($# > 0)); do
  case "$1" in
    --disk)
      DISK="${2:-}"
      shift 2
      ;;
    --confirm-destroy)
      CONFIRM_DESTROY="${2:-}"
      shift 2
      ;;
    --hostname)
      HOSTNAME="${2:-}"
      shift 2
      ;;
    --username)
      USERNAME="${2:-}"
      shift 2
      ;;
    --timezone)
      TIMEZONE="${2:-}"
      shift 2
      ;;
    --root-password-file)
      ROOT_PASSWORD_FILE="${2:-}"
      shift 2
      ;;
    --user-password-file)
      USER_PASSWORD_FILE="${2:-}"
      shift 2
      ;;
    --luks-password-file)
      LUKS_PASSWORD_FILE="${2:-}"
      shift 2
      ;;
    --disable-tpm-enroll)
      ENABLE_TPM_ENROLL="false"
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

[[ -n "$DISK" ]] || die "--disk is required"
[[ -n "$CONFIRM_DESTROY" ]] || die "--confirm-destroy is required"
[[ -n "$HOSTNAME" ]] || die "--hostname is required"
[[ -n "$ROOT_PASSWORD_FILE" ]] || die "--root-password-file is required"
[[ -n "$USER_PASSWORD_FILE" ]] || die "--user-password-file is required"
[[ -n "$LUKS_PASSWORD_FILE" ]] || die "--luks-password-file is required"

[[ "$CONFIRM_DESTROY" == "$DISK" ]] || die "--confirm-destroy must match --disk"
[[ -b "$DISK" ]] || die "Disk not found: $DISK"
[[ -f "$ROOT_PASSWORD_FILE" ]] || die "Root password file not found"
[[ -f "$USER_PASSWORD_FILE" ]] || die "User password file not found"
[[ -f "$LUKS_PASSWORD_FILE" ]] || die "LUKS password file not found"

require_cmd ansible-playbook
require_cmd ansible-galaxy

cd "$REPO_ROOT"
export ANSIBLE_CONFIG="$REPO_ROOT/ansible/ansible.cfg"

ansible-galaxy collection install -r ansible/requirements.yml >/dev/null

exec ansible-playbook \
  -i ansible/inventory/hosts.ini \
  ansible/playbooks/install.yml \
  -e "install_disk=${DISK}" \
  -e "install_confirm_destroy=${CONFIRM_DESTROY}" \
  -e "install_hostname=${HOSTNAME}" \
  -e "install_username=${USERNAME}" \
  -e "install_timezone=${TIMEZONE}" \
  -e "install_root_password_file=${ROOT_PASSWORD_FILE}" \
  -e "install_user_password_file=${USER_PASSWORD_FILE}" \
  -e "install_luks_password_file=${LUKS_PASSWORD_FILE}" \
  -e "install_enable_tpm_enroll=${ENABLE_TPM_ENROLL}"
