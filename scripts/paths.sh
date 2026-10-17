#!/usr/bin/env bash
# Shared paths: resolve symlinks once, and keep generated state outside the checkout.
MINIMAL_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
MINIMAL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
MINIMAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/minimal"
MINIMAL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/minimal"
MINIMAL_RUNTIME="${XDG_RUNTIME_DIR:-$MINIMAL_CACHE}/minimal"
export MINIMAL_ROOT MINIMAL_CONFIG MINIMAL_CACHE MINIMAL_STATE MINIMAL_RUNTIME

# Unit names and lifecycle ownership are scoped to the compositor instance.
_minimal_instance=${HYPRLAND_INSTANCE_SIGNATURE:-default}
MINIMAL_SERVICE_PREFIX="minimal-${_minimal_instance//[^a-zA-Z0-9_-]/_}"
unset _minimal_instance
export MINIMAL_SERVICE_PREFIX
