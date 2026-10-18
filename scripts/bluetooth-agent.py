#!/usr/bin/env python3
"""BlueZ pairing consent and asynchronous, explicitly authorized OBEX reception."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid
try:
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib
except ImportError as error:
    print(f'Bluetooth agent requires python-dbus and python-gobject: {error}', file=sys.stderr)
    sys.exit(1)
from transfer_state import TransferState

AGENT_PATH = '/minimal/bluetooth/agent'
OBEX_AGENT_PATH = '/minimal/obex/agent'


def reject(message='Declined', obex=False):
    return dbus.exceptions.DBusException(message, name=('org.bluez.obex.Error.Rejected' if obex else 'org.bluez.Error.Rejected'))


class BluetoothAgent(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, AGENT_PATH)
        self.pending = None

    def prompt(self, device, message, reply, error, entry=None):
        if self.pending or not shutil.which('zenity'):
            error(reject('Another prompt is active or zenity is unavailable'))
            return
        command = ['zenity', '--entry' if entry else '--question', '--timeout=30',
                   '--title=Bluetooth pairing', '--text=' + message + '\nDevice: ' + str(device).rsplit('/',1)[-1]]
        try:
            proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        except OSError as exc:
            error(reject(str(exc))); return
        self.pending = (proc, error)
        def check():
            if self.pending is None or self.pending[0] is not proc: return False
            if proc.poll() is None: return True
            self.pending = None
            answer = proc.communicate()[0].strip()
            if proc.returncode != 0:
                error(reject()); return False
            try:
                if entry == 'passkey':
                    if not answer.isdigit() or len(answer) > 6: raise ValueError('Enter up to six digits')
                    reply(dbus.UInt32(int(answer)))
                elif entry == 'pin':
                    if not answer or len(answer) > 16: raise ValueError('PIN must contain 1–16 characters')
                    reply(answer)
                else: reply()
            except ValueError as exc: error(reject(str(exc)))
            return False
        GLib.timeout_add(100, check)

    @dbus.service.method('org.bluez.Agent1', in_signature='', out_signature='')
    def Release(self): self.Cancel()

    @dbus.service.method('org.bluez.Agent1', in_signature='', out_signature='')
    def Cancel(self):
        if self.pending:
            proc, error = self.pending; self.pending = None
            proc.terminate(); proc.communicate()
            error(reject('Pairing cancelled'))

    @dbus.service.method('org.bluez.Agent1', in_signature='o', out_signature='s', async_callbacks=('reply','error'))
    def RequestPinCode(self, device, reply, error):
        self.prompt(device, 'Enter the PIN shown by this device.', reply, error, 'pin')

    @dbus.service.method('org.bluez.Agent1', in_signature='o', out_signature='u', async_callbacks=('reply','error'))
    def RequestPasskey(self, device, reply, error):
        self.prompt(device, 'Enter the six-digit passkey shown by this device.', reply, error, 'passkey')

    @dbus.service.method('org.bluez.Agent1', in_signature='ou', out_signature='', async_callbacks=('reply','error'))
    def RequestConfirmation(self, device, passkey, reply, error):
        self.prompt(device, f'Pair only if the other device shows {int(passkey):06d}.', reply, error)

    @dbus.service.method('org.bluez.Agent1', in_signature='o', out_signature='', async_callbacks=('reply','error'))
    def RequestAuthorization(self, device, reply, error):
        self.prompt(device, 'Allow this device to pair?', reply, error)

    @dbus.service.method('org.bluez.Agent1', in_signature='os', out_signature='', async_callbacks=('reply','error'))
    def AuthorizeService(self, device, uuid, reply, error):
        self.prompt(device, 'Allow Bluetooth service ' + str(uuid) + '?', reply, error)

    @dbus.service.method('org.bluez.Agent1', in_signature='ouq', out_signature='')
    def DisplayPasskey(self, device, passkey, entered):
        subprocess.Popen(['notify-send','Bluetooth pairing',f'Enter {int(passkey):06d} on {device}'])

    @dbus.service.method('org.bluez.Agent1', in_signature='os', out_signature='')
    def DisplayPinCode(self, device, pincode):
        subprocess.Popen(['notify-send','Bluetooth pairing',f'Enter {pincode} on {device}'])


class ObexAgent(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBEX_AGENT_PATH)
        self.bus = bus
        self.state = None
        self.path = None
        self.pending = None
        self.deadline = 0

    def finish(self, status):
        if self.state:
            self.state.finish(status)
        self.state = None; self.path = None
        if self.pending:
            _, error = self.pending; self.pending = None
            error(reject('Transfer ' + status, True))

    @dbus.service.method('org.bluez.obex.Agent1', in_signature='', out_signature='')
    def Release(self): self.finish('cancelled')

    @dbus.service.method('org.bluez.obex.Agent1', in_signature='', out_signature='')
    def Cancel(self): self.finish('cancelled')

    @dbus.service.method('org.bluez.obex.Agent1', in_signature='o', out_signature='s', async_callbacks=('reply','error'))
    def AuthorizePush(self, transfer, reply, error):
        if self.state:
            error(reject('Another transfer is active',True)); return
        try:
            obj = self.bus.get_object('org.bluez.obex', transfer)
            props = dbus.Interface(obj,'org.freedesktop.DBus.Properties').GetAll('org.bluez.obex.Transfer1')
            session = self.bus.get_object('org.bluez.obex',props['Session'])
            remote = dbus.Interface(session,'org.freedesktop.DBus.Properties').Get('org.bluez.obex.Session1','Destination')
            name = Path(str(props.get('Name') or props.get('Filename') or 'Bluetooth file')).name
            if name in ('','.','..'): name='Bluetooth file'
            self.state = TransferState('incoming',str(remote),name,int(props.get('Size',0)))
            self.path = str(transfer); self.pending = (reply,error)
            self.deadline = time.monotonic()+35
            subprocess.Popen([str(Path(__file__).with_name('bluetooth-transfer-ui.sh')),self.state.token])
            GLib.timeout_add(150,self.tick)
        except Exception as exc:
            if self.state: self.finish('error')
            else: error(reject(str(exc),True))

    def tick(self):
        if not self.state:return False
        action = self.state.action()
        if time.monotonic() > self.deadline or action in ('decline','cancel'):
            if not self.pending:
                try: dbus.Interface(self.bus.get_object('org.bluez.obex',self.path),'org.bluez.obex.Transfer1').Cancel()
                except dbus.DBusException as exc: print(exc,file=sys.stderr)
            self.finish('rejected' if self.pending else 'cancelled')
            return False
        if self.pending and action=='accept':
            reply,error=self.pending
            try:
                download = subprocess.run(['xdg-user-dir','DOWNLOAD'],capture_output=True,text=True,timeout=2)
                folder=Path(download.stdout.strip()) if download.returncode==0 and download.stdout.strip() else Path.home()/'Downloads'
                folder.mkdir(parents=True,exist_ok=True)
                # Unique destination: never overwrite an existing download or symlink.
                target=folder/(uuid.uuid4().hex[:12]+'-'+self.state.data['filename'])
                self.pending=None
                self.deadline=time.monotonic()+300
                self.state.write(status='transferring')
                reply(str(target))
            except Exception as exc:
                self.pending=None; error(reject(str(exc),True));self.finish('error');return False
        return True

    def changed(self, interface, changed, invalidated, path=None):
        if interface!='org.bluez.obex.Transfer1' or str(path)!=self.path or not self.state:return
        amount=int(changed.get('Transferred',self.state.data['transferred']))
        total=int(changed.get('Size',self.state.data['size']))
        self.state.write(size=total,transferred=amount,progress=min(1,amount/total) if total else 0)
        status=str(changed.get('Status',''))
        if status in ('complete','error'):self.finish(status)


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    system=dbus.SystemBus();session=dbus.SessionBus()
    agent=BluetoothAgent(system);obex=ObexAgent(session)
    session.add_signal_receiver(obex.changed, dbus_interface='org.freedesktop.DBus.Properties',
                               signal_name='PropertiesChanged',path_keyword='path')
    def register_bluez(*args):
        try:
            manager=dbus.Interface(system.get_object('org.bluez','/org/bluez'),'org.bluez.AgentManager1')
            manager.RegisterAgent(AGENT_PATH,'KeyboardDisplay');manager.RequestDefaultAgent(AGENT_PATH)
        except dbus.DBusException as exc:print('Pairing agent registration:',exc,file=sys.stderr)
    def register_obex(*args):
        try:
            manager=dbus.Interface(session.get_object('org.bluez.obex','/org/bluez/obex'),'org.bluez.obex.AgentManager1')
            manager.RegisterAgent(OBEX_AGENT_PATH)
        except dbus.DBusException as exc:print('OBEX agent registration:',exc,file=sys.stderr)
    def bluez_owner(name,old,new):
        agent.Cancel()
        if new:register_bluez()
    def obex_owner(name,old,new):
        obex.finish('error')
        if new:register_obex()
    system.add_signal_receiver(bluez_owner,signal_name='NameOwnerChanged',dbus_interface='org.freedesktop.DBus',arg0='org.bluez')
    session.add_signal_receiver(obex_owner,signal_name='NameOwnerChanged',dbus_interface='org.freedesktop.DBus',arg0='org.bluez.obex')
    subprocess.run(['systemctl','--user','start','obex.service'],check=True,timeout=10)
    register_bluez();register_obex()
    try:GLib.MainLoop().run()
    finally:agent.Cancel();obex.finish('cancelled')

if __name__=='__main__':main()
