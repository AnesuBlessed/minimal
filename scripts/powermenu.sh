#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — POWER MENU (WLOGOUT + ROFI FALLBACK)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

# Toggle: close if already open
if pgrep -u "$(id -u)" -x "wlogout" >/dev/null 2>&1; then
    pkill -u "$(id -u)" -x "wlogout"
    exit 0
fi

if command -v wlogout >/dev/null 2>&1; then
    wLayout="$MINIMAL_ROOT/wlogout/layout"
    wStyle="$MINIMAL_ROOT/wlogout/style.css"
    
    # JSON-encode the resolved action and CSS path; checkout paths may contain spaces.
    tmpLayout=$(mktemp --suffix=.json)
    tmpStyle=$(mktemp --suffix=.css)
    trap 'rm -f -- "$tmpLayout" "$tmpStyle"' EXIT
    python3 - "$wLayout" "$wStyle" "$tmpLayout" "$tmpStyle" <<'PYCODE'
import json, os, pathlib, shlex, sys
layout, css, out_layout, out_css = map(pathlib.Path, sys.argv[1:])
root = os.environ['MINIMAL_ROOT']
text = layout.read_text()
# Wlogout consumes consecutive JSON objects rather than a JSON array.
decoder = json.JSONDecoder()
objects = []
while text.strip():
    item, end = decoder.raw_decode(text.lstrip())
    text = text.lstrip()[end:]
    if item['label'] == 'lock':
        item['action'] = shlex.quote(root + '/scripts/lock.sh')
    elif item['label'] in ('suspend', 'hibernate'):
        # Lock first so the session is never resumed unlocked.
        item['action'] = f"{shlex.quote(root + '/scripts/lock.sh')} & sleep 1; systemctl {item['label']}"
    objects.append(json.dumps(item))
out_layout.write_text('\n'.join(objects) + '\n')
style = css.read_text()
for name in ('lock', 'logout', 'suspend', 'hibernate', 'shutdown', 'reboot'):
    relative = 'icons/' + name + '_white.png'
    style = style.replace(json.dumps(relative), json.dumps(root + '/wlogout/' + relative))
out_css.write_text(style)
PYCODE
    wlogout -b 3 -c 0 -r 0 -m 24 --layout "$tmpLayout" --css "$tmpStyle" --protocol layer-shell
    exit $?

fi

# Fallback: Clean Rofi menu (toggles closed if already open; switches if another rofi is open)
uid="${UID:-$(id -u)}"
if pgrep -u "$uid" -f "rofi.*selector\.rasi" >/dev/null 2>&1; then
    pkill -u "$uid" -f "rofi.*selector\.rasi"
    exit 0
fi
pkill -u "$uid" -x rofi 2>/dev/null || true
entries="󰌾  Lock\n󰤄  Suspend\n󰋊  Hibernate\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown"
chosen=$(printf '%b' "$entries" | rofi -dmenu -theme "$MINIMAL_ROOT/rofi/selector.rasi" -p "󰐥 Power: " 2>/dev/null) || exit 0

case "${chosen:-}" in
    *"Lock"*)
        "$MINIMAL_ROOT/scripts/lock.sh"
        ;;
    *"Suspend"*)
        "$MINIMAL_ROOT/scripts/lock.sh" & sleep 1
        systemctl suspend
        ;;
    *"Hibernate"*)
        "$MINIMAL_ROOT/scripts/lock.sh" & sleep 1
        systemctl hibernate
        ;;
    *"Logout"*)
        hyprctl dispatch exit
        ;;
    *"Reboot"*)
        systemctl reboot
        ;;
    *"Shutdown"*)
        systemctl poweroff
        ;;
esac
