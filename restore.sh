#!/usr/bin/env bash
# Restore a manifest, including originally absent entries and original symlinks.
set -Eeuo pipefail
umask 077
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SOURCE_DIR/scripts/deployment-common.sh"
parse_options "$@"
[[ -d $BACKUP_BASE ]] || fail 'No Minimal backups exist'
if ! $CHECK_ONLY; then lock_deployment; fi
if [[ -n $SELECTED_BACKUP ]]; then
    BACKUP=$(realpath -e -- "$SELECTED_BACKUP")
else
    BACKUP=''
    while IFS= read -r -d '' candidate; do
        if [[ -f $candidate/status && $(<"$candidate/status") == installed ]]; then BACKUP=$candidate; break; fi
    done < <(find "$BACKUP_BASE" -maxdepth 1 -type d -name 'minimal-*' -print0 | sort -zr)
fi
[[ -n $BACKUP && -f $BACKUP/manifest.tsv && -f $BACKUP/config-dir ]] || fail 'No completed manifest-based backup found'
[[ $(<"$BACKUP/config-dir") == "$CONFIG_DIR" ]] || fail 'Backup belongs to a different configuration directory'
[[ $(<"$BACKUP/status") == installed ]] || fail 'Backup is not an active installation'
declare -A seen=()
# Refuse to overwrite components the user replaced independently after installation.
while IFS=$'\t' read -r comp state src; do
    [[ " ${COMPONENTS[*]} " == *" $comp "* && $state =~ ^(present|absent)$ ]] || fail 'Invalid backup manifest'
    [[ -z ${seen[$comp]:-} ]] || fail "Duplicate backup entry: $comp"
    seen[$comp]=1
    [[ -L $CONFIG_DIR/$comp && $(readlink -- "$CONFIG_DIR/$comp") == "$src" ]] || fail "Configuration changed outside deployment: $comp (preserved)"
    [[ $state != present ]] || exists "$BACKUP/original/$comp" || fail "Missing backup: $comp"
done < "$BACKUP/manifest.tsv"
((${#seen[@]} == ${#COMPONENTS[@]})) || fail 'Incomplete backup manifest'
if [[ -f $BACKUP/session-path ]]; then
    read -r session_path < "$BACKUP/session-path"
    [[ -f $session_path && ! -L $session_path ]] && cmp -s -- "$session_path" "$BACKUP/session-installed" || fail "Session entry changed outside deployment: $session_path (preserved)"
fi
if $CHECK_ONLY; then printf 'Restore preflight passed: %s\n' "$BACKUP"; exit 0; fi
TXN=$(mktemp -d "$BACKUP_BASE/restore-$(date +%Y%m%d_%H%M%S_%N)-XXXXXXXX")
mkdir -- "$TXN/staged" "$TXN/displaced" "$TXN/interrupted" "$TXN/created"
# Prepare all restored entries first; failed copies leave the live installation intact.
while IFS=$'\t' read -r comp state src; do
    if [[ $state == present ]]; then cp -a -- "$BACKUP/original/$comp" "$TXN/staged/$comp"; fi
done < "$BACKUP/manifest.tsv"
CHANGED=(); COMMITTED=false
RESTORE_BACKUP=$BACKUP
trap transaction_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
if [[ -f $BACKUP/session-path ]]; then
    snapshot_session "$session_path"
    if exists "$BACKUP/session-original"; then cp -a -- "$BACKUP/session-original" "$TXN/session-staged"; fi
    touch "$TXN/session-changed"
    mv -T -- "$session_path" "$TXN/session-displaced"
    if exists "$TXN/session-staged"; then mv -T -- "$TXN/session-staged" "$session_path"; fi
fi
while IFS=$'\t' read -r comp state src; do
    CHANGED+=("$comp")
    mv -T -- "$CONFIG_DIR/$comp" "$TXN/displaced/$comp"
    if [[ $state == present ]]; then mv -T -- "$TXN/staged/$comp" "$CONFIG_DIR/$comp"; fi
done < "$BACKUP/manifest.tsv"
printf 'restored\n' > "$BACKUP/status"
printf 'completed\n' > "$TXN/status"
COMMITTED=true
printf 'Original configuration restored. Backup retained: %s\nLog out and back in to start the restored session.\n' "$BACKUP"
