#!/usr/bin/env python3
"""Bluetooth File Transfer (OBEX OPP) Sender for Minimal Desktop.

Allows sending files to paired or connected Bluetooth devices using
BlueZ's native D-Bus OBEX Client interface (org.bluez.obex.Client1).
"""
import json
import os
import re
import shutil
import subprocess
import sys


def notify(title, message, urgency="normal", icon="bluetooth"):
    if shutil.which("notify-send"):
        subprocess.run(
            ["notify-send", "-a", "Bluetooth", "-i", icon, "-u", urgency, title, message],
            capture_output=True,
        )


def get_paired_devices():
    devices = []
    if not shutil.which("bluetoothctl"):
        return devices
    try:
        proc = subprocess.run(
            ["bluetoothctl", "devices", "Paired"],
            capture_output=True,
            text=True,
            timeout=3.0,
        )
        for line in proc.stdout.splitlines():
            parts = line.strip().split(maxsplit=2)
            if len(parts) >= 3 and parts[0] == "Device":
                devices.append((parts[1], parts[2]))
        # Also include connected devices
        proc_conn = subprocess.run(
            ["bluetoothctl", "devices", "Connected"],
            capture_output=True,
            text=True,
            timeout=3.0,
        )
        for line in proc_conn.stdout.splitlines():
            parts = line.strip().split(maxsplit=2)
            if len(parts) >= 3 and parts[0] == "Device":
                if not any(d[0] == parts[1] for d in devices):
                    devices.append((parts[1], parts[2]))
    except Exception:
        pass
    return devices


def select_target_device():
    devices = get_paired_devices()
    if not devices:
        notify(
            "No Bluetooth Devices Found",
            "Please pair your phone or target device first in Settings.",
            urgency="critical",
            icon="dialog-error",
        )
        sys.exit(1)

    if len(devices) == 1:
        return devices[0][0], devices[0][1]

    if shutil.which("zenity"):
        cmd = [
            "zenity",
            "--list",
            "--title=Select Bluetooth Target Device",
            "--column=Address",
            "--column=Device Name",
            "--print-column=1",
            "--width=420",
            "--height=260",
        ]
        for mac, name in devices:
            cmd.extend([mac, name])
        res = subprocess.run(cmd, capture_output=True, text=True)
        chosen = res.stdout.strip()
        if not chosen:
            sys.exit(0)
        chosen_mac = chosen.split("|")[0].strip()
        chosen_name = next((d[1] for d in devices if d[0] == chosen_mac), chosen_mac)
        return chosen_mac, chosen_name

    notify("Select a Bluetooth device", "Install zenity to choose among multiple devices.", urgency="critical")
    sys.exit(1)


def select_file():
    if shutil.which("zenity"):
        res = subprocess.run(
            ["zenity", "--file-selection", "--title=Select File to Send via Bluetooth"],
            capture_output=True,
            text=True,
        )
        chosen = res.stdout.strip()
        if chosen:
            return chosen
        sys.exit(0)
    print("Error: No file specified and zenity not available.", file=sys.stderr)
    sys.exit(1)


def main():
    target_mac = None
    target_name = None
    filepath = None

    args = sys.argv[1:]
    if args:
        # Check if first arg is a MAC address
        if re.match(r"^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$", args[0]):
            target_mac = args[0]
            if len(args) > 1:
                filepath = args[1]
        elif os.path.exists(args[0]):
            filepath = args[0]

    if not target_mac:
        target_mac, target_name = select_target_device()
    else:
        # Find display name if available
        for mac, name in get_paired_devices():
            if mac.lower() == target_mac.lower():
                target_name = name
                break
        if not target_name:
            target_name = target_mac

    if not filepath:
        filepath = select_file()

    if not os.path.isfile(filepath):
        notify(
            "File Not Found",
            f"The file '{filepath}' does not exist.",
            urgency="critical",
            icon="dialog-error",
        )
        sys.exit(1)

    abs_path = os.path.abspath(filepath)
    basename = os.path.basename(abs_path)

    try:
        import dbus
        import dbus.mainloop.glib
        from gi.repository import GLib
    except ImportError:
        notify(
            "Dependency Missing",
            "python-dbus or PyGObject is missing for Bluetooth file transfer.",
            urgency="critical",
            icon="dialog-error",
        )
        sys.exit(1)

    # Ensure obex service is running
    subprocess.run(["systemctl", "--user", "start", "obex"], capture_output=True)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        session_bus = dbus.SessionBus()
    except Exception as e:
        notify(
            "D-Bus Error",
            f"Could not connect to session D-Bus: {e}",
            urgency="critical",
            icon="dialog-error",
        )
        sys.exit(1)

    try:
        client = dbus.Interface(
            session_bus.get_object("org.bluez.obex", "/org/bluez/obex"),
            "org.bluez.obex.Client1",
        )
    except Exception as e:
        notify(
            "OBEX Daemon Unavailable",
            f"Could not connect to OBEX service: {e}",
            urgency="critical",
            icon="dialog-error",
        )
        sys.exit(1)

    notify(
        "Bluetooth File Transfer",
        f"Connecting to {target_name} to send '{basename}'...",
        icon="document-send",
    )

    try:
        session_path = client.CreateSession(target_mac, {"Target": "opp"})
    except Exception as e:
        notify(
            "Bluetooth Connection Failed",
            f"Could not open file transfer session with {target_name}: {e}",
            urgency="critical",
            icon="dialog-error",
        )
        sys.exit(1)

    from transfer_state import TransferState
    state = None
    transfer = None
    loop = GLib.MainLoop()
    result = [1]
    finished = [False]
    def finish(status):
        if finished[0]: return False
        finished[0] = True
        result[0] = 0 if status == "complete" else 1
        try:
            client.RemoveSession(session_path)
        except dbus.DBusException as error:
            print("OBEX session cleanup:", error, file=sys.stderr)
        if state:
            state.finish(status)
        loop.quit()
        return False
    def cancel(status="cancelled"):
        if transfer:
            try:
                transfer.Cancel()
            except dbus.DBusException as error:
                print("Transfer cancellation:", error, file=sys.stderr)
        return finish(status)
    def tick():
        if finished[0]: return False
        if state.action() == "cancel": return cancel()
        return True
    def on_transfer_props_changed(interface, changed, invalidated, path=None):
        if interface != "org.bluez.obex.Transfer1" or path != transfer_path or finished[0]: return
        if "Transferred" in changed:
            amount = int(changed["Transferred"])
            state.write(status="transferring", transferred=amount,
                        progress=min(1, amount / total_size) if total_size else 0)
        status = str(changed.get("Status", ""))
        if status in ("complete", "error"):
            finish(status)
            notify("Bluetooth file sent" if status == "complete" else "Bluetooth transfer failed", basename)
    try:
        total_size = os.path.getsize(abs_path)
        state = TransferState("outgoing", target_name, basename, total_size)
        state.write(status="transferring")
        ui_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bluetooth-transfer-ui.sh")
        subprocess.Popen([ui_script, state.token])
        opp = dbus.Interface(session_bus.get_object("org.bluez.obex", session_path), "org.bluez.obex.ObjectPush1")
        transfer_path, props = opp.SendFile(abs_path)
        transfer = dbus.Interface(session_bus.get_object("org.bluez.obex", transfer_path), "org.bluez.obex.Transfer1")
        session_bus.add_signal_receiver(on_transfer_props_changed,
            dbus_interface="org.freedesktop.DBus.Properties", signal_name="PropertiesChanged", path_keyword="path")
        # Fetch current properties after subscribing: completion may race SendFile.
        current = dbus.Interface(session_bus.get_object("org.bluez.obex", transfer_path),
                                 "org.freedesktop.DBus.Properties").GetAll("org.bluez.obex.Transfer1")
        on_transfer_props_changed("org.bluez.obex.Transfer1", current, [], path=transfer_path)
        GLib.timeout_add(150, tick)
        GLib.timeout_add_seconds(300, lambda: cancel("error"))
        if not finished[0]: loop.run()
    except (Exception, KeyboardInterrupt) as error:
        print(error, file=sys.stderr)
        cancel("error")
    finally:
        if not finished[0]: cancel("error")
    sys.exit(result[0])


if __name__ == "__main__":
    main()
