#!/usr/bin/env python3
"""Compile and run Minimal's bar without writing to the checkout."""
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from minimal_config import validate_bar

ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local/state')) / 'minimal'


def compile_config(layout):
    source = ROOT / 'waybar/config.jsonc' if layout == 'custom' else ROOT / f'waybar/layouts/{layout}.jsonc'
    data = validate_bar(source)
    # Optional hardware disappears cleanly on machines without it.
    sensor = None
    for device in sorted(Path('/sys/class/hwmon').glob('hwmon*')):
        try:
            if (device / 'name').read_text().strip() in ('coretemp', 'k10temp', 'cpu_thermal', 'zenpower'):
                sensor = next(device.glob('temp*_input'), None)
                if sensor:
                    break
        except OSError:
            pass
    unavailable = set()
    if sensor and isinstance(data.get('temperature'), dict):
        data['temperature']['hwmon-path'] = str(sensor)
    elif not sensor:
        unavailable.add('temperature')
    if not list(Path('/sys/class/backlight').glob('*')):
        unavailable.update(('backlight', 'group/eyecare'))
    if not any(p.name.startswith('BAT') for p in Path('/sys/class/power_supply').glob('*')):
        unavailable.add('battery')
    def filter_modules(value):
        if isinstance(value, dict):
            return {k: filter_modules(v) for k, v in value.items()}
        if isinstance(value, list):
            return [filter_modules(v) for v in value if not isinstance(v, str) or v not in unavailable]
        return value
    return filter_modules(data)


def owned_pid(pidfile, config):
    try:
        pid = int(pidfile.read_text())
        args = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
        if str(config).encode() in args and Path(os.fsdecode(args[0])).name == 'waybar':
            return pid
    except (OSError, ValueError):
        pass
    return None


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'next'
    layouts = sorted(p.stem for p in (ROOT / 'waybar/layouts').glob('[0-9][0-9].jsonc'))
    if command == 'select':
        # Prompt interactively before taking the lock so concurrent calls don't stall.
        result = subprocess.run(['rofi','-dmenu','-no-custom','-theme',str(ROOT / 'rofi/selector.rasi'),'-p','Bar layout'], input='\n'.join(['custom', *layouts]), text=True, capture_output=True)
        if result.returncode:
            return
        command = result.stdout.strip()
        if command not in [*layouts, 'custom']:
            raise ValueError('Unknown layout')
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'bar.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        statefile = STATE / 'current_waybar_layout'
        current = statefile.read_text().strip() if statefile.exists() else 'custom'
        if current not in [*layouts, 'custom']:
            current = 'custom'
        target = current
        if command in ('next', 'prev'):
            index = layouts.index(current) if current in layouts else (-1 if command == 'next' else 0)
            target = layouts[(index + (1 if command == 'next' else -1)) % len(layouts)]
        elif command in [*layouts, 'custom']:
            target = command
        elif command not in ('start', 'reload', 'render'):
            raise ValueError('Usage: bar.sh [next|prev|select|01..17|custom|start|reload|render]')
        data = compile_config(target)
        config = STATE / 'waybar.json'
        temporary = STATE / 'waybar.json.tmp'
        temporary.write_text(json.dumps(data, indent=2) + '\n')
        temporary.replace(config)
        statefile.write_text(target + '\n')
        if command == 'render':
            print(config)
            return
        pidfile = STATE / 'waybar.pid'
        pid = owned_pid(pidfile, config)
        if pid:
            if command != 'start':
                os.kill(pid, signal.SIGUSR2)
        else:
            env = dict(os.environ, MINIMAL_ROOT=str(ROOT))
            logfile = STATE / 'waybar.log'
            try:
                if logfile.exists() and logfile.stat().st_size > 1024 * 1024:
                    logfile.replace(STATE / 'waybar.log.1')
            except OSError:
                pass
            with logfile.open('a') as log:
                process = subprocess.Popen(['waybar','-c',str(config),'-s',str(ROOT / 'waybar/style.css')], env=env, stdout=log, stderr=log, start_new_session=True)
            time.sleep(0.2)
            if process.poll() is not None:
                raise ValueError(f'Waybar exited during startup; see {STATE / "waybar.log"}')
            pidfile.write_text(str(process.pid))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        print(f'Minimal bar: {exc}', file=sys.stderr)
        sys.exit(1)
