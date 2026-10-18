"""Serialized OBEX ownership with token-bound UI actions and atomic state files."""
import fcntl
import json
import os
from pathlib import Path
import tempfile
import uuid


def runtime():
    return Path(os.environ.get('MINIMAL_RUNTIME') or (Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'minimal'))


def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.transfer-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream)
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


class TransferState:
    def __init__(self, direction, device, filename, size=0):
        # OBEX is user-wide. Serialize transfers even across compositor sessions.
        shared = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'minimal'
        shared.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = (shared / 'obex-transfer.lock').open('a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise RuntimeError('Another Bluetooth transfer is already active')
        self.path = runtime() / 'bt-transfer.json'
        self.token = uuid.uuid4().hex
        self.action_path = runtime() / ('bt-action-' + self.token)
        self.data = dict(id=self.token, direction=direction, device=device, filename=filename,
                         size=size, transferred=0, progress=0, active=True, status='request')
        self.write()

    def write(self, **changes):
        self.data.update(changes)
        atomic_json(self.path, self.data)

    def action(self):
        try:
            action = self.action_path.read_text().strip()
            self.action_path.unlink(missing_ok=True)
            return action
        except FileNotFoundError:
            return None

    def finish(self, status):
        self.write(status=status, active=False, progress=1 if status == 'complete' else self.data['progress'])
        self.action_path.unlink(missing_ok=True)
        self.lock.close()


def submit_action(token, action):
    if action not in ('accept', 'decline', 'cancel') or len(token) != 32 or any(c not in '0123456789abcdef' for c in token):
        raise ValueError('Invalid transfer action')
    data = json.loads((runtime() / 'bt-transfer.json').read_text())
    if data.get('id') != token or not data.get('active'):
        raise ValueError('This transfer is no longer active')
    path = runtime() / ('bt-action-' + token)
    # First decision wins: repeated clicks cannot replace an earlier response.
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return
    with os.fdopen(fd, 'w') as stream:
        stream.write(action)
