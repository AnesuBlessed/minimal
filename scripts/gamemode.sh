#!/usr/bin/env bash
set -euo pipefail
value=$(hyprctl -j getoption animations:enabled | jq -r '.bool // .int // false')
case $value in true|1) anim_bool="false";; *) anim_bool="true";; esac
hyprctl eval "hl.config({ animations = { enabled = $anim_bool }, decoration = { shadow = { enabled = false }, blur = { enabled = false } } })" >/dev/null 2>&1 || true
