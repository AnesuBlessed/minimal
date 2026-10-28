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
    wall = root/'wallpapers/japan_lake.jpg'
widget = 'box-wallpaper' if sys.argv[1:] == ['launcher'] else 'wallframe'
print(widget + ' { background-image: url(' + json.dumps(str(wall.resolve())) + ', height); }')
