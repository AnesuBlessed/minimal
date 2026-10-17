#!/usr/bin/env python3
"""Dynamically parse hypr/keybinds.lua for Quickshell, Fuzzel, and Waybar."""
import html
import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(os.environ.get("MINIMAL_ROOT") or Path(__file__).resolve().parent.parent)
KEYBINDS_LUA = ROOT / "hypr/keybinds.lua"

MOD_NAMES = {
    "SUPER": "Super",
    "SHIFT": "Shift",
    "CTRL": "Ctrl",
    "CONTROL": "Ctrl",
    "ALT": "Alt",
}

KEY_NAMES = {
    "escape": "Esc",
    "return": "Enter",
    "backspace": "BackSpace",
    "space": "Space",
    "slash": "/",
    "print": "Print",
    "left": "←",
    "down": "↓",
    "up": "↑",
    "right": "→",
    "mouse:272": "LMB",
    "mouse:273": "RMB",
    "mouse_down": "Scroll ↓",
    "mouse_up": "Scroll ↑",
}


def describe_action(action_expr: str, comment: str = ""):
    """Return (category, icon, title, subtitle, cmd_list) for a Lua action expression."""
    a = action_expr.strip()
    if "window.close" in a or "killactive" in a:
        return ("Windows", "󰅖", comment or "Close Active Window", "Gracefully close focused window", ["hyprctl", "dispatch", "hl.dsp.window.close()"])
    if "window.float" in a or "togglefloating" in a:
        return ("Windows", "󰙀", comment or "Toggle Floating", "Switch window between tiled and floating", ["hyprctl", "dispatch", 'hl.dsp.window.float({ action = "toggle" })'])
    if "window.fullscreen" in a or '"fullscreen"' in a:
        return ("Windows", "󰊓", comment or "Fullscreen Window", "Toggle fullscreen on focused window", ["hyprctl", "dispatch", "hl.dsp.window.fullscreen()"])
    if "dsp.focus" in a and "direction" in a:
        return ("Windows", "󰁌", comment or "Focus Window", "Move focus in arrow direction", [])
    if "window.move" in a and "direction" in a:
        return ("Windows", "󰆾", comment or "Move Window Directionally", "Move tiled window in arrow direction", [])
    if "resizeactive" in a or ("window.resize" in a and "relative" in a):
        return ("Windows", "󰁁", comment or "Resize Active Window", "Resize focused window in arrow direction", [])
    if "window.drag" in a or "window.resize" in a:
        return ("Windows", "󰍽", comment or "Move / Resize with Mouse", "Hold modifier and drag with mouse buttons", [])
    if "dsp.focus" in a and "workspace = i" in a:
        return ("Workspace", "󰧨", comment or "Switch Workspace", "Jump directly to numbered workspace", [])
    if "window.move" in a and "workspace = i" in a:
        return ("Workspace", "󰆾", comment or "Move Window to Workspace", "Send active window to numbered workspace", [])
    if "toggle_special" in a:
        m = re.search(r'toggle_special\("([^"]+)"\)', a)
        sp = m.group(1) if m else "pocket"
        return ("Workspace", "󰘔", comment or f"Toggle {sp.capitalize()} Scratchpad", f"Toggle special {sp} scratchpad overlay", ["hyprctl", "dispatch", f'hl.dsp.workspace.toggle_special("{sp}")'])
    if 'workspace = "special:' in a:
        m = re.search(r'workspace = "(special:[^"]+)"', a)
        sp = m.group(1) if m else "special:pocket"
        return ("Workspace", "󰞒", comment or "Move to Scratchpad", f"Send active window to {sp}", ["hyprctl", "dispatch", f'hl.dsp.window.move({{ workspace = "{sp}" }})'])
    if "workspace = \"e+1\"" in a or "workspace = \"e-1\"" in a:
        return ("Workspace", "󰹑", comment or "Cycle Workspaces", "Scroll through active workspaces", [])

    # Script & command bindings
    if 'paths.script("terminal.sh")' in a:
        return ("Apps", "󰆍", comment or "Terminal (Foot)", "Launch fast Foot client terminal", [str(ROOT / "scripts/terminal.sh")])
    if 'paths.script("launcher.sh")' in a:
        return ("Apps", "󰀻", comment or "Application Launcher", "Open bottom Quickshell application launcher", [str(ROOT / "scripts/launcher.sh")])
    if 'paths.script("open-app.sh")' in a:
        m = re.search(r'open-app\.sh"\)\s*\.\.\s*"\s*([a-z]+)"', a)
        role = m.group(1) if m else "app"
        role_map = {
            "browser": ("Apps", "󰈹", "Web Browser", "Launch default web browser"),
            "files": ("Apps", "󰉋", "File Manager", "Open file manager"),
            "network": ("System", "󰖩", "Network Settings", "Open network connection manager"),
            "bluetooth": ("System", "󰂯", "Bluetooth Settings", "Open Bluetooth device manager"),
            "audio": ("System", "󰕾", "Audio Mixer", "Open PipeWire / PulseAudio volume mixer"),
        }
        cat, icon, title, sub = role_map.get(role, ("Apps", "󰀻", f"Open {role.capitalize()}", f"Launch {role} application"))
        return (cat, icon, comment or title, sub, [str(ROOT / "scripts/open-app.sh"), role])
    if 'paths.script("clipboard.sh")' in a:
        return ("Apps", "󰅌", comment or "Clipboard History", "Browse, search, and manage clipboard", [str(ROOT / "scripts/clipboard.sh")])
    if 'paths.script("wallchange.sh")' in a:
        if "--random" in a:
            return ("Apps", "󰸉", comment or "Random Wallpaper", "Cycle to a random local wallpaper", [str(ROOT / "scripts/wallchange.sh"), "--random"])
        return ("Apps", "󰸉", comment or "Wallpaper Picker", "Open wallpaper carousel & web search", [str(ROOT / "scripts/wallchange.sh")])
    if 'paths.script("usb-menu.sh")' in a:
        return ("Apps", "󱊞", comment or "USB Drive Menu", "Browse or safely unmount removable drives", [str(ROOT / "scripts/usb-menu.sh")])
    if 'paths.script("keybinds.sh")' in a:
        return ("Apps", "󰌌", comment or "Keybind Cheat-Sheet", "Toggle this interactive shortcut reference", [])
    if "hyprctl reload" in a and "waybar.sh" in a:
        return ("System", "󰑓", comment or "Reload Desktop & Bar", "Reload Hyprland config and Waybar in place", ["bash", "-c", f'hyprctl reload && "{ROOT / "scripts/waybar.sh"}" --reload'])
    if 'paths.script("powermenu.sh")' in a:
        return ("System", "󰐥", comment or "Power Menu", "Open wlogout session power menu", [str(ROOT / "scripts/powermenu.sh")])
    if 'paths.script("lock.sh")' in a:
        return ("System", "󰌾", comment or "Lock Screen", "Lock session immediately with Hyprlock", [str(ROOT / "scripts/lock.sh")])
    if 'paths.script("notifications.sh")' in a:
        m = re.search(r'notifications\.sh"\)\s*\.\.\s*"\s*([a-z-]+)"', a)
        subcmd = m.group(1) if m else "dismiss"
        notif_map = {
            "dismiss": ("Dismiss Notification", "Dismiss most recent desktop notification"),
            "dismiss-all": ("Dismiss All Notifications", "Clear all active desktop notifications"),
            "restore": ("Recall Notification", "Restore last dismissed notification from history"),
            "dnd": ("Toggle Do Not Disturb", "Silence or resume desktop notifications"),
        }
        title, sub = notif_map.get(subcmd, (f"Notifications ({subcmd})", f"Run notifications.sh {subcmd}"))
        icon = "󰂛" if subcmd == "dnd" else "󰂚"
        return ("System", icon, comment or title, sub, [str(ROOT / "scripts/notifications.sh"), subcmd])
    if 'paths.script("screenshot.sh")' in a:
        m = re.search(r'screenshot\.sh"\)\s*\.\.\s*"\s*([a-z-]+)"', a)
        mode = m.group(1) if m else "region"
        shot_map = {
            "region": ("󰹑", "Region Screenshot", "Capture selected screen region to clipboard"),
            "edit": ("󰏫", "Annotate Screenshot", "Capture region and open in Satty editor"),
            "full": ("󰍹", "Full Screen Screenshot", "Capture entire display to clipboard"),
        }
        icon, title, sub = shot_map.get(mode, ("󰹑", f"Screenshot ({mode})", f"Capture screenshot ({mode})"))
        return ("Media", icon, comment or title, sub, [str(ROOT / "scripts/screenshot.sh"), mode])
    if 'paths.script("media.sh")' in a:
        m = re.search(r'media\.sh"\)\s*\.\.\s*"\s*([^"]+)"', a)
        arg = m.group(1).strip() if m else ""
        if arg.startswith("volume"):
            return ("Media", "󰕾", comment or "Volume Up / Down / Mute", "PipeWire audio control with Mako progress OSD", [])
        if arg.startswith("mic"):
            return ("Media", "󰍬", comment or "Microphone Mute", "Toggle default audio input mute with OSD", [])
        if arg.startswith("brightness"):
            return ("Media", "󰃠", comment or "Screen Brightness", "Backlight adjustment with safe 1% minimum", [])
    if "playerctl" in a:
        if "play-pause" in a:
            return ("Media", "󰐎", comment or "Play / Pause Media", "Toggle active MPRIS media player", ["playerctl", "play-pause"])
        if "next" in a or "previous" in a:
            return ("Media", "󰒭", comment or "Next / Previous Track", "Skip tracks in active media player", [])

    # Generic fallback for any custom user bind added to keybinds.lua
    m_exec = re.search(r'exec_cmd\((.+)\)', a)
    if m_exec:
        raw_cmd = m_exec.group(1).replace('paths.script("', str(ROOT / "scripts") + '/').replace('")', '"').replace("..", "")
        clean_title = comment or re.sub(r'["\']', "", raw_cmd).split("/")[-1].strip()
        return ("Apps", "󰌌", clean_title, f"Custom command: {clean_title}", ["bash", "-c", raw_cmd.strip('"\' ')])
    return ("Windows", "󰌌", comment or "Custom Action", a, [])


def parse_combo(combo_expr: str, main_mod: str, loop_range: str = ""):
    """Convert a Lua combo expression into a list of keycap strings."""
    expr = combo_expr.strip()
    expr = re.sub(r'\bmainMod\b', f'"{main_mod}"', expr)
    if loop_range:
        expr = re.sub(r'\bi\b', f'"{loop_range}"', expr)
    parts = [p.strip().strip('"\'') for p in expr.split("..")]
    joined = "".join(parts)
    tokens = [t.strip() for t in joined.split("+") if t.strip()]
    keys = []
    for tok in tokens:
        upper = tok.upper()
        if upper in MOD_NAMES:
            keys.append(MOD_NAMES[upper])
        elif tok.lower() in KEY_NAMES:
            keys.append(KEY_NAMES[tok.lower()])
        elif len(tok) == 1:
            keys.append(tok.upper())
        else:
            keys.append(tok)
    return keys


def split_top_level_args(expr: str):
    """Split a Lua argument list on top-level commas, respecting quotes and nested ()/{}/[]."""
    args = []
    cur = []
    depth = 0
    in_quote = None
    escape = False
    for ch in expr:
        if escape:
            cur.append(ch)
            escape = False
            continue
        if in_quote:
            cur.append(ch)
            if ch == "\\":
                escape = True
            elif ch == in_quote:
                in_quote = None
            continue
        if ch in ('"', "'"):
            in_quote = ch
            cur.append(ch)
        elif ch in "({[":
            depth += 1
            cur.append(ch)
        elif ch in ")}]":
            depth = max(0, depth - 1)
            cur.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        args.append("".join(cur).strip())
    return args


def parse_keybinds(lua_path: Path = KEYBINDS_LUA):
    text = lua_path.read_text(encoding="utf-8")
    main_mod = "SUPER"
    m_mod = re.search(r'local\s+mainMod\s*=\s*"([^"]+)"', text)
    if m_mod:
        main_mod = m_mod.group(1)

    loop_range = ""
    raw_entries = []

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        m_for = re.match(r'for\s+i\s*=\s*(\d+)\s*,\s*(\d+)\s+do', stripped)
        if m_for:
            loop_range = f"{m_for.group(1)} … {m_for.group(2)}"
            continue
        if stripped == "end":
            loop_range = ""
            continue
        if not stripped.startswith("hl.bind("):
            continue

        m_comment = re.search(r'\)\s*--\s*(.*)$', stripped)
        if m_comment:
            comment = m_comment.group(1).strip()
            code_part = stripped[:m_comment.start() + 1]
        else:
            comment = ""
            code_part = stripped

        inner = code_part[len("hl.bind("):].rsplit(")", 1)[0]
        args = split_top_level_args(inner)
        if len(args) < 2:
            continue
        combo_expr = args[0]
        action_expr = args[1]

        # Skip internal laptop lid switch hardware events or redundant XF86 duplicates
        if "switch:" in combo_expr or "XF86PowerOff" in combo_expr:
            continue

        keys = parse_combo(combo_expr, main_mod, loop_range)
        cat, icon, title, subtitle, cmd = describe_action(action_expr, comment)
        raw_entries.append({
            "category": cat,
            "icon": icon,
            "title": title,
            "subtitle": subtitle,
            "keys": keys,
            "cmd": cmd,
        })

    # Group consecutive or identical (category, title) entries into combined keycaps
    grouped = []
    by_key = {}
    for entry in raw_entries:
        # Don't merge XF86AudioPlay with Super + Space
        is_xf86 = any(k.startswith("XF86") for k in entry["keys"])
        if is_xf86 and entry["title"] in ("Play / Pause Media", "Next / Previous Track"):
            continue
        sig = (entry["category"], entry["title"])
        if sig in by_key:
            existing = by_key[sig]
            prefix = existing["keys"][:-1]
            last_new = entry["keys"][-1]
            if entry["keys"][:-1] == prefix:
                if last_new not in existing["_last_keys"]:
                    existing["_last_keys"].append(last_new)
                    if set(existing["_last_keys"]) == {"←", "→", "↑", "↓"}:
                        existing["keys"] = prefix + ["← ↓ ↑ →"]
                    elif existing["keys"][0].startswith("XF86Audio"):
                        existing["keys"] = ["XF86Audio", "Vol / Mute"]
                    elif existing["keys"][0].startswith("XF86MonBrightness"):
                        existing["keys"] = ["XF86MonBrightness", "Up / Down"]
                    else:
                        existing["keys"] = prefix + [" / ".join(existing["_last_keys"])]
            continue
        entry["_last_keys"] = [entry["keys"][-1]] if entry["keys"] else []
        by_key[sig] = entry
        grouped.append(entry)

    for item in grouped:
        item.pop("_last_keys", None)

    # Order by category in UI order: Apps, Windows, Workspace, System, Media
    order = {"Apps": 0, "Windows": 1, "Workspace": 2, "System": 3, "Media": 4}
    grouped.sort(key=lambda x: order.get(x["category"], 99))
    return grouped


def format_waybar_tooltip(entries):
    lines = [
        "<b>󰌌  Keyboard Shortcuts</b>",
        "<span alpha='75%'>────────────────────────────────────────</span>",
    ]
    per_cat = {}
    for item in entries:
        if any(k.startswith("XF86") for k in item["keys"]):
            continue
        cat = item["category"]
        if per_cat.get(cat, 0) >= 3:
            continue
        per_cat[cat] = per_cat.get(cat, 0) + 1
        combo = " + ".join(item["keys"])
        padded = html.escape(combo).ljust(22)
        title = html.escape(item["title"])
        lines.append(f"<tt><b>{padded}</b></tt> {title}")
    lines.append("<span alpha='75%'>────────────────────────────────────────</span>")
    lines.append(f"<i>󰳽 Click or press <b>Super + /</b> to search all {len(entries)} shortcuts</i>")
    return "\n".join(lines)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--json"
    entries = parse_keybinds()
    if mode == "--json":
        print(json.dumps(entries))
    elif mode == "--dmenu":
        for item in entries:
            combo = " + ".join(item["keys"])
            print(f"{combo:<24} │ {item['title']}")
    elif mode == "--waybar":
        print(json.dumps({
            "text": "󰌌",
            "tooltip": format_waybar_tooltip(entries),
        }))
    else:
        raise SystemExit(f"Usage: {sys.argv[0]} [--json|--dmenu|--waybar]")


if __name__ == "__main__":
    main()
