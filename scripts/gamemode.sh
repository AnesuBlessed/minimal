#!/usr/bin/env bash
set -euo pipefail
value=$(hyprctl -j getoption animations:enabled | jq -r '.bool // .int // false')
case $value in true|1) enabled=0;; *) enabled=1;; esac
hyprctl --batch "keyword animations:enabled $enabled; keyword decoration:shadow:enabled 0; keyword decoration:blur:enabled 0"
