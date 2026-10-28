#!/usr/bin/env python3
"""Build a safely quoted Rasi image property for the current wallpaper."""
import json
import os
from pathlib import Path
import sys
root = Path(__file__).resolve().parent.parent
state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/'minimal'
wall = state/'wallpaper.set'
if not wall.is_file():
    matches = list(root.glob('wallpapers/**/japan_lake.jpg'))
    wall = matches[0] if matches else next((p for p in root.glob('wallpapers/**/*') if p.is_file() and p.suffix.lower() in ('.jpg', '.png', '.jpeg', '.webp')), root/'wallpapers/Nature-Landscape/japan_lake.jpg')
widget = 'box-wallpaper' if sys.argv[1:] == ['launcher'] else 'wallframe'
print(widget + ' { background-image: url(' + json.dumps(str(wall.resolve())) + ', height); }')
