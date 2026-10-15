#!/usr/bin/env bash
set -euo pipefail
root=$(dirname "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")")
source "$root/scripts/paths.sh"
mkdir -p -- "$MINIMAL_CACHE/thumbs"
# Pass paths as data, not Python source; a renamed wallpaper invalidates its cache.
python3 - "$MINIMAL_ROOT/wallpapers" "$MINIMAL_CACHE/thumbs" <<'PY'
from PIL import Image
from pathlib import Path
import os, sys, tempfile
for path in Path(sys.argv[1]).iterdir():
    if path.suffix.lower() not in ('.png', '.jpg', '.jpeg', '.webp'):
        continue
    target = Path(sys.argv[2]) / path.name
    if target.exists() and target.stat().st_mtime_ns >= path.stat().st_mtime_ns:
        continue
    temporary = None
    try:
        with Image.open(path) as source:
            source.thumbnail((600, 500), Image.Resampling.LANCZOS)
            image = Image.new('RGB', source.size, (20, 20, 26))
            rgba = source.convert('RGBA')
            image.paste(rgba, mask=rgba.getchannel('A'))
            fd, temporary = tempfile.mkstemp(dir=target.parent, suffix='.tmp')
            os.close(fd)
            image.save(temporary, 'PNG')
            os.replace(temporary, target)
    except (OSError, ValueError) as error:
        print(f'Thumbnail skipped: {path.name}: {error}', file=sys.stderr)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
PY
