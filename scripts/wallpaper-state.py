#!/usr/bin/env python3
"""Atomically persist per-output selections; caller serializes wallpaper changes."""
import json, os, sys, tempfile
from pathlib import Path
state = Path(os.environ['MINIMAL_STATE'])
path = state / 'wallpapers.json'
try:
    selections = json.loads(path.read_text())
except (OSError, ValueError):
    selections = {}
wall, outputs, kind, preview = sys.argv[1:]
if outputs == 'all':
    selections = {}
for output in outputs.split(','):
    selections[output] = dict(path=wall, kind=kind, preview=preview)
fd, temporary = tempfile.mkstemp(dir=state, prefix='wallpapers-')
try:
    with os.fdopen(fd, 'w') as stream:
        json.dump(selections, stream)
    os.replace(temporary, path)
finally:
    Path(temporary).unlink(missing_ok=True)
