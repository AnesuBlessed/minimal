#!/usr/bin/env bash
set -euo pipefail
root=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
cargo test --locked --manifest-path "$root/native/Cargo.toml"
"$root/scripts/check.sh"
# Run GTK event tests in a private Broadway display, never on the user's desktop.
if command -v gtk4-broadwayd >/dev/null && command -v dbus-run-session >/dev/null; then
    test_dir=$(mktemp -d)
    trap 'kill "${display_pid:-}" 2>/dev/null || true; rm -rf -- "$test_dir"' EXIT
    mkdir -p "$test_dir/runtime" "$test_dir/home" "$test_dir/data" "$test_dir/cache" "$test_dir/state"
    chmod 700 "$test_dir/runtime"
    XDG_RUNTIME_DIR="$test_dir/runtime" gtk4-broadwayd :97 >"$test_dir/display.log" 2>&1 &
    display_pid=$!
    sleep 0.3
    timeout 30s env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE GTK_A11Y=none GTK_USE_PORTAL=0 GIO_USE_VFS=local XDG_CURRENT_DESKTOP=MinimalTest dbus-run-session -- env MINIMAL_ROOT="$root" HOME="$test_dir/home" \
        XDG_RUNTIME_DIR="$test_dir/runtime" XDG_CACHE_HOME="$test_dir/cache" \
        XDG_STATE_HOME="$test_dir/state" XDG_DATA_HOME="$test_dir/data" \
        GDK_BACKEND=broadway BROADWAY_DISPLAY=:97 \
        "$root/build/minimal-carousel" --self-test
else
    echo 'SKIP: isolated GTK tests (gtk4-broadwayd/dbus-run-session unavailable)'
fi
