#!/usr/bin/env bash
CONFIG="$1/config.json"
wallpaper_path="$HOME/$(jq -r '.wallpaper_path' "$CONFIG")"
cache_path="$HOME/$(jq -r '.cache_path' "$CONFIG")"

mkdir -p "$cache_path"

python3 -c "
from PIL import Image
import os, glob

wall_dir = '$wallpaper_path'
thumb_dir = '$cache_path'

files = glob.glob(os.path.join(wall_dir, '*'))
for f in files:
    bn = os.path.basename(f)
    out = os.path.join(thumb_dir, bn)
    if os.path.exists(out):
        continue
    try:
        with Image.open(f) as im:
            if im.mode in ('RGBA', 'LA') or (im.mode == 'P' and 'transparency' in im.info):
                im = im.convert('RGBA')
                bg = Image.new('RGBA', im.size, (20, 20, 26, 255))
                im = Image.alpha_composite(bg, im).convert('RGB')
            else:
                im = im.convert('RGB')
            im.thumbnail((600, 500), Image.Resampling.LANCZOS)
            tmp = out + '.tmp'
            im.save(tmp, 'PNG' if bn.lower().endswith('.png') else 'JPEG', quality=85)
            os.replace(tmp, out)
    except Exception:
        pass
"
