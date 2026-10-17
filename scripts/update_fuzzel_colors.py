#!/usr/bin/env python3
"""One-shot wallpaper palette generator with no background daemon."""
import colorsys
import fcntl
import os
from pathlib import Path
import sys
import tempfile
import json

ROOT = Path(__file__).resolve().parent.parent


def atomic_write(path, text):
    if path.exists() and path.read_text() == text:
        return
    fd, name = tempfile.mkstemp(prefix=".minimal-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.chmod(name, (path.stat().st_mode & 0o777) if path.exists() else 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    from PIL import Image
    if len(sys.argv) != 2:
        raise SystemExit("Usage: update_fuzzel_colors.py WALLPAPER")
    with Image.open(sys.argv[1]) as source:
        source = source.convert("RGB")
        source.thumbnail((96, 96))
        dominant = source.quantize(colors=8).convert("RGB")
        rgb = max(dominant.getcolors(96 * 96), key=lambda item: item[0])[1]
    hue, _, saturation = colorsys.rgb_to_hls(*(value / 255 for value in rgb))
    # Wallpaper supplies only the accent; neutral surfaces stay recognizable.
    accent = "".join(f"{round(v * 255):02x}" for v in colorsys.hls_to_rgb(
        hue, 0.78, min(0.24, max(0.10, saturation))))
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "minimal"
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "palette.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = ROOT / "theme.json"
        theme = json.loads(path.read_text())
        theme["colors"]["accent"] = accent
        atomic_write(path, json.dumps(theme, indent=2) + "\n")
        import runpy
        runpy.run_path(str(ROOT / "scripts/sync-theme.py"), run_name="__main__")


if __name__ == "__main__":
    main()
