#!/usr/bin/env python3
"""Read per-sink PipeWire/PulseAudio ports using locale-independent JSON."""
import json,os,re,subprocess,sys

def read_audio(selected=None):
    env=dict(os.environ,LC_ALL='C')
    def run(args):return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL,timeout=3,env=env)
    names={};bt={};ports={}
    try:
        for line in run(['bluetoothctl','devices']).splitlines():
            fields=line.split(maxsplit=2)
            if len(fields)==3 and fields[0]=='Device':bt[fields[1].upper()]=fields[2]
    except (OSError,subprocess.SubprocessError):pass
    sinks=json.loads(run(['pactl','--format=json','list','sinks']))
    if not selected:selected=run(['pactl','get-default-sink']).strip()
    for sink in sinks:
        name=sink['name'];desc=sink.get('description',name)
        mac=re.search(r'(?:[0-9A-Fa-f]{2}[_:]){5}[0-9A-Fa-f]{2}',name)
        if mac:desc=bt.get(mac[0].replace('_',':').upper(),desc)
        names[name]=desc
        raw=sink.get('ports',[])
        if isinstance(raw,dict):raw=[dict(v,name=k) for k,v in raw.items()]
        active=sink.get('active_port','')
        if isinstance(active,dict):active=active.get('name','')
        ports[name]={'active_port':active,'headphone_available':any(p.get('name')=='analog-output-headphones' and p.get('availability')=='available' for p in raw)}
    current=ports.get(selected,{'active_port':'','headphone_available':False})
    return dict(current,sink_names=names,bt_devices=bt,ports=ports,selected_sink=selected)

if __name__=='__main__':
    try:print(json.dumps(read_audio(sys.argv[1] if len(sys.argv)>1 else None)))
    except (OSError,ValueError,subprocess.SubprocessError) as error:
        print(error,file=sys.stderr);sys.exit(1)
