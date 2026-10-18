#!/usr/bin/env python3
"""Maintenance operations share feature-owned paths and propagate failures."""
import os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
CACHE=Path(os.environ.get('XDG_CACHE_HOME',str(Path.home()/'.cache')))
DATA=Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))

def clear(directory):
    # Remove entries, including hidden ones, without following directory symlinks.
    if directory.is_symlink():raise ValueError('Refusing a symlinked cache/trash root: '+str(directory))
    if not directory.exists():return
    for child in directory.iterdir():
        if child.is_dir() and not child.is_symlink():shutil.rmtree(child)
        else:child.unlink()

def main(action):
    if action=='clipboard':subprocess.run([str(ROOT/'scripts/clipboard-action.sh'),'wipe'],check=True)
    elif action=='trash':
        for name in ('files','info'):clear(DATA/'Trash'/name)
    elif action=='thumbnails':
        for path in (CACHE/'thumbnails',CACHE/'minimal/wallpaper-picker/thumbs',CACHE/'minimal/wallpaper-picker/search_thumbs'):
            clear(path)
    else:raise ValueError('Unknown maintenance action')
    subprocess.run(['notify-send','Maintenance',{'clipboard':'Clipboard history cleared','trash':'Trash emptied','thumbnails':'Thumbnail caches cleared'}[action]],check=False)
if __name__=='__main__':
    try:main(sys.argv[1])
    except (OSError,ValueError,subprocess.SubprocessError) as error:
        print(error,file=sys.stderr);sys.exit(1)
