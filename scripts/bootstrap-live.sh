#!/bin/sh

set -eu

REPO_URL="${REPO_URL:-https://github.com/kadencartwright/arch-install.git}"
REPO_REF="${REPO_REF:-main}"
INSTALL_DIR="${INSTALL_DIR:-/tmp/arch-install}"
DEFAULT_USERNAME="${DEFAULT_USERNAME:-k}"
DEFAULT_TIMEZONE="${DEFAULT_TIMEZONE:-America/Chicago}"

SECRETS_DIR=""

log() {
    printf '[bootstrap-live] %s\n' "$*"
}

warn() {
    printf '[bootstrap-live] warning: %s\n' "$*" >&2
}

fatal() {
    printf '[bootstrap-live] error: %s\n' "$*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fatal "required command not found: $1"
}

cleanup() {
    if [ -n "$SECRETS_DIR" ] && [ -d "$SECRETS_DIR" ]; then
        rm -f "$SECRETS_DIR/root_password" "$SECRETS_DIR/user_password" "$SECRETS_DIR/luks_passphrase" 2>/dev/null || true
        rmdir "$SECRETS_DIR" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

prompt() {
    label="$1"
    default="${2:-}"
    value=""

    if [ -n "$default" ]; then
        printf '%s [%s]: ' "$label" "$default" >/dev/tty
    else
        printf '%s: ' "$label" >/dev/tty
    fi

    IFS= read -r value </dev/tty || fatal "failed to read input"
    if [ -z "$value" ]; then
        value="$default"
    fi
    printf '%s' "$value"
}

prompt_required() {
    label="$1"
    value=""
    while [ -z "$value" ]; do
        value="$(prompt "$label" "")"
        if [ -z "$value" ]; then
            warn "$label cannot be empty"
        fi
    done
    printf '%s' "$value"
}

prompt_yes_no() {
    label="$1"
    default="${2:-y}"
    answer=""
    suffix="[y/N]"
    [ "$default" = "y" ] && suffix="[Y/n]"

    while :; do
        printf '%s %s: ' "$label" "$suffix" >/dev/tty
        IFS= read -r answer </dev/tty || fatal "failed to read input"
        [ -n "$answer" ] || answer="$default"
        case "$answer" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
            *) warn "Please answer y or n" ;;
        esac
    done
}

prompt_secret() {
    label="$1"
    first=""
    second=""

    while :; do
        printf '%s: ' "$label" >/dev/tty
        old_stty="$(stty -g </dev/tty)"
        stty -echo </dev/tty
        IFS= read -r first </dev/tty || {
            stty "$old_stty" </dev/tty
            fatal "failed to read secret"
        }
        stty "$old_stty" </dev/tty
        printf '\n' >/dev/tty

        printf 'Confirm %s: ' "$label" >/dev/tty
        old_stty="$(stty -g </dev/tty)"
        stty -echo </dev/tty
        IFS= read -r second </dev/tty || {
            stty "$old_stty" </dev/tty
            fatal "failed to read secret confirmation"
        }
        stty "$old_stty" </dev/tty
        printf '\n' >/dev/tty

        if [ -z "$first" ]; then
            warn "$label cannot be empty"
        elif [ "$first" = "$second" ]; then
            printf '%s' "$first"
            return 0
        else
            warn "Values did not match"
        fi
    done
}

install_prereqs() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi

    need_cmd pacman
    log "Installing git"
    pacman -Sy --needed --noconfirm git
}

disk_label() {
    disk="$1"
    lsblk -dnpo NAME,SIZE,MODEL,SERIAL "$disk" | awk '{$1=$1; print}'
}

disk_by_id() {
    disk="$1"
    found=""
    for path in /dev/disk/by-id/*; do
        [ -e "$path" ] || continue
        case "$path" in
            *-part*) continue ;;
        esac
        target="$(readlink -f "$path" 2>/dev/null || true)"
        if [ "$target" = "$disk" ]; then
            found="$path"
            break
        fi
    done

    if [ -n "$found" ]; then
        printf '%s' "$found"
    else
        printf '%s' "$disk"
    fi
}

choose_disk() {
    disks_file="$(mktemp)"
    labels_file="$(mktemp)"
    trap 'rm -f "$disks_file" "$labels_file"; cleanup' EXIT INT TERM

    lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }' >"$disks_file"
    [ -s "$disks_file" ] || fatal "No disks detected"

    printf '[bootstrap-live] Available disks:\n' >/dev/tty
    i=1
    while IFS= read -r disk; do
        by_id="$(disk_by_id "$disk")"
        label="$(disk_label "$disk")"
        printf '  %s) %s\n     %s\n' "$i" "$label" "$by_id" >/dev/tty
        printf '%s\t%s\n' "$i" "$by_id" >>"$labels_file"
        i=$((i + 1))
    done <"$disks_file"

    choice=""
    while :; do
        printf 'Select target disk number: ' >/dev/tty
        IFS= read -r choice </dev/tty || fatal "failed to read disk selection"
        selected="$(awk -F '\t' -v n="$choice" '$1 == n { print $2 }' "$labels_file")"
        if [ -n "$selected" ]; then
            rm -f "$disks_file" "$labels_file"
            trap cleanup EXIT INT TERM
            printf '%s' "$selected"
            return 0
        fi
        warn "Invalid disk selection"
    done
}

clone_or_update_repo() {
    install_prereqs

    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Updating repo in $INSTALL_DIR"
        git -C "$INSTALL_DIR" fetch --prune origin
    else
        rm -rf "$INSTALL_DIR"
        log "Cloning $REPO_URL to $INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR"
        git -C "$INSTALL_DIR" fetch --prune origin
    fi

    log "Checking out $REPO_REF"
    git -C "$INSTALL_DIR" checkout "$REPO_REF"
    git -C "$INSTALL_DIR" pull --ff-only origin "$REPO_REF" 2>/dev/null || true
}

main() {
    [ -r /dev/tty ] || fatal "This script needs an interactive TTY"
    need_cmd lsblk
    need_cmd awk
    need_cmd readlink
    need_cmd mktemp

    clone_or_update_repo

    disk="$(choose_disk)"
    hostname="$(prompt_required "Hostname")"
    username="$(prompt "Username" "$DEFAULT_USERNAME")"
    timezone="$(prompt "Timezone" "$DEFAULT_TIMEZONE")"

    skip_aur=0
    skip_dotfiles=0
    x1c_power_workaround=0
    if ! prompt_yes_no "Install yay and AUR packages?" "y"; then
        skip_aur=1
    fi
    if ! prompt_yes_no "Install dotfiles?" "y"; then
        skip_dotfiles=1
    fi
    if prompt_yes_no "Apply ThinkPad X1 Carbon power workaround kernel params?" "n"; then
        x1c_power_workaround=1
    fi

    root_password="$(prompt_secret "Root password")"
    user_password="$(prompt_secret "Password for user $username")"
    luks_passphrase="$(prompt_secret "LUKS disk passphrase")"

    log "Install summary:"
    printf '  repo:     %s (%s)\n' "$REPO_URL" "$REPO_REF" >/dev/tty
    printf '  workdir:  %s\n' "$INSTALL_DIR" >/dev/tty
    printf '  disk:     %s\n' "$disk" >/dev/tty
    printf '  hostname: %s\n' "$hostname" >/dev/tty
    printf '  username: %s\n' "$username" >/dev/tty
    printf '  timezone: %s\n' "$timezone" >/dev/tty
    if [ "$skip_aur" -eq 1 ]; then
        printf '  AUR:      skipped\n' >/dev/tty
    else
        printf '  AUR:      enabled\n' >/dev/tty
    fi
    if [ "$skip_dotfiles" -eq 1 ]; then
        printf '  dotfiles: skipped\n' >/dev/tty
    else
        printf '  dotfiles: enabled\n' >/dev/tty
    fi
    if [ "$x1c_power_workaround" -eq 1 ]; then
        printf '  X1C power workaround: enabled\n' >/dev/tty
    else
        printf '  X1C power workaround: skipped\n' >/dev/tty
    fi

    printf '\nThis will ERASE %s.\n' "$disk" >/dev/tty
    printf 'Type ERASE to continue: ' >/dev/tty
    IFS= read -r confirm </dev/tty || fatal "failed to read confirmation"
    [ "$confirm" = "ERASE" ] || fatal "confirmation mismatch; aborting"

    SECRETS_DIR="$(mktemp -d /tmp/arch-install-secrets.XXXXXX)"
    chmod 700 "$SECRETS_DIR"
    printf '%s' "$root_password" >"$SECRETS_DIR/root_password"
    printf '%s' "$user_password" >"$SECRETS_DIR/user_password"
    printf '%s' "$luks_passphrase" >"$SECRETS_DIR/luks_passphrase"
    chmod 600 "$SECRETS_DIR/root_password" "$SECRETS_DIR/user_password" "$SECRETS_DIR/luks_passphrase"

    set -- \
        "$INSTALL_DIR/install.sh" \
        --disk "$disk" \
        --hostname "$hostname" \
        --username "$username" \
        --timezone "$timezone" \
        --root-password-file "$SECRETS_DIR/root_password" \
        --user-password-file "$SECRETS_DIR/user_password" \
        --luks-passphrase-file "$SECRETS_DIR/luks_passphrase" \
        --confirm-destroy

    if [ "$skip_aur" -eq 1 ]; then
        set -- "$@" --skip-aur
    fi
    if [ "$skip_dotfiles" -eq 1 ]; then
        set -- "$@" --skip-dotfiles
    fi
    if [ "$x1c_power_workaround" -eq 1 ]; then
        set -- "$@" --x1c-power-workaround
    fi

    log "Starting installer"
    "$@"
}

main "$@"
