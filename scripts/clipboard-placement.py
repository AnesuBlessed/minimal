#!/usr/bin/env python3
"""Anchor clipboard away from the active bar; centered if its position is unknown."""
import json
import os
from pathlib import Path
state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'minimal'
try:
    config = json.loads((state / 'waybar.json').read_text())
    position = config.get('position', 'top')
    # Waybar layouts configure min-height 10, but GTK styling renders at >= 34px.
    bar_height = max(int(config.get('height', 34)), 34)
    offset = bar_height + 14
except (OSError, ValueError, TypeError):
    position, offset = 'unknown', 48
rules = {
    'top': f'location: north east; anchor: north east; x-offset: -12px; y-offset: {offset}px;',
    'bottom': f'location: south east; anchor: south east; x-offset: -12px; y-offset: -{offset}px;',
    'left': 'location: west; anchor: west; x-offset: 60px; y-offset: 0px;',
    'right': 'location: east; anchor: east; x-offset: -60px; y-offset: 0px;',
}
print('window { ' + rules.get(position, 'location: center; anchor: center; x-offset: 0px; y-offset: 0px;') + ' }')
