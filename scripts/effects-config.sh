#!/usr/bin/env bash
# Minimal Visual Effects & Desktop Controls Helper
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p "$MINIMAL_STATE" "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_STATE/effects.lock"
flock -w 5 9 || exit 1

unit="$MINIMAL_SERVICE_PREFIX-night-light.service"

python3 - "$MINIMAL_STATE" "$unit" "${1:-get}" "${2:-}" "${3:-}" <<'PY'
import json, os, sys, subprocess, tempfile, math
from pathlib import Path

def report_error(kind, error, traceback):
    print("Could not apply setting: " + str(error), file=sys.stderr)

sys.excepthook = report_error

state_dir, night_light_unit, action, key, value = sys.argv[1:6]
state = Path(state_dir)
json_file = state / "effects.json"
lua_file = state / "effects.lua"
pref_file = state / "launcher.pref"

def is_service_active(unit_name):
    try:
        res = subprocess.run(["systemctl", "--user", "is-active", "--quiet", unit_name], timeout=5)
        return res.returncode == 0
    except Exception:
        return False

def stop_night_light():
    if is_service_active(night_light_unit):
        subprocess.run(["systemctl", "--user", "stop", night_light_unit],
                       stdout=subprocess.DEVNULL, timeout=10, check=True)

def get_hypr_bool(option):
    try:
        res = subprocess.run(["hyprctl", "-j", "getoption", option], capture_output=True, text=True, timeout=5)
        if res.returncode == 0:
            data = json.loads(res.stdout)
            return bool(data.get("bool") or data.get("int", 0))
    except Exception:
        pass
    return False

def read_state():
    defaults = {
        "blur": get_hypr_bool("decoration:blur:enabled"),
        "animations": get_hypr_bool("animations:enabled"),
        "night_light": is_service_active(night_light_unit),
        "temperature": 4500,
        "launcher": "quickshell"
    }
    if pref_file.exists():
        try:
            val = pref_file.read_text().strip()
            if val in ("fuzzel", "quickshell"):
                defaults["launcher"] = val
        except Exception:
            pass
    try:
        if json_file.exists():
            data = json.loads(json_file.read_text())
            for k in ("temperature", "launcher"):
                if k in data:
                    defaults[k] = data[k]
    except Exception:
        pass
    return defaults

def write_atomic(path, text):
    fd, tmp = tempfile.mkstemp(dir=state)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)

if action not in ("get", "set"):
    sys.exit("Expected get or set")
if action == "set":
    if key not in ('blur', 'animations', 'night_light', 'launcher', 'temperature'): sys.exit("Unknown setting: " + key)
    if key in ('blur', 'animations', 'night_light') and value.lower() not in ("true", "false", "1", "0", "yes", "no"): sys.exit("Expected a boolean value")
    if key == "launcher" and value not in ("fuzzel", "quickshell"): sys.exit("Unknown launcher")
    if key == "temperature":
        try: number = int(value)
        except ValueError: sys.exit("Temperature must be an integer")
        if not 2000 <= number <= 6500: sys.exit("Temperature must be between 2000 and 6500")

data = read_state()

if action == "get":
    print(json.dumps(data))
    sys.exit(0)

if action == "set":
    if key == "blur":
        val_bool = (value.lower() in ("true", "1", "yes"))
        data["blur"] = val_bool
        lua_val = "true" if val_bool else "false"
        subprocess.run(["hyprctl", "eval", f"hl.config({{ decoration = {{ blur = {{ enabled = {lua_val} }} }} }})"], stdout=subprocess.DEVNULL, timeout=10, check=True)
    elif key == "animations":
        val_bool = (value.lower() in ("true", "1", "yes"))
        data["animations"] = val_bool
        lua_val = "true" if val_bool else "false"
        subprocess.run(["hyprctl", "eval", f"hl.config({{ animations = {{ enabled = {lua_val} }} }})"], stdout=subprocess.DEVNULL, timeout=10, check=True)
    elif key == "launcher":
        if value in ("fuzzel", "quickshell"):
            data["launcher"] = value
            write_atomic(pref_file, value + "\n")
    elif key == "night_light":
        val_bool = (value.lower() in ("true", "1", "yes"))
        data["night_light"] = val_bool
        if val_bool:
            temp = data.get("temperature", 4500)
            stop_night_light()
            subprocess.run([
                "systemd-run", "--user", "--quiet", "--collect",
                f"--unit={night_light_unit}",
                "--property=PartOf=graphical-session.target",
                "--property=Type=exec",
                f"--setenv=WAYLAND_DISPLAY={os.environ.get('WAYLAND_DISPLAY', '')}",
                f"--setenv=HYPRLAND_INSTANCE_SIGNATURE={os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')}",
                "hyprsunset", "-t", str(temp)
            ], stdout=subprocess.DEVNULL, timeout=10, check=True)
        else:
            stop_night_light()
    elif key == "temperature":
        try:
            temp = int(value)
            temp = max(2000, min(6500, temp))
            data["temperature"] = temp
            if data["night_light"]:
                stop_night_light()
                subprocess.run([
                    "systemd-run", "--user", "--quiet", "--collect",
                    f"--unit={night_light_unit}",
                    "--property=PartOf=graphical-session.target",
                "--property=Type=exec",
                    f"--setenv=WAYLAND_DISPLAY={os.environ.get('WAYLAND_DISPLAY', '')}",
                    f"--setenv=HYPRLAND_INSTANCE_SIGNATURE={os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')}",
                    "hyprsunset", "-t", str(temp)
                ], stdout=subprocess.DEVNULL, timeout=10, check=True)
        except ValueError:
            pass

    # Save effects Lua
    b_str = "true" if data["blur"] else "false"
    a_str = "true" if data["animations"] else "false"
    lua_content = f"""-- Generated by Minimal effects-config.sh
hl.config({{
    decoration = {{
        blur = {{
            enabled = {b_str},
        }},
    }},
    animations = {{
        enabled = {a_str},
    }},
}})
"""
    if key in ("blur", "animations"):
        write_atomic(lua_file, lua_content)
    write_atomic(json_file, json.dumps(data, indent=2) + "\n")
    print(json.dumps(data))
PY
