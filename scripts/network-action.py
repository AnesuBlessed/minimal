#!/usr/bin/env python3
"""Shared Wi-Fi operations for Minimal: connect, disconnect, forget, and saved profiles."""
import subprocess
import sys


def fields(line):
    out = []
    word = ''
    escape = False
    for c in line:
        if escape:
            word += c
            escape = False
        elif c == '\\':
            escape = True
        elif c == ':':
            out.append(word)
            word = ''
        else:
            word += c
    return out + [word]


def notify(summary, body, critical=False):
    urgency = 'critical' if critical else 'normal'
    try:
        subprocess.run(['notify-send', '-u', urgency, summary, body], check=False, timeout=3)
    except Exception:
        pass


def list_saved():
    r = subprocess.run(['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show'],
                       capture_output=True, text=True, check=True, timeout=5)
    saved = []
    for line in r.stdout.splitlines():
        parts = fields(line)
        if len(parts) == 2 and 'wireless' in parts[1]:
            saved.append(parts[0])
    return saved


def connect(ssid, password=None):
    if not ssid:
        raise ValueError("SSID cannot be empty")

    cmd = ['nmcli', 'device', 'wifi', 'connect', ssid]
    if password:
        cmd.extend(['password', password])

    r = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
    if r.returncode != 0:
        err = r.stderr.strip() or r.stdout.strip() or "Connection failed"
        if err.startswith("Error:"):
            err = err[6:].strip()
        notify("Wi-Fi Error", f"Failed to connect to '{ssid}': {err}", critical=True)
        print(err, file=sys.stderr)
        sys.exit(r.returncode or 1)

    notify("Wi-Fi", f"Connected to '{ssid}'")
    if r.stdout.strip():
        print(r.stdout.strip())


def disconnect(ssid):
    r = subprocess.run(['nmcli', '-t', '-f', 'IN-USE,SSID,DEVICE', 'device', 'wifi', 'list'],
                       capture_output=True, text=True, check=True, timeout=10)
    devices = {f[2] for line in r.stdout.splitlines() if len(f := fields(line)) == 3 and f[0] == '*' and f[1] == ssid}
    if not devices:
        raise ValueError('This network is no longer connected')
    for device in devices:
        subprocess.run(['nmcli', 'device', 'disconnect', device], check=True, timeout=15)
    notify("Wi-Fi", f"Disconnected from '{ssid}'")


def forget(ssid):
    if not ssid:
        raise ValueError("SSID cannot be empty")
    r = subprocess.run(['nmcli', 'connection', 'delete', ssid], capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        err = r.stderr.strip() or r.stdout.strip() or "Failed to forget network"
        if err.startswith("Error:"):
            err = err[6:].strip()
        notify("Wi-Fi Error", f"Failed to forget '{ssid}': {err}", critical=True)
        print(err, file=sys.stderr)
        sys.exit(r.returncode or 1)
    notify("Wi-Fi", f"Removed network '{ssid}'")


if __name__ == '__main__':
    try:
        if len(sys.argv) < 2:
            raise ValueError('Usage: network-action.py <connect|disconnect|forget|saved> [args...]')

        action = sys.argv[1]
        if action == 'disconnect':
            if len(sys.argv) != 3:
                raise ValueError('Usage: network-action.py disconnect SSID')
            disconnect(sys.argv[2])
        elif action == 'connect':
            if len(sys.argv) < 3:
                raise ValueError('Usage: network-action.py connect SSID [PASSWORD]')
            ssid = sys.argv[2]
            pw = sys.argv[3] if len(sys.argv) > 3 else None
            connect(ssid, pw)
        elif action == 'forget':
            if len(sys.argv) != 3:
                raise ValueError('Usage: network-action.py forget SSID')
            forget(sys.argv[2])
        elif action == 'saved':
            for s in list_saved():
                print(s)
        else:
            raise ValueError(f"Unknown action: {action}")
    except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as e:
        print(e, file=sys.stderr)
        sys.exit(1)
