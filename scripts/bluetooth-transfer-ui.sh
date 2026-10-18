#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
export MINIMAL_TRANSFER_ID=${1:?Transfer ID required}
exec quickshell -n -p "$MINIMAL_ROOT/quickshell/transfer/shell.qml"
