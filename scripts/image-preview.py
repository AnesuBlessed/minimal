#!/usr/bin/env python3
"""Validate downloaded raster images and create bounded static thumbnails."""
import argparse
import os
from pathlib import Path
import tempfile
from PIL import Image

MAX_BYTES = 25 * 1024 * 1024
MAX_PIXELS = 40_000_000
Image.MAX_IMAGE_PIXELS = MAX_PIXELS
FORMATS = {'JPEG', 'PNG', 'WEBP', 'GIF'}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', nargs='?', type=Path)
    args = parser.parse_args()
    if not 0 < args.source.stat().st_size <= MAX_BYTES:
        raise ValueError('Image exceeds the download size limit')
    with Image.open(args.source) as image:
        if image.format not in FORMATS or image.width * image.height > MAX_PIXELS:
            raise ValueError('Unsupported image or excessive dimensions')
        image.verify()
    if args.destination is None:
        return
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.preview-', dir=args.destination.parent)
    os.close(fd)
    try:
        with Image.open(args.source) as image:
            image.seek(0)
            image.thumbnail((800, 420))
            image.convert('RGB').save(temporary, 'PNG')
        os.replace(temporary, args.destination)
    finally:
        Path(temporary).unlink(missing_ok=True)

if __name__ == '__main__':
    main()
