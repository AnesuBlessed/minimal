#!/usr/bin/env bash
# Shared paths: resolve symlinks once, and keep generated state outside the checkout.
MINIMAL_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
MINIMAL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
MINIMAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/minimal"
MINIMAL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/minimal"
MINIMAL_RUNTIME="${XDG_RUNTIME_DIR:-$MINIMAL_CACHE}/minimal"
export MINIMAL_ROOT MINIMAL_CONFIG MINIMAL_CACHE MINIMAL_STATE MINIMAL_RUNTIME

# Unit names and lifecycle ownership are scoped to the compositor instance.
_minimal_instance=${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-default}}
_safe_inst="${_minimal_instance//[^a-zA-Z0-9_-]/_}"
MINIMAL_SERVICE_PREFIX="minimal-${_safe_inst}"
# User preferences/cache are shared; process ownership is per compositor.
_base_runtime="${XDG_RUNTIME_DIR:-$MINIMAL_CACHE}/minimal"
if [[ $_safe_inst != default ]]; then
    MINIMAL_RUNTIME="$_base_runtime/sessions/${_safe_inst}"
else
    MINIMAL_RUNTIME="$_base_runtime"
fi
export MINIMAL_RUNTIME
unset _minimal_instance _safe_inst _base_runtime
export MINIMAL_SERVICE_PREFIX
