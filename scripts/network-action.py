#!/usr/bin/env python3
"""Shared Wi-Fi operations; disconnect by actual device, never by profile alias."""
import subprocess, sys

def fields(line):
    out=[]; word=''; escape=False
    for c in line:
        if escape:word+=c;escape=False
        elif c=='\\':escape=True
        elif c==':':out.append(word);word=''
        else:word+=c
    return out+[word]

def disconnect(ssid):
    r=subprocess.run(['nmcli','-t','-f','IN-USE,SSID,DEVICE','device','wifi','list'],capture_output=True,text=True,check=True,timeout=10)
    devices={f[2] for line in r.stdout.splitlines() if len(f:=fields(line))==3 and f[0]=='*' and f[1]==ssid}
    if not devices:raise ValueError('This network is no longer connected')
    for device in devices:subprocess.run(['nmcli','device','disconnect',device],check=True,timeout=15)

if __name__=='__main__':
    try:
        if len(sys.argv)!=3 or sys.argv[1]!='disconnect':raise ValueError('Usage: network-action.py disconnect SSID')
        disconnect(sys.argv[2])
    except (ValueError,subprocess.SubprocessError) as e:
        print(e,file=sys.stderr);sys.exit(1)
