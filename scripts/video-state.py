#!/usr/bin/env python3
"""Reconcile only this session's video units with saved per-output wallpaper state."""
import hashlib,json,os,subprocess,sys
from pathlib import Path

def reconcile():
    prefix=os.environ['MINIMAL_SERVICE_PREFIX']
    state=Path(os.environ['MINIMAL_STATE'])/'wallpapers.json'
    data=json.loads(state.read_text()) if state.exists() else {}
    subprocess.run(['systemctl','--user','stop',prefix+'-video-*.service'],check=True)
    if not any(v.get('kind') == 'video' for v in data.values()): return
    monitors=json.loads(subprocess.check_output(['hyprctl','-j','monitors'],text=True))
    for monitor in monitors:
        name=monitor['name'];selection=data.get(name,data.get('all',{}))
        if selection.get('kind')!='video':continue
        video=selection['path']
        if not Path(video).is_file():raise ValueError('Saved video is missing: '+video)
        unit=prefix+'-video-'+hashlib.sha256(name.encode()).hexdigest()[:12]
        subprocess.run(['systemd-run','--user','--quiet','--collect','--unit='+unit,
                        '--property=PartOf=graphical-session.target','--property=Type=exec',
                        '--setenv=WAYLAND_DISPLAY='+os.environ.get('WAYLAND_DISPLAY',''),
                        'mpvpaper','-o','loop --no-audio --hwdec=auto --profile=fast',name,video],check=True)
if __name__=='__main__':
    try:reconcile()
    except (OSError,ValueError,subprocess.SubprocessError) as error:
        print(error,file=sys.stderr);sys.exit(1)
