#!/usr/bin/env python3
"""Owned screen recorder lifecycle and truthful Waybar status."""
import fcntl, json, os, signal, subprocess, sys, time, uuid
from pathlib import Path
from transfer_state import atomic_json

RUNTIME=Path(os.environ['MINIMAL_RUNTIME'])
STATE=RUNTIME/'recording.json'

def read():
    try:return json.loads(STATE.read_text())
    except (OSError,ValueError):return {}

def start_time(pid):
    try:return Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[19]
    except (OSError,IndexError):return None

def alive(data):
    return bool(data.get('active') and data.get('start') and start_time(data.get('pid'))==data['start'])

def refresh():
    subprocess.run(['systemctl','--user','kill','--kill-whom=main','--signal=RTMIN+10',os.environ['MINIMAL_SERVICE_PREFIX']+'-waybar.service'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def notify(title,body):
    subprocess.run(['notify-send','-a','minimal',title,body],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def worker(token,output,command):
    child=None;data={'id':token,'active':False,'status':'error','output':output}
    try:
        child=subprocess.Popen(command,stdin=subprocess.DEVNULL)
        def stop(*_):
            if child.poll() is None:child.send_signal(signal.SIGINT)
        signal.signal(signal.SIGTERM,stop)
        time.sleep(.3)
        if child.poll() is not None:raise RuntimeError('Recorder exited during startup')
        data.update(active=True,status='recording',pid=child.pid,start=start_time(child.pid))
        atomic_json(STATE,data);refresh();notify('Recording started','Press Super+Shift+R to stop.')
        code=child.wait()
        good=code in (0,-signal.SIGINT) and Path(output).is_file() and Path(output).stat().st_size>0
        data.update(active=False,status='saved' if good else 'error')
        atomic_json(STATE,data);refresh()
        notify('Screen recording saved' if good else 'Screen recording failed',output)
    except Exception as error:
        if child and child.poll() is None:
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait()
        atomic_json(STATE,data);refresh();notify('Screen recording failed',str(error))

def main():
    RUNTIME.mkdir(parents=True,exist_ok=True)
    mode=sys.argv[1]
    if mode=='worker':worker(sys.argv[2],sys.argv[3],sys.argv[4:]);return
    if mode=='status':
        data=read();active=alive(data)
        print(json.dumps({'text':'● REC' if active else '', 'class':'recording' if active else 'idle',
                          'tooltip':'Click to stop recording' if active else 'Not recording'}));return
    with (RUNTIME/'recording.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        data=read()
        if alive(data):
            os.kill(data['pid'],signal.SIGINT)
            deadline=time.monotonic()+15
            while alive(read()) and time.monotonic()<deadline:time.sleep(.1)
            if alive(read()):raise RuntimeError('Recorder is still finalizing; try again shortly')
            return
        import shutil
        recorder=next((shutil.which(x) for x in ('wl-screenrec','wf-recorder') if shutil.which(x)),None)
        if not recorder:raise RuntimeError('Install wl-screenrec or wf-recorder')
        args=[]
        if mode=='record':
            region=subprocess.run(['slurp'],capture_output=True,text=True)
            if region.returncode or not region.stdout.strip():return
            args=['-g',region.stdout.strip()]
        output_dir=Path(os.environ.get('XDG_VIDEOS_DIR',str(Path.home()/'Videos')))/'Recordings'
        output_dir.mkdir(parents=True,exist_ok=True)
        token=uuid.uuid4().hex
        output=str(output_dir/(time.strftime('recording-%Y%m%d-%H%M%S-')+token[:6]+'.mp4'))
        with (RUNTIME/'recording.log').open('a') as log:
            proc=subprocess.Popen([sys.executable,__file__,'worker',token,output,recorder,*args,'-f',output],
                                  start_new_session=True,stdin=subprocess.DEVNULL,stdout=log,stderr=log)
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            data=read()
            if data.get('id')==token:
                if not alive(data):raise RuntimeError('Recorder failed to start; see recording.log')
                return
            if proc.poll() is not None:raise RuntimeError('Recorder supervisor exited')
            time.sleep(.05)
        proc.terminate()
        raise RuntimeError('Recorder startup timed out')

if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError) as error:
        print(error,file=sys.stderr);sys.exit(1)
