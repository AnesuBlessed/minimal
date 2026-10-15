#!/usr/bin/env bash
# One-shot deployment helpers; callers use strict mode and hold the same lock.
COMPONENTS=(hypr waybar wlogout fuzzel foot mako fastfetch minimal)
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }
source_for() {
    if [[ $1 == minimal ]]; then printf '%s\n' "$SOURCE_DIR"; else printf '%s/%s\n' "$SOURCE_DIR" "$1"; fi
}
parse_options() {
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
    CHECK_ONLY=false
    SELECTED_BACKUP=''
    while (($#)); do
        case $1 in
            --check) CHECK_ONLY=true; shift ;;
            --config-dir) (($# >= 2)) || fail '--config-dir needs a path'; CONFIG_DIR=$2; shift 2 ;;
            --backup) (($# >= 2)) || fail '--backup needs a path'; SELECTED_BACKUP=$2; shift 2 ;;
            *) fail "Unknown option: $1" ;;
        esac
    done
    CONFIG_DIR=$(realpath -m -- "$CONFIG_DIR")
    [[ $CONFIG_DIR != / && $CONFIG_DIR != "$SOURCE_DIR" ]] || fail 'Unsafe configuration directory'
    [[ $CONFIG_DIR != *$'\n'* && $CONFIG_DIR != *$'\t'* && $SOURCE_DIR != *$'\n'* && $SOURCE_DIR != *$'\t'* ]] || fail 'Paths cannot contain tabs/newlines'
    BACKUP_BASE="$CONFIG_DIR/backups"
}
lock_deployment() {
    mkdir -p -- "$CONFIG_DIR"
    exec 9>"$CONFIG_DIR/.minimal-deployment.lock"
    flock -n 9 || fail 'Another deployment or restore is running'
}
# Roll back only operations recorded by this transaction. Never follow symlinks.
rollback_transaction() {
    local comp dst
    set +e
    for ((i=${#CHANGED[@]}-1; i>=0; i--)); do
        comp=${CHANGED[i]}; dst="$CONFIG_DIR/$comp"
        if exists "$TXN/displaced/$comp"; then
            if exists "$dst"; then mv -T -- "$dst" "$TXN/interrupted/$comp" || continue; fi
            mv -T -- "$TXN/displaced/$comp" "$dst" || printf 'Recovery needed: %s\n' "$comp" >&2
        elif [[ -e "$TXN/created/$comp" ]] && exists "$dst"; then
            mv -T -- "$dst" "$TXN/interrupted/$comp" || true
        fi
    done
    printf 'failed\n' > "$TXN/status"
    if [[ -n ${RESTORE_BACKUP:-} ]]; then printf 'installed\n' > "$RESTORE_BACKUP/status"; fi
    printf 'Operation failed; previous configuration restored where possible. Recovery files: %s\n' "$TXN" >&2
}
transaction_exit() {
    local result=$?
    trap - EXIT INT TERM HUP
    if [[ ${COMMITTED:-false} != true ]]; then rollback_transaction; fi
    exit "$result"
}
