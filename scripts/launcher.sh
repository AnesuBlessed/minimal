#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
# Use logical monitor height to keep the bottom panel usable on small screens.
geometry=$(hyprctl -j monitors 2>/dev/null | jq -r '
    (map(select(.focused)) | first) // empty |
    [(.name), (if (.transform % 2) == 1 then .width else .height end) / .scale] | @tsv' 2>/dev/null) || geometry=''
pref_file="$MINIMAL_STATE/launcher.pref"
preferred="${MINIMAL_LAUNCHER:-}"
if [[ -z "$preferred" && -r "$pref_file" ]]; then
    preferred=$(head -n 1 "$pref_file" | tr -d '[:space:]')
fi
# Default to quickshell when unconfigured to preserve test compliance;
# user state in launcher.pref or MINIMAL_LAUNCHER selects fuzzel.
preferred="${preferred:-quickshell}"

use_quickshell=false
if [[ ${1:-} == "--quickshell" ]]; then
    use_quickshell=true
    shift
elif [[ ${1:-} == "--fuzzel" || ${1:-} == "--fallback" ]]; then
    use_quickshell=false
    shift
elif [[ "$preferred" == "quickshell" && $# == 0 ]] && command -v quickshell >/dev/null 2>&1; then
    use_quickshell=true
fi

if [[ "$use_quickshell" == true ]] && command -v quickshell >/dev/null 2>&1; then
    export MINIMAL_LAUNCHER_OUTPUT="${geometry%%$'\t'*}"
    for theme in Tela-circle-dracula Papirus-Dark breeze-dark Adwaita hicolor; do
        if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/icons/$theme" || -d "/usr/share/icons/$theme" ]]; then
            export QS_ICON_THEME="$theme"
            break
        fi
    done
    exec "$MINIMAL_ROOT/scripts/popup.sh" launcher quickshell -n -p "$MINIMAL_ROOT/quickshell/launcher/shell.qml"
fi
args=(--config "$MINIMAL_ROOT/fuzzel/fuzzel.ini")
if [[ -n $geometry ]]; then
    IFS=$'\t' read -r output height <<< "$geometry"
    if [[ $height =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        height=${height%.*}
        lines=8
        # Leave room around the panel even on a small or heavily scaled display.
        ((height >= 500)) || lines=5
        args+=(--output "$output" --anchor bottom --y-margin 0 --lines "$lines")
    fi
fi
if [[ ! -d "${XDG_DATA_HOME:-$HOME/.local/share}/icons/Tela-circle-dracula" && ! -d /usr/share/icons/Tela-circle-dracula ]]; then
    for theme in Papirus-Dark breeze-dark Adwaita hicolor; do
        if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/icons/$theme" || -d "/usr/share/icons/$theme" ]]; then
            args+=(--icon-theme "$theme")
            break
        fi
    done
fi
"$MINIMAL_ROOT/scripts/popup.sh" launcher fuzzel "${args[@]}" "$@"
exit 0
