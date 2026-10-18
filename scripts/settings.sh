#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — QUICKSHELL SETTINGS & SYSTEM MANAGER WRAPPER (IPC)
# =============================================================================
set -uo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG="$MINIMAL_ROOT/quickshell/settings"
IPC_TARGET="settings"
LOG_DIR="$MINIMAL_CACHE/settings"
LOG_FILE="$LOG_DIR/quickshell.log"
IPC_LOG="$LOG_DIR/ipc.log"
ACTION="${1:-toggle}"

usage() {
    echo "Usage: settings.sh [start|stop|restart|toggle|show|hide|display|sound|network|bluetooth|power|storage|log]" >&2
}

if ! command -v quickshell >/dev/null 2>&1; then
    echo "ERROR: Quickshell was not found in PATH." >&2
    exit 127
fi

if [[ ! -f "$CONFIG/shell.qml" ]]; then
    echo "ERROR: Settings shell not found at $CONFIG/shell.qml" >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/settings.lock"
flock -w 5 9 || exit 1

call_ipc() {
    quickshell -p "$CONFIG" ipc call "$IPC_TARGET" "$1"
}

case "$ACTION" in
    start) ACTION=show ;;
    restart)
        quickshell kill -p "$CONFIG" >/dev/null 2>&1 || true
        ACTION=show ;;
esac
case "$ACTION" in
    stop) quickshell kill -p "$CONFIG"; ;;
    log)
        tail -n 100 "$LOG_FILE"
        ;;
    toggle|show|hide|display|sound|network|bluetooth|power|storage)
        if call_ipc "$ACTION" >"$IPC_LOG" 2>&1; then
            exit 0
        fi

        if [[ "$ACTION" == "hide" ]]; then
            exit 0
        fi

        quickshell -n -p "$CONFIG" >>"$LOG_FILE" 2>&1 9>&- &
        SHELL_PID=$!

        for _ in {1..50}; do
            if call_ipc "$ACTION" >"$IPC_LOG" 2>&1; then
                exit 0
            fi
            if ! kill -0 "$SHELL_PID" 2>/dev/null; then
                break
            fi
            sleep 0.05
        done

        echo "ERROR: Failed to execute IPC command $IPC_TARGET $ACTION." >&2
        tail -n 40 "$LOG_FILE" >&2 || true
        exit 1
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac
