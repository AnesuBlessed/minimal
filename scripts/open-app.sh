#!/usr/bin/env bash
# Launch the first available application for a role (browser, files, network,
# audio). Minimal must not assume any particular app is installed: a missing
# app produces a notification instead of a silently dead keybind. Exits at once.
set -euo pipefail

role=${1:-}

case $role in
    browser)   candidates=("${BROWSER:-}" firefox librewolf zen-browser chromium google-chrome-stable brave falkon epiphany) ;;
    files)     candidates=(dolphin thunar nautilus pcmanfm pcmanfm-qt nemo caja) ;;
    network)   candidates=(nm-connection-editor iwgtk nmtui-foot) ;;
    bluetooth) candidates=(blueman-manager overskride blueberry) ;;
    audio)     candidates=(pavucontrol pwvucontrol helvum) ;;
    *) printf 'Usage: %s browser|files|network|bluetooth|audio\n' "${0##*/}" >&2; exit 2 ;;
esac

for app in "${candidates[@]}"; do
    [[ -n $app ]] || continue
    # $BROWSER may carry arguments; split words without pathname expansion.
    read -r -a cmd <<< "$app"
    command -v "${cmd[0]}" >/dev/null 2>&1 || continue
    setsid -f "${cmd[@]}" >/dev/null 2>&1
    exit 0
done

# A browser can still be reachable through the desktop's default handler.
if [[ $role == browser ]] && command -v xdg-open >/dev/null 2>&1; then
    setsid -f xdg-open 'about:blank' >/dev/null 2>&1 && exit 0
fi

hint=${candidates[0]:-${candidates[1]}}
notify-send -a minimal -u low "No $role application found" \
    "Install one (e.g. $hint); this key will pick it up automatically." 2>/dev/null || true
exit 0
