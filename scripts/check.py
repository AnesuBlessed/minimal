#!/usr/bin/env python3
"""Read-only repository checks. No daemons or desktop actions are started."""
import ast
from pathlib import Path
import re
import shutil
import subprocess
import sys
from minimal_config import validate_bar

ROOT = Path(__file__).resolve().parent.parent


FORBIDDEN = (
    r'(?i)\bhyde\b',
    r'(?i)wallbash',
    r'wbar-switch',
    r'custom/wbar',
    r'custom/wallchange',
    r'custom/cliphist',
    r'custom/keybindhint',
    r'custom-cpuinfo',
    r'custom-gpuinfo',
)
TEXT_SUFFIXES = {'.sh', '.py', '.lua', '.css', '.rasi', '.jsonc', '.json', '.conf', '.md', '.yml', '.ini', '.fish'}


def check(root=ROOT):
    errors = []
    for path in root.rglob('*'):
        if not path.is_file() or '.git' in path.parts or path.suffix not in TEXT_SUFFIXES:
            continue
        if path.resolve() == Path(__file__).resolve():
            continue
        text = path.read_text(errors='ignore')
        for pattern in FORBIDDEN:
            if re.search(pattern, text):
                errors.append(f'{path.relative_to(root)}: leftover {pattern} reference')
    for path in root.rglob('*.sh'):
        if '.git' in path.parts:
            continue
        result = subprocess.run(['bash', '-n', str(path)], capture_output=True, text=True)
        if result.returncode:
            errors.append(result.stderr)
    for path in (root / 'scripts').glob('*.py'):
        try:
            ast.parse(path.read_text())
        except SyntaxError as exc:
            errors.append(str(exc))
    if shutil.which('luac'):
        for path in (root / 'hypr').glob('*.lua'):
            result = subprocess.run(['luac','-p',str(path)],capture_output=True,text=True)
            if result.returncode:
                errors.append(result.stderr)
    else:
        print('SKIP: Lua syntax (luac unavailable)')
    for path in [root/'waybar/config.jsonc',*sorted((root/'waybar/layouts').glob('[0-9][0-9].jsonc'))]:
        try:
            validate_bar(path)
        except (OSError, ValueError, KeyError) as exc:
            errors.append(str(exc))
    # GTK parses CSS without opening windows.
    try:
        import gi
        gi.require_version('Gtk','3.0')
        from gi.repository import Gtk
        for name in ('waybar/style.css', 'wlogout/style.css'):
            provider = Gtk.CssProvider()
            provider.connect('parsing-error', lambda p, section, error: errors.append(f'{name}: {error.message}'))
            provider.load_from_path(str(root/name))
    except ImportError:
        print('SKIP: GTK CSS parser (Python GObject/GTK unavailable)')
    if shutil.which('rofi'):
        for path in (root/'rofi').glob('*.rasi'):
            result=subprocess.run(['rofi','-no-config','-theme',str(path),'-dump-theme'], capture_output=True,text=True,timeout=10)
            if result.returncode or 'Failed to parse' in result.stderr:
                errors.append(f'{path}: {result.stderr}')
    else:
        print('SKIP: Rofi theme parser (rofi unavailable)')
    if shutil.which('foot'):
        result=subprocess.run(['foot','--check-config','--config='+str(root/'foot/foot.ini')],capture_output=True,text=True)
        if result.returncode:
            errors.append(result.stderr)
    if errors:
        print('\n'.join('FAIL: '+error for error in errors))
        return 1
    print('PASS: shell/Python syntax, available Lua/GTK/Rofi/Foot parsers, bar includes and modules')
    return 0


if __name__=='__main__': sys.exit(check())
