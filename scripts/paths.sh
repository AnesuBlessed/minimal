#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — PATH RESOLUTION
# =============================================================================
MINIMAL_ROOT="${MINIMAL_ROOT:-$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")}"
MINIMAL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
MINIMAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/minimal"
MINIMAL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/minimal"
# Without XDG_RUNTIME_DIR, never fall back to a predictable shared /tmp path
# (another user could pre-create it and hold lock.lock); stay under $HOME.
MINIMAL_RUNTIME="${XDG_RUNTIME_DIR:-$MINIMAL_CACHE/runtime}/minimal"
export MINIMAL_ROOT MINIMAL_CONFIG MINIMAL_CACHE MINIMAL_STATE MINIMAL_RUNTIME
