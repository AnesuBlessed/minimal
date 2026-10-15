#!/usr/bin/env python3
"""One-shot wallpaper palette; no HyDE dependency and no Python daemon."""
import colorsys
import fcntl
import os
from pathlib import Path
import re
import sys
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def atomic_write(path, text):
    fd, name = tempfile.mkstemp(prefix=".minimal-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: update_fuzzel_colors.py WALLPAPER")
    with Image.open(sys.argv[1]) as source:
        source = source.convert("RGB")
        source.thumbnail((96, 96))
        dominant = source.quantize(colors=8).convert("RGB")
        rgb = max(dominant.getcolors(96 * 96), key=lambda item: item[0])[1]
    hue, _, saturation = colorsys.rgb_to_hls(*(value / 255 for value in rgb))
    saturation = min(0.45, max(0.18, saturation))

    def color(lightness):
        return "".join(f"{round(v * 255):02x}" for v in colorsys.hls_to_rgb(hue, lightness, saturation))

    bg, pill, accent = color(0.10), color(0.25), color(0.78)
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "minimal"
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / "palette.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = ROOT / "fuzzel/fuzzel.ini"
        text = path.read_text()
        before, rest = text.split("[colors]", 1)
        section, after = rest.split("[border]", 1)
        values = {"background": bg + "f0", "text": "ffffffff", "prompt": accent + "ff",
                  "match": accent + "ff", "selection": pill + "ff", "selection-text": "ffffffff",
                  "selection-match": accent + "ff", "border": accent + "55"}
        for key, value in values.items():
            section = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", section, flags=re.M)
        atomic_write(path, before + "[colors]" + section + "[border]" + after)
        palette = ROOT / "colors.css"
        css = palette.read_text()
        values = {"bg-glass": f"alpha(#{bg}, 0.88)", "bg-glass-hover": f"alpha(#{pill}, 0.95)",
                  "border-glass": f"alpha(#{accent}, 0.30)", "accent": f"#{accent}", "accent-dark": f"#{bg}"}
        for key, value in values.items():
            css = re.sub(rf"@define-color {key} [^;]+;", f"@define-color {key} {value};", css)
        atomic_write(palette, css)


if __name__ == "__main__":
    main()
