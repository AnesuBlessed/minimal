#!/usr/bin/env bash
# Build native helpers without changing the running desktop.
set -euo pipefail
root=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
command -v cargo >/dev/null || { echo 'Install Rust/Cargo to build Minimal.' >&2; exit 1; }
command -v cc >/dev/null || { echo 'Install a C compiler to build the carousel.' >&2; exit 1; }
pkg-config --exists gtk4 json-c || { echo 'Install GTK4, json-c and pkg-config development files.' >&2; exit 1; }
mkdir -p "$root/build"
cargo build --release --locked --manifest-path "$root/native/Cargo.toml"
# Build both before replacing either installed executable.
cc -O2 -Wall -Wextra -Werror -o "$root/build/minimal-carousel.new" "$root/native/carousel.c" $(pkg-config --cflags --libs gtk4 json-c) -lm
cp "$root/native/target/release/minimal" "$root/build/minimal.new"
mv -f "$root/build/minimal.new" "$root/build/minimal"
mv -f "$root/build/minimal-carousel.new" "$root/build/minimal-carousel"
printf 'Built native helpers in %s/build\n' "$root"
