#!/usr/bin/env python3
"""Retire competing daemons only on this Wayland display, never other sessions.
No host files or enablement settings are changed. Called once at login.
"""
import os, re, signal, subprocess
from pathlib import Path

def is_legacy_watcher(name, args):
    return name == 'bash' and any(arg.startswith(b'while [ ! -f ') and b'inotifywait' in arg and
                                  (b'/minimal/settings.json' in arg or b'/minimal/qs_colors.json' in arg)
                                  for arg in args)

def main():
    display = os.environ.get('WAYLAND_DISPLAY')
    prefix = os.environ.get('MINIMAL_SERVICE_PREFIX', '')
    root = os.environ.get('MINIMAL_ROOT', '')
    if not display or not prefix or not root:
        raise SystemExit('Missing session identity; refusing conflict cleanup')
    names = {'waybar', 'hyprpaper', 'mako', 'hypridle', 'udiskie', 'wl-paste',
             'wl-clip-persist', 'dunst', 'swaync', 'blueman-applet', 'blueman-tray', 'nm-applet'}
    for process in Path('/proc').iterdir():
        if not process.name.isdigit(): continue
        try:
            if process.stat().st_uid != os.getuid(): continue
            env = dict(field.split(b'=', 1) for field in (process/'environ').read_bytes().split(b'\0') if b'=' in field)
            if env.get(b'WAYLAND_DISPLAY') != display.encode(): continue
            cgroup = (process/'cgroup').read_text()
            if prefix in cgroup: continue
            name = (process/'comm').read_text().strip()
            args = (process/'cmdline').read_bytes().split(b'\0')
            legacy_watcher = is_legacy_watcher(name, args)
            old_battery = (root + '/scripts/battery-monitor.sh').encode() in args
            if name not in names and not old_battery and not legacy_watcher: continue
            units = re.findall(r'/([^/\n]+\.service)(?:/|$)', cgroup, re.M)
            # Never stop the user manager or a compositor service containing its children.
            unit = next((u for u in reversed(units) if u.startswith(('mako.', 'dunst.', 'swaync.', 'waybar.', 'hypridle.', 'hyprpaper.'))), None)
            if unit:
                subprocess.run(['systemctl', '--user', 'stop', unit], check=True, timeout=10)
            else:
                fd = os.pidfd_open(int(process.name))
                try: signal.pidfd_send_signal(fd, signal.SIGTERM)
                finally: os.close(fd)
        except (FileNotFoundError, ProcessLookupError, PermissionError, subprocess.SubprocessError):
            continue

if __name__ == '__main__': main()
