#!/usr/bin/env python3
"""Reactive Waybar Notch status & Quickshell Notch data provider (Recording / MPRIS / Weather)."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request

ROOT = Path(os.environ.get("MINIMAL_ROOT") or Path(__file__).resolve().parent.parent)
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "minimal"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or CACHE) / "minimal"
WEATHER_CACHE = CACHE / "weather.json"
WEATHER_TTL = 1800  # 30 minutes

WMO_ICONS = {
    "113": "󰖙",  # Sunny / Clear
    "116": "󰖕",  # Partly cloudy
    "119": "󰖐",  # Cloudy
    "122": "󰖐",  # Overcast
    "143": "󰖑",  # Mist
    "176": "󰖗",  # Patchy rain
    "179": "󰖘",  # Patchy snow
    "200": "󰙾",  # Thundery outbreaks
    "227": "󰖘",  # Blowing snow
    "248": "󰖑",  # Fog
    "260": "󰖑",  # Freezing fog
    "263": "󰖗",  # Patchy light drizzle
    "266": "󰖗",  # Light drizzle
    "293": "󰖗",  # Light rain
    "296": "󰖗",  # Light rain
    "299": "󰖖",  # Moderate rain
    "302": "󰖖",  # Moderate rain
    "305": "󰖖",  # Heavy rain
    "308": "󰖖",  # Heavy rain
    "353": "󰖗",  # Light rain shower
    "386": "󰙾",  # Patchy light rain with thunder
    "389": "󰙾",  # Moderate or heavy rain with thunder
}


def run_cmd(args, timeout=2.0):
    try:
        res = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip() if res.returncode == 0 else ""
    except Exception:
        return ""


def get_recording_state():
    pidfile = RUNTIME / "recording.pid"
    if not pidfile.is_file():
        return {"active": False, "elapsed": "", "path": ""}
    try:
        parts = pidfile.read_text().strip().split("\n")
        meta = parts[0].split()
        pid = int(meta[0])
        expected_start = meta[1] if len(meta) > 1 else ""
        rec_path = parts[1] if len(parts) > 1 else ""
        stat_path = Path(f"/proc/{pid}/stat")
        if not stat_path.is_file():
            return {"active": False, "elapsed": "", "path": ""}
        stat_after = stat_path.read_text().rsplit(")", 1)[-1].split()
        if expected_start and stat_after[19] != expected_start:
            return {"active": False, "elapsed": "", "path": ""}
        started_at = int(meta[2]) if len(meta) > 2 else int(pidfile.stat().st_mtime)
        secs = max(0, int(time.time()) - started_at)
        mins, rem = divmod(secs, 60)
        return {"active": True, "elapsed": f"{mins:02d}:{rem:02d}", "path": rec_path}
    except Exception:
        return {"active": False, "elapsed": "", "path": ""}


def format_duration(seconds):
    if seconds <= 0:
        return "0:00"
    mins, secs = divmod(int(seconds), 60)
    return f"{mins}:{secs:02d}"


def get_media_state():
    if not shutil.which("playerctl"):
        return {"active": False, "status": "Stopped"}
    status = run_cmd(["playerctl", "status"], timeout=1.2)
    if status not in ("Playing", "Paused"):
        return {"active": False, "status": "Stopped"}
    sep = "\x1f"
    fmt = sep.join([
        "{{playerName}}",
        "{{title}}",
        "{{artist}}",
        "{{album}}",
        "{{mpris:artUrl}}",
        "{{position}}",
        "{{mpris:length}}",
    ])
    raw = run_cmd(["playerctl", "metadata", "--format", fmt], timeout=1.2)
    parts = (raw.split(sep) + [""] * 7)[:7]
    player, title, artist, album, art_url, pos_us, len_us = parts
    try:
        pos_sec = float(pos_us) / 1_000_000.0 if pos_us else 0.0
    except ValueError:
        pos_sec = 0.0
    try:
        len_sec = float(len_us) / 1_000_000.0 if len_us else 0.0
    except ValueError:
        len_sec = 0.0
    return {
        "active": True,
        "status": status,
        "player": player or "Media",
        "title": title or "Unknown Track",
        "artist": artist or "",
        "album": album or "",
        "artUrl": art_url or "",
        "position": pos_sec,
        "length": len_sec,
        "positionStr": format_duration(pos_sec),
        "lengthStr": format_duration(len_sec),
    }


def fetch_weather_network():
    CACHE.mkdir(parents=True, exist_ok=True)
    url = os.environ.get("MINIMAL_WEATHER_URL", "https://wttr.in/?format=j1")
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
    with urllib.request.urlopen(req, timeout=4.5) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    cur = (data.get("current_condition") or [{}])[0]
    area = (data.get("nearest_area") or [{}])[0]
    city = ((area.get("areaName") or [{}])[0].get("value") or "").strip()
    country = ((area.get("country") or [{}])[0].get("value") or "").strip()
    location = f"{city}, {country}".strip(", ") or "Local Weather"
    code = str(cur.get("weatherCode") or "113")
    icon = WMO_ICONS.get(code, "󰖐")
    desc = ((cur.get("weatherDesc") or [{}])[0].get("value") or "Clear").strip()
    forecast = []
    for day in (data.get("weather") or [])[:3]:
        hourly = day.get("hourly") or [{}]
        mid = hourly[len(hourly) // 2] if hourly else {}
        d_code = str(mid.get("weatherCode") or "113")
        d_desc = ((mid.get("weatherDesc") or [{}])[0].get("value") or desc).strip()
        forecast.append({
            "date": day.get("date", ""),
            "maxC": str(day.get("maxtempC", "--")),
            "minC": str(day.get("mintempC", "--")),
            "condition": d_desc,
            "icon": WMO_ICONS.get(d_code, "󰖐"),
        })
    parsed = {
        "updatedAt": int(time.time()),
        "location": location,
        "tempC": str(cur.get("temp_C", "--")),
        "feelsLikeC": str(cur.get("FeelsLikeC", "--")),
        "condition": desc,
        "icon": icon,
        "humidity": str(cur.get("humidity", "--")),
        "windKmph": str(cur.get("windspeedKmph", "--")),
        "forecast": forecast,
    }
    tmp = CACHE / "weather.json.tmp"
    tmp.write_text(json.dumps(parsed))
    tmp.replace(WEATHER_CACHE)
    return parsed


def get_weather_state(force_refresh=False):
    cached = None
    if WEATHER_CACHE.is_file():
        try:
            cached = json.loads(WEATHER_CACHE.read_text())
        except Exception:
            cached = None
    now = int(time.time())
    if force_refresh:
        try:
            return fetch_weather_network()
        except Exception:
            if cached:
                return cached
    elif cached and (now - int(cached.get("updatedAt", 0)) < WEATHER_TTL):
        return cached
    else:
        # Refresh synchronously if fast test URL or spawn detached background refresh
        if os.environ.get("MINIMAL_WEATHER_SYNC") == "1":
            try:
                return fetch_weather_network()
            except Exception:
                pass
        else:
            try:
                subprocess.Popen(
                    [sys.executable, str(Path(__file__).resolve()), "--refresh-weather"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except Exception:
                pass
        if cached:
            return cached
    return {
        "updatedAt": 0,
        "location": "Weather",
        "tempC": "--",
        "feelsLikeC": "--",
        "condition": "Click to refresh",
        "icon": "󰖐",
        "humidity": "--",
        "windKmph": "--",
        "forecast": [],
    }


def waybar_payload():
    rec = get_recording_state()
    med = get_media_state()
    wea = get_weather_state(force_refresh=False)
    weather_summary = f"{wea['icon']} {wea['tempC']}°C · {wea['condition']} ({wea['location']})"

    if rec["active"]:
        return {
            "text": f"󰑊 REC {rec['elapsed']}",
            "class": "recording",
            "tooltip": f"Screen Recording Active ({rec['elapsed']})\nFile: {rec['path']}\n\n{weather_summary}\nClick to open Notch · Super+Shift+R to stop",
        }
    if med["active"]:
        icon = "󰐊" if med["status"] == "Playing" else "󰏤"
        label = f"{med['artist']} — {med['title']}" if med["artist"] else med["title"]
        if len(label) > 28:
            label = label[:27] + "…"
        return {
            "text": f"{icon} {label}  {wea['icon']} {wea['tempC']}°",
            "class": "playing" if med["status"] == "Playing" else "paused",
            "tooltip": (
                f"{med['title']}\n"
                + (f"by {med['artist']}\n" if med["artist"] else "")
                + f"{med['positionStr']} / {med['lengthStr']} ({med['player']})\n\n"
                + f"{weather_summary}\n"
                + "Click: Open Dynamic Notch · Middle: Play/Pause · Right: Next"
            ),
        }
    temp_display = f"{wea['tempC']}°C" if wea["tempC"] != "--" else "Notch"
    return {
        "text": f"{wea['icon']} {temp_display}",
        "class": "weather",
        "tooltip": (
            f"{wea['location']}\n"
            f"{wea['icon']} {wea['condition']} · {wea['tempC']}°C (Feels like {wea['feelsLikeC']}°C)\n"
            f"Humidity: {wea['humidity']}% · Wind: {wea['windKmph']} km/h\n\n"
            "Click to open Dynamic Notch (Media & 3-Day Forecast)"
        ),
    }


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--waybar"
    if mode == "--refresh-weather":
        try:
            fetch_weather_network()
            subprocess.run(["pkill", "-RTMIN+9", "waybar"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            sys.exit(1)
        return
    if mode == "--popup-json":
        print(json.dumps({
            "recording": get_recording_state(),
            "media": get_media_state(),
            "weather": get_weather_state(force_refresh=False),
        }))
        return
    print(json.dumps(waybar_payload()))


if __name__ == "__main__":
    main()
