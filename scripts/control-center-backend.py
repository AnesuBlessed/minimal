#!/usr/bin/env python3
"""Backend state & action dispatcher for the unified Quickshell Control Center (Wi-Fi, Bluetooth, Audio, Display)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(os.environ.get("MINIMAL_ROOT") or Path(__file__).resolve().parent.parent)
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "minimal"
RUNTIME = Path(os.environ.get("MINIMAL_RUNTIME") or (Path(os.environ.get("XDG_RUNTIME_DIR") or CACHE) / "minimal"))
SERVICE_PREFIX = os.environ.get("MINIMAL_SERVICE_PREFIX", "minimal-default")


def run_cmd(args, timeout=4.0):
    try:
        res = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)


def notify(title, body="", urgency="low"):
    if shutil.which("notify-send"):
        subprocess.run(
            ["notify-send", "-a", "minimal", "-u", urgency, title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def get_wifi_state(scan_networks=True):
    if not shutil.which("nmcli"):
        return {
            "available": False,
            "enabled": False,
            "connectedSsid": "",
            "ipAddress": "",
            "interface": "",
            "hotspotActive": False,
            "networks": [],
        }
    _, radio_out, _ = run_cmd(["nmcli", "-t", "-f", "WIFI", "radio"], timeout=2.0)
    enabled = radio_out.strip().lower() == "enabled"

    # Saved connections
    _, saved_out, _ = run_cmd(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"], timeout=2.0)
    saved_ssids = set()
    for line in saved_out.splitlines():
        parts = line.rsplit(":", 1)
        if len(parts) == 2 and "wireless" in parts[1]:
            saved_ssids.add(parts[0])

    # Active connections & IP
    _, active_out, _ = run_cmd(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"], timeout=2.0)
    connected_ssid = ""
    wifi_dev = ""
    hotspot_active = False
    for line in active_out.splitlines():
        parts = line.split(":")
        if len(parts) >= 3 and "wireless" in parts[1]:
            connected_ssid = parts[0]
            wifi_dev = parts[2]
            if parts[0].lower() == "hotspot":
                hotspot_active = True
            break

    ip_addr = ""
    if wifi_dev:
        _, dev_out, _ = run_cmd(["nmcli", "-t", "-f", "IP4.ADDRESS", "device", "show", wifi_dev], timeout=2.0)
        for line in dev_out.splitlines():
            if ":" in line:
                ip_addr = line.split(":", 1)[1].split("/")[0].strip()
                if ip_addr:
                    break

    networks = []
    if enabled and scan_networks:
        _, list_out, _ = run_cmd(
            ["nmcli", "-t", "-e", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"],
            timeout=3.0,
        )
        seen = {}
        for raw_line in list_out.splitlines():
            # Split unescaped colons
            fields = re.split(r"(?<!\\):", raw_line)
            if len(fields) < 4:
                continue
            in_use = fields[0].strip() == "*"
            ssid = fields[1].replace(r"\:", ":").replace(r"\\", "\\").strip()
            if not ssid:
                continue
            try:
                signal = int(fields[2].strip())
            except ValueError:
                signal = 0
            security = ":".join(fields[3:]).replace(r"\:", ":").strip()
            secured = bool(security and security != "--")
            entry = {
                "ssid": ssid,
                "signal": signal,
                "security": security if secured else "Open",
                "secured": secured,
                "inUse": in_use or (ssid == connected_ssid and bool(connected_ssid)),
                "saved": ssid in saved_ssids or in_use,
            }
            if ssid not in seen or entry["inUse"] or entry["signal"] > seen[ssid]["signal"]:
                seen[ssid] = entry
        networks = sorted(seen.values(), key=lambda n: (not n["inUse"], not n["saved"], -n["signal"], n["ssid"].lower()))

    return {
        "available": True,
        "enabled": enabled,
        "connectedSsid": connected_ssid,
        "ipAddress": ip_addr,
        "interface": wifi_dev,
        "hotspotActive": hotspot_active,
        "networks": networks,
    }


def get_bluetooth_state():
    if not shutil.which("bluetoothctl"):
        return {
            "available": False,
            "powered": False,
            "discoverable": False,
            "controller": "",
            "devices": [],
        }
    rc, show_out, _ = run_cmd(["bluetoothctl", "show"], timeout=2.0)
    if rc != 0 or "No default controller" in show_out:
        has_rfkill = False
        rfkill_blocked = False
        if shutil.which("rfkill"):
            _, rf_out, _ = run_cmd(["rfkill", "list", "bluetooth"], timeout=1.5)
            if rf_out.strip():
                has_rfkill = True
                rfkill_blocked = "Soft blocked: yes" in rf_out or "Hard blocked: yes" in rf_out
        if has_rfkill:
            return {
                "available": True,
                "powered": False,
                "discoverable": False,
                "controller": "Bluetooth (Blocked)" if rfkill_blocked else "Bluetooth (Off)",
                "devices": [],
            }
        return {
            "available": False,
            "powered": False,
            "discoverable": False,
            "controller": "No Controller",
            "devices": [],
        }
    powered = "Powered: yes" in show_out
    discoverable = "Discoverable: yes" in show_out
    alias_match = re.search(r"Alias:\s*(.+)", show_out)
    name_match = re.search(r"Name:\s*(.+)", show_out)
    ctrl_match = re.search(r"Controller\s+([0-9A-Fa-f:]{17})", show_out)
    controller = alias_match.group(1).strip() if alias_match else (name_match.group(1).strip() if name_match else "Bluetooth")
    address = ctrl_match.group(1).strip() if ctrl_match else ""

    _, paired_out, _ = run_cmd(["bluetoothctl", "devices", "Paired"], timeout=2.0)
    paired_macs = {line.split()[1] for line in paired_out.splitlines() if line.startswith("Device ") and len(line.split()) >= 2}

    _, conn_out, _ = run_cmd(["bluetoothctl", "devices", "Connected"], timeout=2.0)
    conn_macs = {line.split()[1] for line in conn_out.splitlines() if line.startswith("Device ") and len(line.split()) >= 2}

    _, trusted_out, _ = run_cmd(["bluetoothctl", "devices", "Trusted"], timeout=2.0)
    trusted_macs = {line.split()[1] for line in trusted_out.splitlines() if line.startswith("Device ") and len(line.split()) >= 2}

    _, all_out, _ = run_cmd(["bluetoothctl", "devices"], timeout=2.0)
    devices = []
    for line in all_out.splitlines():
        if not line.startswith("Device "):
            continue
        parts = line.split(" ", 2)
        if len(parts) < 3:
            continue
        mac, name = parts[1].strip(), parts[2].strip()
        is_conn = mac in conn_macs
        is_paired = mac in paired_macs or is_conn
        is_trusted = mac in trusted_macs
        battery = ""
        if is_conn:
            _, info_out, _ = run_cmd(["bluetoothctl", "info", mac], timeout=1.5)
            b_match = re.search(r"Battery Percentage:.*\((\d+)\)", info_out)
            if b_match:
                battery = b_match.group(1) + "%"
        display_name = name or mac
        if not name or re.match(r"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", display_name) or display_name.startswith("dev_"):
            info_text = info_out if is_conn else run_cmd(["bluetoothctl", "info", mac], timeout=1.0)[1]
            alias_m = re.search(r"^\s*Alias:\s*(.+)$", info_text, re.MULTILINE)
            name_m = re.search(r"^\s*Name:\s*(.+)$", info_text, re.MULTILINE)
            resolved = (alias_m.group(1).strip() if alias_m else "") or (name_m.group(1).strip() if name_m else "")
            if resolved and not re.match(r"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", resolved):
                display_name = resolved
            else:
                display_name = "Bluetooth Device"

        devices.append({
            "mac": mac,
            "name": display_name,
            "connected": is_conn,
            "paired": is_paired,
            "trusted": is_trusted,
            "battery": battery,
        })
    devices.sort(key=lambda d: (not d["connected"], not d["paired"], d["name"].lower()))
    return {
        "available": True,
        "powered": powered,
        "discoverable": discoverable,
        "controller": controller,
        "name": controller,
        "address": address,
        "devices": devices,
    }


def parse_wpctl_volume(target):
    if not shutil.which("wpctl"):
        return 0, False
    rc, out, _ = run_cmd(["wpctl", "get-volume", target], timeout=1.5)
    if rc != 0 or not out:
        return 0, False
    muted = "[MUTED]" in out
    m = re.search(r"Volume:\s*([0-9.]+)", out)
    vol = round(float(m.group(1)) * 100) if m else 0
    return vol, muted


def parse_wpctl_devices():
    sinks, sources = [], []
    if not shutil.which("wpctl"):
        return sinks, sources
    rc, out, _ = run_cmd(["wpctl", "status"], timeout=2.0)
    if rc != 0:
        return sinks, sources
    section = ""
    in_audio = False
    for line in out.splitlines():
        clean = line.replace("│", " ").replace("├", " ").replace("└", " ").replace("─", " ").strip()
        if line.startswith("Audio"):
            in_audio = True
            continue
        if line.startswith("Video") or line.startswith("Settings"):
            in_audio = False
            continue
        if not in_audio:
            continue
        if clean.startswith("Sinks:"):
            section = "sinks"
            continue
        if clean.startswith("Sources:"):
            section = "sources"
            continue
        if clean.startswith(("Sink endpoints:", "Source endpoints:", "Streams:", "Filters:", "Devices:")):
            section = ""
            continue
        if section in ("sinks", "sources"):
            active = clean.startswith("*")
            item_str = clean.lstrip("*").strip()
            m = re.match(r"^(\d+)\.\s+(.+?)(?:\s+\[vol:.*\])?$", item_str)
            if m:
                entry = {"id": m.group(1), "name": m.group(2).strip(), "active": active}
                if section == "sinks":
                    sinks.append(entry)
                else:
                    sources.append(entry)
    return sinks, sources


def get_audio_state():
    vol, muted = parse_wpctl_volume("@DEFAULT_AUDIO_SINK@")
    mic_vol, mic_muted = parse_wpctl_volume("@DEFAULT_AUDIO_SOURCE@")
    sinks, sources = parse_wpctl_devices()
    return {
        "volume": vol,
        "muted": muted,
        "micVolume": mic_vol,
        "micMuted": mic_muted,
        "sinks": sinks,
        "sources": sources,
    }


def get_system_state(wifi_enabled, bt_powered):
    brightness = 100
    if shutil.which("brightnessctl"):
        rc1, cur_s, _ = run_cmd(["brightnessctl", "--class=backlight", "get"], timeout=1.5)
        rc2, max_s, _ = run_cmd(["brightnessctl", "--class=backlight", "max"], timeout=1.5)
        try:
            if rc1 == 0 and rc2 == 0 and int(max_s) > 0:
                brightness = max(1, min(100, round(int(cur_s) * 100 / int(max_s))))
        except ValueError:
            pass

    caffeine = (RUNTIME / "caffeine.inhibit").is_file()
    night_light = False
    if shutil.which("systemctl"):
        rc, _, _ = run_cmd(["systemctl", "--user", "is-active", "--quiet", f"{SERVICE_PREFIX}-sunset.service"], timeout=1.5)
        night_light = rc == 0

    dnd = False
    if shutil.which("makoctl"):
        _, modes, _ = run_cmd(["makoctl", "mode"], timeout=1.5)
        dnd = "do-not-disturb" in modes.splitlines()

    return {
        "brightness": brightness,
        "caffeine": caffeine,
        "nightLight": night_light,
        "dnd": dnd,
        "airplane": (not wifi_enabled) and (not bt_powered),
    }


def full_state(scan_networks=True):
    wifi = get_wifi_state(scan_networks=scan_networks)
    bt = get_bluetooth_state()
    audio = get_audio_state()
    system = get_system_state(wifi["enabled"], bt["powered"])
    return {
        "wifi": wifi,
        "bluetooth": bt,
        "audio": audio,
        "system": system,
    }


def handle_action(args):
    if not args:
        return
    act = args[0]
    if act == "wifi-toggle":
        wifi = get_wifi_state(scan_networks=False)
        target = "off" if wifi["enabled"] else "on"
        run_cmd(["nmcli", "radio", "wifi", target])
    elif act == "wifi-scan":
        run_cmd(["nmcli", "device", "wifi", "rescan"], timeout=8.0)
    elif act == "wifi-connect":
        ssid = args[1] if len(args) > 1 else ""
        password = args[2] if len(args) > 2 else ""
        if not ssid:
            sys.exit(2)
        if password:
            rc, _, err = run_cmd(["nmcli", "device", "wifi", "connect", ssid, "password", password], timeout=15.0)
        else:
            rc, _, err = run_cmd(["nmcli", "connection", "up", "id", ssid], timeout=12.0)
            if rc != 0:
                rc, _, err = run_cmd(["nmcli", "device", "wifi", "connect", ssid], timeout=12.0)
        if rc == 0:
            notify("Wi-Fi Connected", ssid)
        else:
            notify("Wi-Fi Connection Failed", err or ssid, "critical")
            sys.exit(1)
    elif act == "wifi-disconnect":
        ssid = args[1] if len(args) > 1 else ""
        if ssid:
            subprocess.run([sys.executable, str(ROOT / "scripts/network-action.py"), "disconnect", ssid], check=True, timeout=30)
            notify("Wi-Fi Disconnected", ssid)
    elif act == "wifi-forget":
        ssid = args[1] if len(args) > 1 else ""
        if ssid:
            run_cmd(["nmcli", "connection", "delete", "id", ssid], timeout=6.0)
            notify("Removed Saved Network", ssid)
    elif act == "wifi-hotspot":
        wifi = get_wifi_state(scan_networks=False)
        if wifi["hotspotActive"]:
            run_cmd(["nmcli", "connection", "down", "id", "Hotspot"], timeout=6.0)
            notify("Wi-Fi Hotspot Stopped", "Restored normal Wi-Fi client mode")
        else:
            rc, out, err = run_cmd(["nmcli", "device", "wifi", "hotspot"], timeout=10.0)
            if rc == 0:
                notify("Wi-Fi Hotspot Active", out or "Hotspot started")
            else:
                notify("Hotspot Failed", err or "Could not start hotspot", "critical")
    elif act == "airplane-toggle":
        wifi = get_wifi_state(scan_networks=False)
        bt = get_bluetooth_state()
        turning_on_airplane = wifi["enabled"] or bt["powered"]
        if turning_on_airplane:
            run_cmd(["nmcli", "radio", "all", "off"])
            run_cmd(["bluetoothctl", "power", "off"])
            if shutil.which("rfkill"):
                run_cmd(["rfkill", "block", "bluetooth"])
            notify("Airplane Mode Enabled", "Wi-Fi and Bluetooth turned off")
        else:
            if shutil.which("rfkill"):
                run_cmd(["rfkill", "unblock", "all"])
                import time
                time.sleep(0.15)
            run_cmd(["nmcli", "radio", "all", "on"])
            run_cmd(["bluetoothctl", "power", "on"])
            run_cmd(["bluetoothctl", "discoverable-timeout", "0"], timeout=2.0)
            run_cmd(["bluetoothctl", "pairable", "on"], timeout=2.0)
            run_cmd(["bluetoothctl", "discoverable", "on"], timeout=2.0)
            notify("Airplane Mode Disabled", "Wireless radios restored")
    elif act == "bt-toggle":
        bt = get_bluetooth_state()
        if bt["powered"]:
            run_cmd(["bluetoothctl", "power", "off"], timeout=2.0)
        else:
            if shutil.which("rfkill"):
                run_cmd(["rfkill", "unblock", "bluetooth"], timeout=2.0)
                import time
                for _ in range(8):
                    rc, out, _ = run_cmd(["bluetoothctl", "show"], timeout=1.0)
                    if rc == 0 and "No default controller" not in out:
                        break
                    time.sleep(0.05)
            run_cmd(["bluetoothctl", "power", "on"], timeout=3.0)
            run_cmd(["bluetoothctl", "discoverable-timeout", "0"], timeout=2.0)
            run_cmd(["bluetoothctl", "pairable", "on"], timeout=2.0)
            run_cmd(["bluetoothctl", "discoverable", "on"], timeout=2.0)
    elif act == "bt-discoverable":
        bt = get_bluetooth_state()
        target = "off" if bt["discoverable"] else "on"
        run_cmd(["bluetoothctl", "discoverable-timeout", "0"], timeout=2.0)
        run_cmd(["bluetoothctl", "pairable", "on"], timeout=2.0)
        run_cmd(["bluetoothctl", "discoverable", target], timeout=2.0)
        if target == "on":
            notify("Bluetooth", "Device is now always discoverable", "low")
        else:
            notify("Bluetooth", "Device is now hidden from discovery", "low")
    elif act == "bt-scan":
        run_cmd(["bluetoothctl", "--timeout", "4", "scan", "on"], timeout=6.0)
    elif act == "bt-pair":
        mac = args[1] if len(args) > 1 else ""
        if mac:
            rc, _, err = run_cmd(["bluetoothctl", "pair", mac], timeout=15.0)
            if rc == 0:
                run_cmd(["bluetoothctl", "trust", mac], timeout=4.0)
                run_cmd(["bluetoothctl", "connect", mac], timeout=10.0)
                notify("Bluetooth Paired", mac)
            else:
                notify("Bluetooth Pairing Failed", err or mac, "critical")
    elif act == "bt-connect":
        mac = args[1] if len(args) > 1 else ""
        if mac:
            rc, _, err = run_cmd(["bluetoothctl", "connect", mac], timeout=10.0)
            if rc == 0:
                notify("Bluetooth Connected", mac)
            else:
                notify("Bluetooth Connection Failed", err or mac, "critical")
    elif act == "bt-disconnect":
        mac = args[1] if len(args) > 1 else ""
        if mac:
            run_cmd(["bluetoothctl", "disconnect", mac], timeout=6.0)
            notify("Bluetooth Disconnected", mac)
    elif act == "bt-trust":
        mac = args[1] if len(args) > 1 else ""
        if mac:
            _, info_out, _ = run_cmd(["bluetoothctl", "info", mac], timeout=2.0)
            cmd = "untrust" if "Trusted: yes" in info_out else "trust"
            run_cmd(["bluetoothctl", cmd, mac], timeout=3.0)
    elif act == "bt-forget":
        mac = args[1] if len(args) > 1 else ""
        if mac:
            run_cmd(["bluetoothctl", "remove", mac], timeout=5.0)
            notify("Bluetooth Device Removed", mac)
    elif act == "bt-send":
        mac = args[1] if len(args) > 1 else ""
        send_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bluetooth-send.py")
        cmd = ["python3", send_script]
        if mac:
            cmd.append(mac)
        subprocess.Popen(cmd)
    elif act == "audio-volume":
        pct = max(0, min(100, int(float(args[1])))) if len(args) > 1 else 50
        run_cmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"])
        run_cmd(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", f"{pct}%"])
    elif act == "audio-mute":
        run_cmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    elif act == "mic-volume":
        pct = max(0, min(100, int(float(args[1])))) if len(args) > 1 else 50
        run_cmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "0"])
        run_cmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", f"{pct}%"])
    elif act == "mic-mute":
        run_cmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
    elif act == "audio-set-sink":
        if len(args) > 1:
            run_cmd(["wpctl", "set-default", args[1]])
    elif act == "audio-set-source":
        if len(args) > 1:
            run_cmd(["wpctl", "set-default", args[1]])
    elif act == "brightness":
        pct = max(1, min(100, int(float(args[1])))) if len(args) > 1 else 50
        run_cmd(["brightnessctl", "--class=backlight", "set", f"{pct}%"])
    elif act == "caffeine-toggle":
        subprocess.run([str(ROOT / "scripts/caffeine.sh"), "toggle"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif act == "nightlight-toggle":
        subprocess.run([str(ROOT / "scripts/night-light.sh")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif act == "dnd-toggle":
        subprocess.run([str(ROOT / "scripts/notifications.sh"), "dnd"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        sys.exit(2)


def main():
    if len(sys.argv) <= 1 or sys.argv[1] == "--state":
        scan = "--no-scan" not in sys.argv
        state = full_state(scan_networks=scan)
        payload = json.dumps(state)
        try:
            CACHE.mkdir(parents=True, exist_ok=True)
            (CACHE / "cc-state.json").write_text(payload)
        except OSError:
            pass
        print(payload)
        return
    if sys.argv[1] == "--action":
        action_args = sys.argv[2:]
        handle_action(action_args)
        need_scan = bool(action_args and action_args[0].startswith("wifi"))
        state = full_state(scan_networks=need_scan)
        payload = json.dumps(state)
        try:
            CACHE.mkdir(parents=True, exist_ok=True)
            (CACHE / "cc-state.json").write_text(payload)
        except OSError:
            pass
        print(payload)
        return
    handle_action(sys.argv[1:])


if __name__ == "__main__":
    main()
