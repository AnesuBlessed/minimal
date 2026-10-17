"""Integration checks in temporary directories; never touch the live desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ('hypr', 'waybar', 'wlogout', 'fuzzel', 'foot', 'mako', 'fastfetch', 'minimal')


class MinimalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='minimal test ')
        self.base = Path(self.temp.name)
        self.repo = self.base / 'source rice'
        self.repo.mkdir()
        for directory in ('hypr', 'waybar', 'wlogout', 'fuzzel', 'foot', 'mako', 'fastfetch', 'scripts', 'quickshell', 'assets'):
            shutil.copytree(ROOT / directory, self.repo / directory, symlinks=True)
        for filename in ('deploy.sh', 'restore.sh', 'bootstrap.sh', 'colors.css', 'theme.json'):
            shutil.copy2(ROOT / filename, self.repo / filename)
        self.config = self.base / 'config'
        self.config.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.trace = self.base / 'trace.jsonl'
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        XDG_CONFIG_HOME=str(self.config), XDG_CACHE_HOME=str(self.base / 'cache'),
                        XDG_STATE_HOME=str(self.base / 'state'), XDG_RUNTIME_DIR=str(self.base / 'runtime'),
                        MOCK_TRACE=str(self.trace), MINIMAL_ROOT=str(self.repo))
        (self.base / 'runtime').mkdir()
        (self.base / 'home').mkdir()
        self.env['HOME'] = str(self.base / 'home')
        self.env['XDG_DATA_HOME'] = str(self.base / 'data')
        self.env.pop('WAYLAND_DISPLAY', None)
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        self.mock('systemctl', '')
        self.mock('systemd-run', '')
        self.mock('makoctl', '')
        self.mock('sudo', 'sys.exit(99)')
        self.mock('pacman', '')
        self.mock('fc-match', "print('JetBrainsMono Nerd Font')")
        self.mock('inotifywait', '')
        self.mock('mpvpaper', '')
        self.mock('hyprsunset', '')
        self.mock('gnome-keyring-daemon', '')
        self.mock('fusermount3', 'sys.exit(99)')
        self.mock('fusermount', 'sys.exit(99)')
        self.mock('brightnessctl', "print('500' if sys.argv[-1] == 'max' else '250')")

    def tearDown(self):
        self.temp.cleanup()

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/usr/bin/python3\nimport os,sys,json\n' +
                        'with open(os.environ["MOCK_TRACE"], "a") as f: f.write(json.dumps([os.path.basename(sys.argv[0]), *sys.argv[1:]]) + "\\n")\n' + body + '\n')
        path.chmod(0o755)

    def run_script(self, name, *args, expected=0):
        result = subprocess.run([str(self.repo / name), *args], env=self.env, text=True,
                                capture_output=True, timeout=30)
        if expected is not None:
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_clipboard_text_preview_is_bounded(self):
        self.mock('cliphist', "sys.stdout.write('x' * 200000)")
        result = self.run_script('quickshell/clipboard/clip_fetcher.py', '--text', '123')
        self.assertTrue(result.stdout.startswith('x' * 65536))
        self.assertIn('Preview truncated', result.stdout)
        self.assertLess(len(result.stdout), 65700)

    def test_image_preview_rejects_invalid_and_bounds_thumbnail(self):
        from PIL import Image
        source = self.base / 'picture.png'
        target = self.base / 'thumb.png'
        Image.new('RGB', (1600, 1000)).save(source)
        self.run_script('scripts/image-preview.py', str(source), str(target))
        with Image.open(target) as image:
            self.assertLessEqual(image.width, 800)
            self.assertLessEqual(image.height, 420)
        source.write_text('<html>not an image</html>')
        self.assertNotEqual(self.run_script('scripts/image-preview.py', str(source), expected=None).returncode, 0)

    def test_search_apply_rejects_local_url_and_path_traversal(self):
        cache = self.base / 'search'
        cache.mkdir()
        self.env['QS_CACHE_WALLPAPER_PICKER'] = str(cache)
        (cache / 'search_map.txt').write_text('image.jpg|file:///etc/passwd\n')
        for name in ('image.jpg', '../escape.jpg', 'missing.jpg'):
            result = self.run_script('quickshell/wallpaper-picker/apply-search.sh', name, 'all', expected=None)
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.repo / 'wallpapers/image.jpg').exists())
        self.assertFalse(self.trace.exists())

    def test_optional_build_failure_keeps_idle_lock_startup(self):
        for name in ('prepare-lock.sh', 'hardware-detect.sh', 'restore-wallpapers.sh', 'session-conflicts.py'):
            (self.repo / 'scripts' / name).write_text('#!/bin/sh\nexit 0\n')
        (self.repo / 'scripts/build-native.sh').write_text('#!/bin/sh\nexit 1\n')
        self.mock('systemctl', "sys.exit(3 if 'is-active' in sys.argv else 0)")
        self.mock('dbus-update-activation-environment', '')
        self.mock('notify-send', '')
        self.mock('pgrep', '')
        self.run_script('scripts/session-start.sh')
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()]
        starts = [call for call in calls if call[0] == 'systemd-run']
        self.assertTrue(any('hypridle' in call for call in starts))
        self.assertTrue(any('--unit=minimal-default-waybar' in call for call in starts))
        self.assertFalse(any('--unit=minimal-default-automount' in call for call in starts))

    def test_partial_video_failure_stops_started_units(self):
        # Stand-in preview apply verifies descriptor inheritance without a compositor.
        (self.repo / 'scripts/wallpaper.sh').write_text('#!/bin/bash\nflock -n 9 || exit 70\n')
        self.mock('systemd-run', "sys.exit(1 if 'DP-2' in sys.argv else 0)")
        video = self.base / 'video.mp4'
        video.touch()
        result = self.run_script('scripts/wallpaper-video.sh', str(video), 'DP-1,DP-2', 'preview', expected=None)
        self.assertNotEqual(result.returncode, 0)
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()]
        starts = [call for call in calls if call[0] == 'systemd-run']
        self.assertEqual(len(starts), 2)
        for call in starts:
            self.assertIn('--property=Type=exec', call)
            unit = next(arg.split('=', 1)[1] for arg in call if arg.startswith('--unit='))
            self.assertIn(['systemctl', '--user', 'stop', unit + '.service'], calls)
        self.assertFalse((self.base / 'state/minimal/wallpapers.json').exists())

    def test_clipboard_search_reuses_results_and_invalidates_on_history_change(self):
        listing = self.base / 'listing'
        listing.write_text('2\tSecond\n1\tFirst\n')
        self.env['TEST_LISTING'] = str(listing)
        self.mock('cliphist', "if sys.argv[1]=='list': print(open(os.environ['TEST_LISTING']).read(), end='')\nelse: print('needle')")
        cache = self.base / 'clipboard'
        for offset in ('0', '1'):
            self.run_script('quickshell/clipboard/clip_fetcher.py', offset, '1', str(cache), 'needle')
        self.assertEqual(sum(e[:2] == ['cliphist', 'decode'] for e in self.events()), 2)
        listing.write_text('3\tThird\n' + listing.read_text())
        self.run_script('quickshell/clipboard/clip_fetcher.py', '0', '1', str(cache), 'needle')
        self.assertEqual(sum(e[:2] == ['cliphist', 'decode'] for e in self.events()), 5)

    def test_power_action_checks_capabilities(self):
        self.mock('busctl', "print('s \"na\"')")
        self.mock('notify-send', '')
        self.run_script('scripts/power-action.sh', 'hibernate', expected=1)
        self.assertFalse(any(e[0] == 'systemctl' for e in self.events()))
        self.mock('busctl', "print('s \"yes\"')")
        for action in ('suspend', 'hibernate', 'reboot', 'poweroff'):
            self.run_script('scripts/power-action.sh', action)
            self.assertIn(['systemctl', action], self.events())

    def test_terminal_uses_server_without_waiting_for_shell_exit(self):
        import socket
        self.env['WAYLAND_DISPLAY'] = 'wayland-test'
        self.mock('footclient', '')
        self.mock('foot', '')
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(self.base / 'runtime/foot-wayland-test.sock'))
            self.run_script('scripts/terminal.sh', 'sh', '-c', 'exit 1')
        self.assertIn(['footclient', '--no-wait', '--client-environment', 'sh', '-c', 'exit 1'], self.events())
        self.assertFalse(any(e[0] == 'foot' for e in self.events()))

    def test_restore_groups_identical_monitor_wallpapers(self):
        state = self.base / 'state/minimal'
        state.mkdir(parents=True)
        wall = self.base / 'wall.png'
        wall.touch()
        selection = dict(path=str(wall), kind='image', preview=str(wall))
        (state / 'wallpapers.json').write_text(json.dumps({'DP-1': selection, 'DP-2': selection}))
        self.mock('hyprctl', '')
        (self.repo / 'scripts/wallpaper.sh').write_text('#!/bin/sh\nprintf "%s" "$2" > "$XDG_STATE_HOME/outputs"\n')
        self.run_script('scripts/restore-wallpapers.sh')
        self.assertEqual((self.base / 'state/outputs').read_text(), 'DP-1,DP-2')

    def originals(self):
        for component in COMPONENTS:
            (self.config / component).mkdir()
            (self.config / component / 'sentinel').write_text('original-' + component)

    def assert_originals(self):
        for component in COMPONENTS:
            self.assertFalse((self.config / component).is_symlink(), component)
            self.assertEqual((self.config / component / 'sentinel').read_text(), 'original-' + component)

    def test_restore_directories_and_leave_dunst_untouched(self):
        self.originals()
        (self.config / 'dunst').mkdir()
        (self.config / 'dunst/dunstrc').write_text('keep')
        self.run_script('deploy.sh')
        self.run_script('restore.sh')
        self.assert_originals()
        self.assertEqual((self.config / 'dunst/dunstrc').read_text(), 'keep')

    def test_restore_absent_entries(self):
        self.run_script('deploy.sh')
        self.run_script('restore.sh')
        for component in COMPONENTS:
            self.assertFalse(os.path.lexists(self.config / component), component)

    def test_restore_symlinks_including_dangling(self):
        target = self.base / 'external'
        target.mkdir()
        (target / 'sentinel').write_text('untouched')
        (self.config / 'hypr').symlink_to(target)
        (self.config / 'foot').symlink_to('../missing-target')
        self.run_script('deploy.sh')
        self.run_script('restore.sh')
        self.assertEqual(os.readlink(self.config / 'hypr'), str(target))
        self.assertEqual(os.readlink(self.config / 'foot'), '../missing-target')
        self.assertEqual((target / 'sentinel').read_text(), 'untouched')

    def test_failed_backup_does_not_change_originals(self):
        self.originals()
        self.mock('cp', 'sys.exit(1)')
        self.run_script('deploy.sh', expected=1)
        self.assert_originals()

    def test_failed_link_rolls_back_every_changed_component(self):
        self.originals()
        self.mock('ln', 'if sys.argv[-1].endswith("/waybar"): sys.exit(1)\nos.execv("/usr/bin/ln", ["ln", *sys.argv[1:]])')
        self.run_script('deploy.sh', expected=1)
        self.assert_originals()

    def test_failed_restore_copy_keeps_installation_intact(self):
        self.originals()
        self.run_script('deploy.sh')
        self.mock('cp', 'sys.exit(1)')
        self.run_script('restore.sh', expected=1)
        for component in COMPONENTS:
            self.assertTrue((self.config / component).is_symlink())

    def test_failed_restore_move_rolls_back_installation(self):
        self.originals()
        self.run_script('deploy.sh')
        self.mock('mv', 'if "/staged/waybar" in sys.argv[-2]: sys.exit(1)\nos.execv("/usr/bin/mv", ["mv", *sys.argv[1:]])')
        self.run_script('restore.sh', expected=1)
        for component in COMPONENTS:
            self.assertTrue((self.config / component).is_symlink())
        (self.bin / 'mv').unlink()
        self.run_script('restore.sh')
        self.assert_originals()

    def test_redeployment_is_noop_and_original_backup_remains(self):
        self.originals()
        self.run_script('deploy.sh')
        before = list((self.config / 'backups').glob('minimal-*'))
        self.run_script('deploy.sh')
        self.assertEqual(before, list((self.config / 'backups').glob('minimal-*')))
        self.run_script('restore.sh')
        self.assert_originals()

    def test_restore_preserves_external_replacement(self):
        self.run_script('deploy.sh')
        (self.config / 'waybar').unlink()
        (self.config / 'waybar').mkdir()
        (self.config / 'waybar/custom').write_text('keep')
        self.run_script('restore.sh', expected=1)
        self.assertEqual((self.config / 'waybar/custom').read_text(), 'keep')
        self.assertTrue((self.config / 'hypr').is_symlink())

    def test_preflight_does_not_install(self):
        self.run_script('deploy.sh', '--check')
        self.assertEqual(list(self.config.iterdir()), [])

    def test_css_loads_through_deployed_symlink(self):
        import gi
        gi.require_version('Gtk', '3.0')
        from gi.repository import Gtk
        self.run_script('deploy.sh')
        Gtk.CssProvider().load_from_path(str(self.config / 'waybar/style.css'))

    def events(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def test_volume_osd_uses_actual_volume_and_replacement_tag(self):
        self.mock('wpctl', 'if sys.argv[1] == "get-volume": print("Volume: 0.57")')
        self.mock('notify-send', '')
        self.run_script('scripts/media.sh', 'volume', 'up')
        events = self.events()
        self.assertIn(['wpctl', 'set-volume', '-l', '1.0', '@DEFAULT_AUDIO_SINK@', '5%+'], events)
        notification = next(event for event in events if event[0] == 'notify-send')
        self.assertIn('int:value:57', notification)
        self.assertIn('string:x-canonical-private-synchronous:volume', notification)

    def test_muted_mic_osd(self):
        self.mock('wpctl', 'if sys.argv[1] == "get-volume": print("Volume: 0.95 [MUTED]")')
        self.mock('notify-send', '')
        self.run_script('scripts/media.sh', 'mic', 'mute')
        notification = self.events()[-1]
        self.assertIn('int:value:0', notification)
        self.assertIn('Microphone muted', notification[-1])

    def test_failed_control_does_not_report_success(self):
        self.mock('wpctl', 'sys.exit(1)')
        self.mock('notify-send', '')
        self.run_script('scripts/media.sh', 'volume', 'up', expected=1)
        self.assertFalse(any(event[0] == 'notify-send' for event in self.events()))

    def test_brightness_uses_screen_device_and_safe_minimum(self):
        self.mock('notify-send', '')
        self.run_script('scripts/media.sh', 'brightness', 'down')
        self.assertIn(['brightnessctl', '--class=backlight', '--min-value=1', 'set', '5%-'], self.events())
        self.assertIn('int:value:50', self.events()[-1])

    def test_launcher_uses_owned_quickshell_popup(self):
        self.mock('hyprctl', 'print(json.dumps([{"focused":True,"name":"test","height":768,"width":1366,"scale":1,"transform":0}]))')
        self.mock('quickshell', 'assert os.environ["MINIMAL_LAUNCHER_OUTPUT"] == "test"')
        self.run_script('scripts/launcher.sh')
        calls = [e for e in self.events() if e[0] == 'quickshell']
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1:], ['-n', '-p', str(self.repo / 'quickshell/launcher/shell.qml')])

    def test_launcher_search_actions_and_launch(self):
        source = (self.repo / 'quickshell/launcher/shell.qml').read_text()
        harness = self.repo / 'quickshell/launcher/regression.qml'
        checks = r"""
    Timer {
        interval: 100; running: true
        onTriggered: {
            function check(ok, label) {
                if (!ok) throw new Error(label);
            }
            try {
                const fixture = {name: "Fixture Browser", genericName: "Web Browser",
                    id: "fixture", comment: "Browse websites", keywords: ["internet"],
                    categories: ["Network"], icon: "", noDisplay: false,
                    runInTerminal: false, actions: [{name: "Private Window", icon: "",
                        execute: function() { console.log("REGRESSION_PASS action launched"); }}]};
                root.entries = [fixture, Object.assign({}, fixture, {name: "Hidden", noDisplay: true})];
                root.query = "";
                root.refresh();
                check(root.results.length === 1, "hidden entry filtering");
                root.query = "fxbr";
                check(root.results.length > 0, "fuzzy matching");
                root.query = "internet";
                check(root.results.length === 1, "keyword matching");
                root.query = "zzzzzzzzzzzz";
                check(root.results.length === 0 && list.currentIndex === -1, "empty results");
                root.launch(-1);
                root.query = "private";
                check(root.results.length === 1 && root.results[0].action !== null, "desktop actions");
                root.launch(0);
            } catch (error) {
                console.log("REGRESSION_FAIL", error);
                Qt.quit();
            }
        }
    }
"""
        # Exercise the production search/launch logic without a Wayland surface.
        logic = source[:source.index('    PanelWindow {')]
        harness.write_text(logic + '    QtObject { id: list; property int currentIndex: -1 }\n' + checks + '}')
        env = dict(self.env, QT_QPA_PLATFORM='offscreen')
        result = subprocess.run(['quickshell', '-n', '-p', str(harness)], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('REGRESSION_PASS action launched', output)
        self.assertNotIn('REGRESSION_FAIL', output)

    def test_launcher_position_and_scaled_monitor(self):
        self.mock('hyprctl', 'print(json.dumps([{"focused":True,"name":"test","height":1536,"width":2732,"scale":2,"transform":0}]))')
        self.mock('fuzzel', '')
        self.run_script('scripts/launcher.sh', '--fallback')
        args = self.events()[-1]
        self.assertEqual(args[args.index('--y-margin') + 1], '0')
        self.assertEqual(args[args.index('--anchor') + 1], 'bottom')
        self.assertEqual(args[args.index('--output') + 1], 'test')

    def test_launcher_does_not_kill_unowned_fuzzel(self):
        self.mock('pgrep', 'sys.exit(0)')
        self.mock('pkill', '')
        self.mock('fuzzel', '')
        self.run_script('scripts/launcher.sh', '--fallback')
        self.assertFalse(any(e[0] == 'pkill' for e in self.events()))
        self.assertTrue(any(e[0] == 'fuzzel' for e in self.events()))

    def test_launcher_cancels_cleanly_on_fuzzel_exit(self):
        self.mock('fuzzel', 'sys.exit(1)')
        result = self.run_script('scripts/launcher.sh', '--fallback', expected=0)
        self.assertEqual(result.returncode, 0)

    def test_failed_wallpaper_preserves_saved_selection(self):
        self.mock('hyprctl', 'sys.exit(1)')
        state = self.base / 'state/minimal'
        state.mkdir(parents=True)
        (state / 'current_wallpaper').write_text('previous')
        image = self.base / 'wall.png'
        image.write_text('fixture')
        self.run_script('scripts/wallpaper.sh', str(image), expected=1)
        self.assertEqual((state / 'current_wallpaper').read_text(), 'previous')

    def test_battery_detects_hardware_without_fixed_name(self):
        batteries = self.base / 'power'
        battery = batteries / 'BAT9'
        battery.mkdir(parents=True)
        for key, value in {'type':'Battery','capacity':'63','status':'Charging'}.items():
            (battery / key).write_text(value + '\n')
        self.env['MINIMAL_POWER_SUPPLY_ROOT'] = str(batteries)
        self.assertIn('63% · Plugged in', self.run_script('scripts/battery-status.sh').stdout)

    def test_palette_and_lock_cache_preserve_launcher_geometry(self):
        from PIL import Image
        image = self.base / "wall with ' quotes.png"
        Image.new('RGB', (64, 64), 'purple').save(image)
        self.run_script('scripts/update_fuzzel_colors.py', str(image))
        self.assertIn('width=56', (self.repo / 'fuzzel/fuzzel.ini').read_text())
        self.run_script('scripts/prepare-lock.sh', str(image))
        cached = self.base / 'cache/minimal/lock.png'
        self.assertTrue(cached.is_file())
        stamp = cached.stat().st_mtime_ns
        self.run_script('scripts/prepare-lock.sh', str(image))
        self.assertEqual(stamp, cached.stat().st_mtime_ns)

    def test_battery_monitor_warning_and_emergency_suspend(self):
        batteries = self.base / 'power'
        battery = batteries / 'BAT0'
        battery.mkdir(parents=True)
        (battery / 'type').write_text('Battery\n')
        (battery / 'status').write_text('Discharging\n')
        self.env['MINIMAL_POWER_SUPPLY_ROOT'] = str(batteries)

        self.mock('notify-send', '')
        self.mock('systemctl', '')
        self.mock('systemd-run', '')
        self.mock('makoctl', '')
        self.mock('sudo', 'sys.exit(99)')
        self.mock('pacman', '')
        self.mock('fc-match', "print('JetBrainsMono Nerd Font')")
        self.mock('fusermount3', 'sys.exit(99)')
        self.mock('fusermount', 'sys.exit(99)')

        # Test Low Battery (20%)
        (battery / 'capacity').write_text('20\n')
        self.run_script('scripts/battery-monitor.sh', '--check')
        events = self.events()
        self.assertTrue(any(e[0] == 'notify-send' and any('Low Battery' in arg for arg in e) for e in events))

        # Test Critical Battery (10%)
        (battery / 'capacity').write_text('10\n')
        self.run_script('scripts/battery-monitor.sh', '--check')
        events = self.events()
        self.assertTrue(any(e[0] == 'notify-send' and any('Critical Battery' in arg for arg in e) for e in events))

        # Test Emergency Suspend (4%)
        (battery / 'capacity').write_text('4\n')
        self.run_script('scripts/battery-monitor.sh', '--check')
        events = self.events()
        self.assertTrue(any(e[0] == 'systemctl' and 'suspend' in e for e in events))

    def test_notification_controls_invoke_daemon(self):
        self.mock('makoctl', 'if sys.argv[1] == "mode": print("default")')
        self.mock('notify-send', '')
        self.run_script('scripts/notifications.sh', 'dismiss')
        self.run_script('scripts/notifications.sh', 'restore')
        self.run_script('scripts/notifications.sh', 'dnd')
        events = self.events()
        self.assertIn(['makoctl', 'dismiss'], events)
        self.assertIn(['makoctl', 'restore'], events)
        self.assertTrue(any(e[0] == 'makoctl' and 'mode' in e for e in events))

    def test_hardware_detect_live_intel_haswell(self):
        self.env['MINIMAL_MOCK_LSPCI'] = '00:02.0 VGA compatible controller [0300]: Intel Corporation Haswell [8086:0a16]\n\tKernel driver in use: i915\n'
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(self.base / 'nonexistent_drm')
        self.env['MINIMAL_MOCK_PLATFORM'] = 'baremetal'
        # Test --print flag
        print_res = self.run_script('scripts/hardware-detect.sh', '--print')
        self.assertIn('MINIMAL HARDWARE & GPU AUTO-DETECTION SUMMARY', print_res.stdout)
        self.assertIn('LIBVA_DRIVER_NAME="i965"', print_res.stdout)
        self.assertIn('HYPR_VFR="true"', print_res.stdout)
        self.assertIn('HYPR_BLUR="false"', print_res.stdout)

        # Verify cache file written
        cached_env = self.base / 'cache/minimal/hardware.env'
        self.assertTrue(cached_env.is_file())
        env_content = cached_env.read_text()
        self.assertIn('export LIBVA_DRIVER_NAME="i965"', env_content)
        self.assertIn('export GPU_VENDOR="intel"', env_content)
        self.assertIn('export GPU_FAMILY="haswell"', env_content)

        # Test --export flag
        export_res = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export LIBVA_DRIVER_NAME="i965"', export_res.stdout)
        self.assertIn('export HYPR_VFR="true"', export_res.stdout)
        self.assertIn('export HYPR_BLUR="false"', export_res.stdout)

    def test_hardware_detect_modern_intel(self):
        mock_lspci = (
            "00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] [8086:9a49] (rev 01)\n"
            "\tSubsystem: Dell Device [1028:098e]\n"
            "\tKernel driver in use: i915\n"
        )
        self.env['MINIMAL_MOCK_LSPCI'] = mock_lspci
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(self.base / 'nonexistent_drm')
        res = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export LIBVA_DRIVER_NAME="iHD"', res.stdout)
        self.assertIn('export GPU_FAMILY="broadwell-plus"', res.stdout)
        self.assertIn('export HYPR_VFR="true"', res.stdout)

    def test_hardware_detect_amd(self):
        mock_lspci = (
            "05:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Cezanne [Radeon Vega Series] [1002:1638] (rev c5)\n"
            "\tSubsystem: Lenovo Device [17aa:3805]\n"
            "\tKernel driver in use: amdgpu\n"
        )
        self.env['MINIMAL_MOCK_LSPCI'] = mock_lspci
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(self.base / 'nonexistent_drm')
        res = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export LIBVA_DRIVER_NAME="radeonsi"', res.stdout)
        self.assertIn('export VDPAU_DRIVER="radeonsi"', res.stdout)
        self.assertIn('export AMD_VULKAN_ICD="RADV"', res.stdout)
        self.assertIn('export GPU_VENDOR="amd"', res.stdout)

    def test_hardware_detect_nvidia_proprietary(self):
        mock_lspci = (
            "01:00.0 3D controller [0302]: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile] [10de:2520] (rev a1)\n"
            "\tSubsystem: Lenovo Device [17aa:3a57]\n"
            "\tKernel driver in use: nvidia\n"
        )
        self.env['MINIMAL_MOCK_LSPCI'] = mock_lspci
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(self.base / 'nonexistent_drm')
        res = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export LIBVA_DRIVER_NAME="nvidia"', res.stdout)
        self.assertIn('export __GLX_VENDOR_LIBRARY_NAME="nvidia"', res.stdout)
        self.assertIn('export NVD_BACKEND="direct"', res.stdout)
        self.assertIn('export ELECTRON_OZONE_PLATFORM_HINT="auto"', res.stdout)
        self.assertIn('export GBM_BACKEND="nvidia-drm"', res.stdout)
        self.assertIn('export GPU_FAMILY="nvidia-proprietary"', res.stdout)

    def test_hardware_detect_nvidia_nouveau(self):
        mock_lspci = (
            "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK107 [GeForce GT 640] [10de:0fc1] (rev a1)\n"
            "\tSubsystem: ASUS Device [1043:8414]\n"
            "\tKernel driver in use: nouveau\n"
        )
        self.env['MINIMAL_MOCK_LSPCI'] = mock_lspci
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(self.base / 'nonexistent_drm')
        res = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export LIBVA_DRIVER_NAME="nouveau"', res.stdout)
        self.assertIn('export VDPAU_DRIVER="nouveau"', res.stdout)
        self.assertIn('export GPU_FAMILY="nvidia-nouveau"', res.stdout)

    def test_hardware_detect_virtual_machine(self):
        mock_lspci = (
            "00:02.0 VGA compatible controller [0300]: Red Hat, Inc. Virtio GPU [1af4:1050] (rev 01)\n"
            "\tKernel driver in use: virtio-pci\n"
        )
        self.env['MINIMAL_MOCK_LSPCI'] = mock_lspci
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(self.base / 'nonexistent_drm')
        self.env['MINIMAL_MOCK_PLATFORM'] = 'kvm'
        res = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export WLR_NO_HARDWARE_CURSORS="1"', res.stdout)
        self.assertIn('export WLR_RENDERER_ALLOW_SOFTWARE="1"', res.stdout)
        self.assertIn('export GPU_VENDOR="virtual"', res.stdout)

    def test_hyprland_lua_hardware_verification(self):
        # Verify Hyprland Lua syntax parses cleanly
        hypr_lua = self.repo / 'hypr/hyprland.lua'
        proc = subprocess.run(["Hyprland", "--verify-config", "-c", str(hypr_lua)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("config ok", proc.stdout)

    def test_waybar_modular_architecture(self):
        import re
        modules_dir = self.repo / 'waybar/modules'
        self.assertTrue(modules_dir.is_dir(), "waybar/modules directory must exist")
        module_files = list(modules_dir.glob('*.jsonc'))
        self.assertGreater(len(module_files), 50, "Should have 50+ modular jsonc files")

        forbidden = ['wallbash', 'rofilaunch', 'hl.dsp']
        for mf in module_files:
            text = mf.read_text(encoding='utf-8')
            for bad in forbidden:
                self.assertNotIn(bad, text, f"Found forbidden '{bad}' in {mf.name}")

        config_path = self.repo / 'waybar/config.jsonc'
        self.assertTrue(config_path.is_file(), "waybar/config.jsonc must exist")
        cfg_text = config_path.read_text(encoding='utf-8')
        # Check modular include directive
        self.assertIn('includes/includes.json', cfg_text)

        # Validate JSONC syntax & include tree without connecting to the live Wayland display.
        def parse_jsonc(path):
            raw = path.read_text(encoding='utf-8')
            stripped = re.sub(
                r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/',
                lambda m: m.group(1) if m.group(1) is not None else '',
                raw,
                flags=re.S,
            )
            stripped = re.sub(r',(\s*[}\]])', r'\1', stripped)
            return json.loads(stripped)

        main_cfg = parse_jsonc(config_path)
        includes_cfg = parse_jsonc(self.repo / 'waybar/includes/includes.json')
        defined_modules = set()
        for inc in includes_cfg.get('include', []):
            rel = inc.split('"/waybar/', 1)[-1]
            inc_path = self.repo / 'waybar' / rel
            self.assertTrue(inc_path.is_file(), f"Missing included module file: {inc_path}")
            mod_data = parse_jsonc(inc_path)
            defined_modules.update(mod_data.keys())

        for section in ('modules-left', 'modules-center', 'modules-right'):
            for group in main_cfg.get(section, []):
                self.assertIn(group, main_cfg, f"Group {group} missing in config.jsonc")
                for mod in main_cfg[group].get('modules', []):
                    if not mod.startswith(('hyprland/', 'tray', 'privacy', 'cpu', 'memory', 'clock', 'backlight', 'pulseaudio', 'battery')):
                        self.assertIn(mod, defined_modules, f"Module {mod} not defined in includes")

        # Verify waybar.sh reloads in place via SIGUSR2 when waybar is already running, never stacking a second bar.
        self.mock('pgrep', 'print("12345"); sys.exit(0)')
        self.mock('pkill', '')
        self.mock('waybar', '')
        self.run_script('scripts/waybar.sh')
        events = self.events()
        self.assertTrue(any(e[0] == 'systemctl' and '--signal=USR2' in e and e[-1].startswith('minimal-') for e in events))
        self.assertFalse(any(e[0] == 'pkill' for e in events))
        self.assertFalse(any(e[0] == 'waybar' for e in events))

    def test_wallpaper_picker_self_contained_files(self):
        wp_dir = ROOT / 'quickshell/wallpaper-picker'
        required_files = (
            'shell.qml', 'WallpaperPicker.qml', 'ddg_search.sh', 'get_ddg_links.py',
            'generate_thumbs.sh', 'Caching.qml', 'Scaler.qml', 'WindowRegistry.js',
            'MatugenColors.qml', 'GlobalTheme.qml', 'GlobalSettingsWatcher.qml', 'qmldir'
        )
        for req in required_files:
            self.assertTrue((wp_dir / req).is_file(), f"Missing required file: {req}")

        # Scripts must be executable
        for script in ('ddg_search.sh', 'get_ddg_links.py', 'generate_thumbs.sh'):
            self.assertTrue(os.access(wp_dir / script, os.X_OK), f"{script} should be executable")

        # No hardcoded ~/.config/hypr paths in WallpaperPicker.qml
        qml_text = (wp_dir / 'WallpaperPicker.qml').read_text()
        self.assertNotIn('.config/hypr', qml_text)

    def test_wallchange_fallback_when_quickshell_missing(self):
        walls_dir = self.repo / 'wallpapers'
        walls_dir.mkdir(parents=True, exist_ok=True)
        from PIL import Image
        wall1 = walls_dir / '01_test.png'
        wall2 = walls_dir / '02_test.png'
        Image.new('RGB', (32, 32), 'blue').save(wall1)
        Image.new('RGB', (32, 32), 'green').save(wall2)

        state = self.base / 'state/minimal'
        state.mkdir(parents=True, exist_ok=True)
        (state / 'current_wallpaper').write_text(str(wall1.resolve()))

        self.mock('hyprctl', 'sys.exit(0)')
        self.mock('notify-send', 'sys.exit(0)')

        # Hide quickshell by removing from PATH or mocking failure
        env = dict(self.env)
        # Create dummy bin without quickshell
        temp_bin = self.base / 'no_qs_bin'
        temp_bin.mkdir(parents=True, exist_ok=True)
        for f in os.listdir('/usr/bin'):
            if f != 'quickshell':
                try:
                    os.symlink(os.path.join('/usr/bin', f), temp_bin / f)
                except Exception:
                    pass
        # Include our mocked tools
        for f in os.listdir(self.bin):
            if f != 'quickshell':
                try:
                    (temp_bin / f).unlink(missing_ok=True)
                    os.symlink(self.bin / f, temp_bin / f)
                except Exception:
                    pass
        env['PATH'] = str(temp_bin)

        result = subprocess.run([str(self.repo / 'scripts/wallchange.sh')], env=env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((state / 'current_wallpaper').read_text().strip(), str(wall2.resolve()))

    def test_wallchange_targets_wallpaper_picker_quickshell(self):
        wallchange_text = (self.repo / 'scripts/wallchange.sh').read_text()
        self.assertIn('quickshell/wallpaper-picker/shell.qml', wallchange_text)
        self.assertIn('quickshell kill -p', wallchange_text)

    def test_clipboard_quickshell_integration(self):
        clip_script = self.repo / 'scripts/clipboard.sh'
        self.assertTrue(clip_script.is_file())
        self.assertTrue(os.access(clip_script, os.X_OK))
        clip_text = clip_script.read_text()
        self.assertIn('quickshell/clipboard/shell.qml', clip_text)
        self.assertIn('quickshell kill -p', clip_text)

        clip_qml = self.repo / 'quickshell/clipboard/ClipboardManager.qml'
        self.assertTrue(clip_qml.is_file())
        qml_text = clip_qml.read_text()
        # Verify broom brush wipe button is present
        self.assertIn('󰃢', qml_text)
        self.assertIn('window.mutateClipboard("wipe", "")', qml_text)

    def test_clipboard_qml_pagination_delete_and_wipe(self):
        self.env['MINIMAL_ROOT'] = str(self.repo)
        self.env['QS_CACHE_CLIPBOARD'] = str(self.base / 'cache/minimal/clipboard')
        self.env['QT_QPA_PLATFORM'] = 'offscreen'
        self.env.pop('WAYLAND_DISPLAY', None)
        self.mock('cliphist', """state=os.path.join(os.environ['XDG_STATE_HOME'], 'fixture.json')
os.makedirs(os.path.dirname(state),exist_ok=True)
items=json.load(open(state)) if os.path.exists(state) else [str(i) for i in range(60,0,-1)]
if sys.argv[1]=='list':
 for i in items: print(i+'\\tFixture '+i)
elif sys.argv[1]=='delete':
 items.remove(sys.stdin.read().strip()); json.dump(items,open(state,'w'))
elif sys.argv[1]=='wipe': json.dump([],open(state,'w'))
""")
        harness = self.repo / 'quickshell/clipboard/regression.qml'
        shutil.copy2(ROOT / 'tests/clipboard_harness.qml', harness)
        result = subprocess.run(['quickshell','-n','-p',str(harness)],env=self.env,
                                capture_output=True,text=True,timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('REGRESSION_PASS', output)
        self.assertNotIn('REGRESSION_FAIL', output)

    def test_clipboard_cancel_preserves_clipboard(self):
        self.mock('cliphist', 'print("42\\tfixture") if sys.argv[1] == "list" else sys.exit(1)')
        self.mock('fuzzel', 'sys.stdin.read(); sys.exit(1)')
        self.mock('wl-copy', 'sys.stdin.buffer.read()')
        self.run_script('scripts/clipboard.sh', '--fallback')
        self.assertFalse(any(e[0] == 'wl-copy' for e in self.events()))

    def test_clipboard_decode_failure_preserves_clipboard(self):
        self.mock('cliphist', 'sys.exit(1)')
        self.mock('wl-copy', '')
        self.run_script('scripts/clipboard-action.sh', 'copy', '42', expected=1)
        self.assertFalse(any(e[0] == 'wl-copy' for e in self.events()))

    def test_clipboard_copy_preserves_binary_bytes(self):
        self.mock('cliphist', 'sys.stdout.buffer.write(bytes([0, 255, 10, 0]))')
        self.mock('wl-copy', 'open(os.environ["COPY_RESULT"], "wb").write(sys.stdin.buffer.read())')
        target = self.base / 'copy.bin'
        self.env['COPY_RESULT'] = str(target)
        self.run_script('scripts/clipboard-action.sh', 'copy', '42')
        self.assertEqual(target.read_bytes(), bytes([0, 255, 10, 0]))

    def test_clipboard_wipe_removes_image_cache(self):
        cache = self.base / 'cache/minimal/clipboard'
        cache.mkdir(parents=True)
        (cache / '42.png').write_bytes(b'fixture')
        self.mock('cliphist', '')
        self.run_script('scripts/clipboard-action.sh', 'wipe')
        self.assertFalse((cache / '42.png').exists())
        self.assertEqual(cache.stat().st_mode & 0o777, 0o700)

    def test_clipboard_failed_decode_is_not_cached(self):
        self.mock('cliphist', 'if sys.argv[1] == "list": print("42\\t[[ binary data 10 B png 1x1 ]]")\nelse: sys.exit(1)')
        cache = self.base / 'clip-cache'
        result = self.run_script('quickshell/clipboard/clip_fetcher.py', '0', '24', str(cache))
        self.assertFalse((cache / '42.png').exists())
        self.assertEqual(json.loads(result.stdout)[0]['type'], 'text')

    def test_battery_suspends_even_when_notification_fails(self):
        battery = self.base / 'power/BAT0'
        battery.mkdir(parents=True)
        for key, value in {'type':'Battery', 'capacity':'4', 'status':'Discharging'}.items():
            (battery / key).write_text(value + '\n')
        self.env['MINIMAL_POWER_SUPPLY_ROOT'] = str(battery.parent)
        self.mock('notify-send', 'sys.exit(1)')
        self.run_script('scripts/battery-monitor.sh', '--check')
        self.assertIn(['systemctl', 'suspend'], self.events())

    def test_deployment_preserves_host_hooks_and_services(self):
        hook = self.config / 'fish/conf.d/host.fish'
        hook.parent.mkdir(parents=True)
        hook.write_text('set -gx HYPRLAND_CONFIG host-config\n')
        self.run_script('deploy.sh')
        self.run_script('restore.sh')
        self.assertEqual(hook.read_text(), 'set -gx HYPRLAND_CONFIG host-config\n')
        self.assertFalse(any(e[0] == 'systemctl' for e in self.events()))

    def test_session_registration_restores_original(self):
        session = self.base / 'data/wayland-sessions/minimal.desktop'
        session.parent.mkdir(parents=True)
        session.write_text('original desktop entry')
        self.run_script('deploy.sh')
        self.assertIn(str(self.repo / 'scripts/session-entry.sh'), session.read_text())
        self.assertIn('--config-dir', session.read_text())
        if shutil.which('desktop-file-validate'):
            check = subprocess.run(['desktop-file-validate', str(session)], capture_output=True, text=True)
            # DesktopNames is a display-manager extension to Desktop Entry.
            diagnostics = (check.stdout + check.stderr).splitlines()
            self.assertFalse([line for line in diagnostics if 'key "DesktopNames"' not in line], diagnostics)
        self.run_script('restore.sh')
        self.assertEqual(session.read_text(), 'original desktop entry')

    def test_failed_deploy_restores_session_entry(self):
        session = self.base / 'data/wayland-sessions/minimal.desktop'
        self.mock('ln', 'sys.exit(1)')
        self.run_script('deploy.sh', expected=1)
        self.assertFalse(session.exists())

    def test_restore_preserves_independently_changed_session(self):
        session = self.base / 'data/wayland-sessions/minimal.desktop'
        self.run_script('deploy.sh')
        session.write_text('independent session')
        self.run_script('restore.sh', expected=1)
        self.assertEqual(session.read_text(), 'independent session')
        self.assertTrue((self.config / 'hypr').is_symlink())

    def test_usb_open_uses_selected_mountpoint(self):
        mount = '/run/media/test/USB Drive'
        data = {'blockdevices':[{'path':'/dev/sdz','rm':False,'tran':'usb','mountpoints':[None],
                                'children':[{'path':'/dev/sdz1','rm':False,'tran':None,'mountpoints':[mount]}]}]}
        self.mock('lsblk', 'print(' + repr(json.dumps(data)) + ')')
        self.mock('fuzzel', 'sys.stdin.read(); print("0")')
        self.mock('dolphin', '')
        self.run_script('scripts/usb-menu.sh')
        self.assertIn(['dolphin', mount], self.events())

    def test_update_check_failure_is_not_up_to_date(self):
        self.mock('checkupdates', 'sys.exit(1)')
        result = self.run_script('scripts/updates.sh')
        self.assertIn('failed', json.loads(result.stdout)['tooltip'])
        self.mock('checkupdates', 'sys.exit(2)')
        result = self.run_script('scripts/updates.sh')
        self.assertEqual(json.loads(result.stdout)['tooltip'], 'System up to date')

    def test_wallpaper_applies_only_selected_outputs(self):
        from PIL import Image
        wall = self.base / 'wall.png'
        Image.new('RGB', (16, 16), 'blue').save(wall)
        self.mock('hyprctl', 'print("ok")')
        self.mock('notify-send', '')
        self.run_script('scripts/wallpaper.sh', str(wall), 'DP-1,HDMI-A-1')
        calls = [e for e in self.events() if e[:2] == ['hyprctl', 'hyprpaper']]
        self.assertEqual(calls, [['hyprctl','hyprpaper','wallpaper',f'{m},{wall},cover']
                                 for m in ('DP-1','HDMI-A-1')])
        self.assertIn(['hyprctl', 'reload'], self.events())

    def test_wallpaper_qml_failed_download_clears_spinner(self):
        self.env['MINIMAL_ROOT'] = str(self.repo)
        self.env['MINIMAL_CACHE'] = str(self.base / 'cache/minimal')
        self.env['MINIMAL_RUNTIME'] = str(self.base / 'runtime/minimal')
        self.env['QT_QPA_PLATFORM'] = 'offscreen'
        self.env.pop('WAYLAND_DISPLAY', None)
        (self.repo / 'wallpapers').mkdir()
        cache = self.base / 'cache/minimal/wallpaper-picker'
        cache.mkdir(parents=True)
        (cache / 'search_map.txt').write_text('fixture.jpg|https://example.invalid/image.jpg\n')
        self.mock('curl', 'sys.exit(22)')
        self.mock('hyprctl', 'print("[]")')
        self.mock('notify-send', '')
        harness = self.repo / 'quickshell/wallpaper-picker/regression.qml'
        shutil.copy2(ROOT / 'tests/wallpaper_harness.qml', harness)
        result = subprocess.run(['quickshell','-n','-p',str(harness)],env=self.env,
                                capture_output=True,text=True,timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('REGRESSION_PASS', output)
        self.assertNotIn('REGRESSION_FAIL', output)

    def test_search_query_is_passed_literally(self):
        import time
        self.mock('setsid', '')
        marker = self.base / 'injected'
        query = '$(touch "' + str(marker) + '") " landscape'
        self.run_script('quickshell/wallpaper-picker/start-search.sh', query)
        for _ in range(50):
            if self.trace.exists() and any(e[0] == 'setsid' for e in self.events()): break
            time.sleep(0.02)
        call = next(e for e in self.events() if e[0] == 'setsid')
        self.assertEqual(call[-1], query)
        self.assertFalse(marker.exists())


    def test_looknfeel_gaps_and_curved_edges(self):
        look_text = (self.repo / 'hypr/looknfeel.lua').read_text()
        self.assertIn('gaps_in  = 3', look_text)
        self.assertIn('gaps_out = 6', look_text)
        self.assertIn('rounding = 10', look_text)

    def test_deploy_preserves_foreign_application_state(self):
        # 1. Foreign workflow state preservation
        foreign_state = self.base / 'state/foreign/lua_state'
        foreign_state.mkdir(parents=True)
        wf = foreign_state / 'workflows.lua'
        wf.write_text('local _p = "/some/path/efficiency.lua"\nreturn { key = "efficiency" }\n')

        # 2. Firefox stale locks and broken symlink
        ff_dir = self.base / 'home/.mozilla/firefox'
        ff_dir.mkdir(parents=True)
        (ff_dir / 'test.default-release-backup').mkdir()
        (ff_dir / 'test.default-release-backup/prefs.js').write_text('user_pref("test", 1);')
        (ff_dir / 'test.default-release').symlink_to('/run/user/1000/psd/test.default-release')
        (ff_dir / 'installs.ini').write_text('[1234]\nLocked=1\n')
        (ff_dir / '.parentlock').write_text('')

        self.run_script('deploy.sh')

        # Check foreign workflow preserved
        self.assertIn('efficiency.lua', wf.read_text())

        # Check Firefox healed
        self.assertTrue((ff_dir / 'test.default-release').is_symlink())
        self.assertTrue((ff_dir / '.parentlock').exists())
        self.assertIn('Locked=1', (ff_dir / 'installs.ini').read_text())
        self.assertFalse((self.base / 'home/.config/mozilla/firefox').exists())
        self.run_script('deploy.sh')
        self.run_script('restore.sh')
        self.assertIn('efficiency.lua', wf.read_text())
        self.assertFalse(any(e[0].startswith('fusermount') for e in self.events()))

    def test_foot_and_fastfetch_config(self):
        foot_text = (self.repo / 'foot/foot.ini').read_text()
        self.assertIn('size=6', foot_text)
        ff_text = (self.repo / 'fastfetch/config.jsonc').read_text()
        self.assertIn('"type": "sixel"', ff_text)

    def test_deploy_installs_missing_packages_with_sudo(self):
        mock_bin = self.base / 'isolated_bin'
        mock_bin.mkdir()
        for b in ('Hyprland', 'hyprctl', 'waybar', 'wlogout', 'mako', 'makoctl',
                  'hyprpaper', 'hypridle', 'hyprlock', 'wpctl', 'brightnessctl',
                  'notify-send', 'quickshell', 'jq', 'magick', 'python3', 'python',
                  'wl-paste', 'wl-copy', 'cliphist', 'flock', 'loginctl', 'bash', 'sh',
                  'nm-applet', 'nm-connection-editor', 'blueman-applet', 'blueman-manager', 'pavucontrol',
                  'cat', 'sed', 'grep', 'mkdir', 'cp', 'mv', 'rm', 'ln', 'chmod', 'readlink',
                  'realpath', 'dirname', 'basename', 'mktemp', 'date', 'touch'):
            p = shutil.which(b)
            if p:
                (mock_bin / b).symlink_to(p)
        self.mock('sudo', 'if sys.argv[1] == "-v": sys.exit(0)\nelse: os.execv(sys.argv[1], sys.argv[1:])')
        (mock_bin / 'sudo').symlink_to(self.bin / 'sudo')
        self.mock('pacman', '')
        self.mock('fc-match', "print('JetBrainsMono Nerd Font')")
        (mock_bin / 'pacman').symlink_to(self.bin / 'pacman')
        env = dict(self.env, PATH=str(mock_bin))
        subprocess.run([str(self.repo / 'deploy.sh'), '-y'], env=env, text=True, capture_output=True, timeout=10)
        events = self.events()
        self.assertIn(['sudo', '-v'], events)
        sudo_pacman = next((e for e in events if e[0] == 'sudo' and 'pacman' in e), None)
        self.assertIsNotNone(sudo_pacman)
        self.assertIn('fuzzel', sudo_pacman)
        self.assertIn('foot', sudo_pacman)
        self.assertIn('inotify-tools', sudo_pacman)
        self.assertIn('mpvpaper', sudo_pacman)
        self.assertIn('hyprsunset', sudo_pacman)
        self.assertEqual(sudo_pacman.count('foot'), 1)


    def test_deploy_rejects_checkout_as_component_destination(self):
        new = self.base / 'minimal'
        self.repo.rename(new)
        self.repo = new
        result = self.run_script('deploy.sh', '--config-dir', str(self.base), expected=1)
        self.assertIn('overlaps checkout', result.stderr)
        self.assertTrue((new / 'deploy.sh').is_file())
        self.assertFalse(new.is_symlink())

    def test_hybrid_gpu_prefers_connected_intel(self):
        self.env['MINIMAL_MOCK_LSPCI'] = (
            '01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GPU [10de:2520]\n'
            '\tKernel driver in use: nvidia\n'
            '00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake [8086:9a49]\n'
            '\tKernel driver in use: i915\n')
        drm = self.base / 'drm'
        (drm / 'card1/device').mkdir(parents=True)
        (drm / 'card1/device/vendor').write_text('0x8086\n')
        (drm / 'card1/device/device').write_text('0x9a49\n')
        (drm / 'card1-eDP-1').mkdir()
        (drm / 'card1-eDP-1/status').write_text('connected\n')
        self.env['MINIMAL_SYSFS_DRM_DIR'] = str(drm)
        result = self.run_script('scripts/hardware-detect.sh', '--export')
        self.assertIn('export GPU_VENDOR="intel"', result.stdout)

    def test_connected_gpu_matches_pci_slot_with_identical_cards(self):
        for first_slot in ('01:00.0', '0000:01:00.0'):
            with self.subTest(slot=first_slot):
                self.env['MINIMAL_MOCK_LSPCI'] = (
                    f'{first_slot} VGA compatible controller [0300]: NVIDIA First [10de:2520]\n'
                    '\tKernel driver in use: nvidia\n'
                    '0001:02:00.0 VGA compatible controller [0300]: NVIDIA Second [10de:2520]\n'
                    '\tKernel driver in use: nouveau\n')
                drm = self.base / 'drm'
                device = drm / 'card1/device'
                device.mkdir(parents=True, exist_ok=True)
                for key, value in [('vendor', '0x10de'), ('device', '0x2520'),
                                   ('uevent', 'PCI_SLOT_NAME=0001:02:00.0')]:
                    (device / key).write_text(value + '\n')
                connector = drm / 'card1-DP-1'
                connector.mkdir(exist_ok=True)
                (connector / 'status').write_text('connected\n')
                self.env['MINIMAL_SYSFS_DRM_DIR'] = str(drm)
                result = self.run_script('scripts/hardware-detect.sh', '--export')
                self.assertIn('export GPU_DRIVER="nouveau"', result.stdout)
                self.assertIn('NVIDIA Second', result.stdout)

    def test_deploy_build_failure_preserves_originals(self):
        self.originals()
        self.mock('cc', 'sys.exit(1)')
        self.run_script('deploy.sh', expected=1)
        self.assert_originals()
        self.assertFalse((self.base / 'data/wayland-sessions/minimal.desktop').exists())

    def test_redeploy_does_not_build_recolor_or_reload(self):
        self.run_script('deploy.sh')
        palette = self.repo / 'colors.css'
        before = palette.read_bytes()
        for script in ('build-native.sh', 'sync-theme.py'):
            (self.repo / 'scripts' / script).write_text('#!/bin/sh\nexit 99\n')
        self.trace.write_text('')
        self.mock('hyprctl', 'sys.exit(99)')
        self.run_script('deploy.sh')
        self.assertEqual(palette.read_bytes(), before)
        self.assertFalse(any(e[0] in ('hyprctl', 'makoctl', 'systemd-run') for e in self.events()))

    def test_clipboard_decode_byte_limit_removes_partial_cache(self):
        self.mock('cliphist', "if sys.argv[1]=='list': print('1\\t[[ binary data ]]')\nelse: sys.stdout.buffer.write(b'x' * (17 * 1024 * 1024))")
        cache = self.base / 'clipboard'
        result = self.run_script('quickshell/clipboard/clip_fetcher.py', '0', '12', str(cache))
        self.assertEqual(json.loads(result.stdout)[0]['type'], 'text')
        self.assertEqual(list(cache.glob('1.*')), [])

    def test_clipboard_rejects_oversized_dimensions_before_raster_decode(self):
        import importlib.util
        from unittest.mock import MagicMock, patch
        spec = importlib.util.spec_from_file_location('clip_fetcher', self.repo / 'quickshell/clipboard/clip_fetcher.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        preview = MagicMock(width=4096, height=4096)
        with patch('PIL.Image.open') as image_open:
            image_open.return_value.__enter__.return_value = preview
            with self.assertRaises(ValueError):
                module.create_preview('synthetic-input', 'unused-output')
        preview.thumbnail.assert_not_called()

    def test_night_light_stops_only_session_unit(self):
        self.env['HYPRLAND_INSTANCE_SIGNATURE'] = 'test-instance'
        self.run_script('scripts/night-light.sh')
        self.assertIn(['systemctl', '--user', 'stop', 'minimal-test-instance-night-light.service'], self.events())
        self.assertFalse(any(e[0] == 'pkill' for e in self.events()))

    def test_full_secondary_battery_does_not_hide_critical_primary(self):
        supplies = self.base / 'power'
        for name, capacity, status in [('BAT0', '4', 'Discharging'), ('BAT1', '100', 'Full')]:
            battery = supplies / name
            battery.mkdir(parents=True)
            for key, value in [('type', 'Battery'), ('capacity', capacity), ('status', status)]:
                (battery / key).write_text(value + '\n')
        self.env['MINIMAL_POWER_SUPPLY_ROOT'] = str(supplies)
        self.mock('notify-send', '')
        self.mock('sleep', '')
        self.run_script('scripts/battery-monitor.sh', '--check')
        self.run_script('scripts/battery-monitor.sh', '--check')
        self.assertEqual(self.events().count(['systemctl', 'suspend']), 2)

    def test_screenshot_cancel_does_not_touch_clipboard(self):
        self.mock('slurp', 'sys.exit(1)')
        self.mock('grim', '')
        self.mock('wl-copy', '')
        self.run_script('scripts/screenshot.sh', 'region')
        self.assertFalse(any(e[0] in ('grim', 'wl-copy') for e in self.events()))

    def test_clipboard_search_matches_full_text_beyond_first_page(self):
        self.mock('cliphist', """if sys.argv[1]=='list':
 for i in range(60,0,-1): print(str(i)+'\\tShort preview')
else: print('hidden needle' if sys.argv[2]=='1' else 'unrelated')
""")
        cache = self.base / 'clipboard'
        result = self.run_script('quickshell/clipboard/clip_fetcher.py', '0', '24', str(cache), 'needle')
        self.assertEqual([item['id'] for item in json.loads(result.stdout)], ['1'])

    def test_native_guard_stops_only_owned_units_after_compositor_exit(self):
        self.run_script('scripts/build-native.sh')
        child = subprocess.Popen(['sleep', '0.2'])
        guard = subprocess.run([str(self.base / 'cache/minimal/bin/session-guard'), str(child.pid), 'minimal-fixture'], env=self.env, timeout=5)
        child.wait()
        self.assertEqual(guard.returncode, 0)
        self.assertIn(['systemctl', '--user', 'stop', 'minimal-fixture-*'], self.events())

    def test_thumbnail_generation_waits_for_last_worker(self):
        import time
        source = self.base / 'walls'
        source.mkdir()
        (source / 'fixture.png').write_text('not an image; mocked conversion')
        self.env['MINIMAL_WALLPAPERS'] = str(source)
        self.mock('magick', "import time\nif sys.argv[-1]=='info:-': print('abcdef')\nelse:\n time.sleep(.4)\n open(sys.argv[-1], 'w').write('thumbnail')")
        started = time.monotonic()
        self.run_script('quickshell/wallpaper-picker/generate_thumbs.sh')
        self.assertGreaterEqual(time.monotonic() - started, .4)
        self.assertTrue((self.base / 'cache/minimal/wallpaper-picker/thumbs/fixture.png').exists())

    def test_caffeine_never_kills_idle_locker(self):
        self.mock('systemctl', "sys.exit(3) if 'is-active' in sys.argv else None")
        self.mock('systemd-run', '')
        self.run_script('scripts/caffeine.sh', 'toggle')
        event = next(e for e in self.events() if e[0] == 'systemd-run')
        self.assertIn('--what=idle', event)
        self.assertFalse(any('hypridle' in e for e in self.events()))


    def test_theme_keeps_neutral_surfaces_and_updates_every_accent(self):
        from PIL import Image
        original = json.loads((self.repo / 'theme.json').read_text())
        for color in ('red', 'blue'):
            wall = self.base / (color + '.png')
            Image.new('RGB', (16, 16), color).save(wall)
            self.run_script('scripts/update_fuzzel_colors.py', str(wall))
            theme = json.loads((self.repo / 'theme.json').read_text())
            self.assertEqual(theme['colors']['base'], original['colors']['base'])
            self.assertEqual(theme['colors']['surface'], original['colors']['surface'])
            accent = theme['colors']['accent']
            for filename in ('colors.css', 'fuzzel/fuzzel.ini', 'hypr/colors.lua',
                             'hypr/hyprlock.conf', 'mako/config', 'foot/foot.ini', 'assets/gtk-accent.css'):
                self.assertIn(accent, (self.repo / filename).read_text(), filename)
            self.assertIn('background=171c1ecc', (self.repo / 'fuzzel/fuzzel.ini').read_text())
            main = (self.repo / 'fuzzel/fuzzel.ini').read_text().split('[colors]')[0]
            self.assertIn('prompt=""', main)
            self.assertIn('message="                          ━━━━"', main)
        paths = [self.repo / p for p in ('colors.css', 'foot/foot.ini', 'fuzzel/fuzzel.ini', 'mako/config', 'assets/gtk-accent.css')]
        timestamps = [p.stat().st_mtime_ns for p in paths]
        self.run_script('scripts/sync-theme.py')
        self.assertEqual(timestamps, [p.stat().st_mtime_ns for p in paths])

    def test_wallpaper_picker_reads_shared_theme_instead_of_qt_palette(self):
        theme = json.loads((self.repo / 'theme.json').read_text())
        theme['colors']['base'] = '192023'
        theme['radius']['control'] = 9
        (self.repo / 'theme.json').write_text(json.dumps(theme))
        harness = self.repo / 'quickshell/wallpaper-picker/theme-regression.qml'
        harness.write_text("""import QtQuick
import Quickshell
import "."
ShellRoot {
    MatugenColors { id: design }
    Timer {
        interval: 200; running: true
        onTriggered: {
            if (String(design.base) === "#192023" && design.controlRadius === 9)
                console.log("THEME_PASS");
            else console.log("THEME_FAIL", design.base, design.controlRadius);
            Qt.quit();
        }
    }
}
""")
        result = subprocess.run(['quickshell', '-n', '-p', str(harness)],
                                env=dict(self.env, QT_QPA_PLATFORM='offscreen'),
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('THEME_PASS', output)
        self.assertNotIn('Unable to assign', output)

    def test_power_menu_uses_logical_geometry_and_stable_cards(self):
        import re
        self.mock('hyprctl', 'print(json.dumps([{"focused":True,"width":1366,"height":768,"scale":2,"transform":0}]))')
        self.mock('wlogout', '')
        self.run_script('scripts/powermenu.sh')
        args = next(e for e in self.events() if e[0] == 'wlogout')
        self.assertEqual(args[args.index('-b') + 1], '3')
        self.assertEqual(args[args.index('-T') + 1], '44')
        css = (self.repo / 'wlogout/style.css').read_text()
        self.assertNotIn('transition: all', css)
        self.assertNotIn('margin: 185px', css)
        raw_actions = re.findall(r'"action"\s*:\s*"([^"]*)"', (self.repo / 'wlogout/layout').read_text())
        self.assertEqual(len(raw_actions), 6)
        for act in raw_actions:
            self.assertNotIn('\\', act)
        subprocess.run(['sh', '-c', raw_actions[1].rstrip('&')], env=self.env, check=True, timeout=5)
        self.assertIn(['hyprctl', 'dispatch', 'hl.dsp.exit()'], self.events())

    def test_failed_wallpaper_rolls_back_generated_theme(self):
        from PIL import Image
        wall = self.base / 'wall.png'
        Image.new('RGB', (16, 16), 'red').save(wall)
        generated = ('theme.json', 'fuzzel/fuzzel.ini', 'colors.css', 'foot/foot.ini',
                     'waybar/theme.css', 'waybar/design.css', 'wlogout/design.css',
                     'hypr/colors.lua', 'hypr/hyprlock.conf', 'mako/config', 'assets/gtk-accent.css')
        before = {name: (self.repo / name).read_bytes() for name in generated}
        self.mock('hyprctl', 'sys.exit(1)')
        self.mock('notify-send', '')
        self.run_script('scripts/wallpaper.sh', str(wall), expected=1)
        for name in generated:
            self.assertEqual((self.repo / name).read_bytes(), before[name], name)
        self.assertFalse((self.base / 'state/minimal/current_wallpaper').exists())
        self.assertFalse((self.base / 'cache/minimal/lock.png').exists())

    def test_wallpaper_state_preserves_distinct_outputs(self):
        from PIL import Image
        self.mock('hyprctl', 'print("ok")')
        self.mock('notify-send', '')
        for output, color in [('DP-1','red'), ('HDMI-A-1','blue')]:
            wall = self.base / (output + '.png')
            Image.new('RGB', (16, 16), color).save(wall)
            self.run_script('scripts/wallpaper.sh', str(wall), output)
        state = json.loads((self.base / 'state/minimal/wallpapers.json').read_text())
        self.assertEqual(state['DP-1']['path'], str(self.base / 'DP-1.png'))
        self.assertEqual(state['HDMI-A-1']['path'], str(self.base / 'HDMI-A-1.png'))

    def test_legacy_cleanup_does_not_match_embedded_shell_source(self):
        import runpy
        helpers = runpy.run_path(str(self.repo / 'scripts/session-conflicts.py'))
        matcher = helpers['is_legacy_watcher']
        command = b'while [ ! -f /tmp/minimal/settings.json ]; do sleep 2; done; inotifywait /tmp/minimal/settings.json'
        self.assertTrue(matcher('bash', [b'bash', b'-c', command]))
        self.assertFalse(matcher('bash', [b'bash', b'-c', b'python3 - <<EOF\n' + command]))


    def open_app(self, role, *apps):
        """Run open-app.sh with only the named fake apps visible, so the host's
        real browsers and file managers cannot leak into the result."""
        tools = self.base / 'open-app-bin'
        tools.mkdir()
        for name in ('bash', 'env', 'setsid'):
            (tools / name).symlink_to(shutil.which(name))
        for name in ('notify-send', *apps):
            script = tools / name
            script.write_text('#!/bin/sh\necho "%s $*" >> "%s"\n' % (name, self.base / 'open-app.log'))
            script.chmod(0o755)
        env = dict(self.env, PATH=str(tools), BROWSER='')
        subprocess.run([str(self.repo / 'scripts/open-app.sh'), role], env=env, check=True, timeout=10)
        time.sleep(0.2)
        log = self.base / 'open-app.log'
        return log.read_text() if log.exists() else ''

    def test_open_app_degrades_without_any_candidate(self):
        # A bare system (no Firefox, file manager, etc.) must not break the key.
        self.assertIn('notify-send', self.open_app('files'))

    def test_open_app_launches_first_available(self):
        out = self.open_app('files', 'thunar')
        self.assertIn('thunar', out)
        self.assertNotIn('notify-send', out)

    def test_hyprpaper_08_readiness_and_no_duplicate_default_apply(self):
        state = self.base / 'state/minimal'
        state.mkdir(parents=True)
        wall = self.base / 'wall.png'
        wall.touch()
        selection = dict(path=str(wall), kind='image', preview=str(wall))
        (state / 'wallpapers.json').write_text(json.dumps({'all': selection}))
        self.mock('hyprctl', 'sys.stderr.write("error: invalid hyprpaper request\\n"); sys.exit(1)')
        (self.repo / 'scripts/wallpaper.sh').write_text('#!/bin/sh\nprintf "%s" "$2" > "$XDG_STATE_HOME/outputs"\n')
        self.env['MINIMAL_WALLPAPER'] = str(wall)
        started = time.monotonic()
        self.run_script('scripts/restore-wallpapers.sh')
        self.assertLess(time.monotonic() - started, 1.0)
        self.assertFalse((self.base / 'state/outputs').exists())

    def test_looknfeel_respects_hardware_blur_and_vfr(self):
        hw_text = (self.repo / 'hypr/hardware.lua').read_text()
        look_text = (self.repo / 'hypr/looknfeel.lua').read_text()
        self.assertIn('M.vfr =', hw_text)
        self.assertIn('M.blur =', hw_text)
        self.assertIn('hardware.blur', look_text)
        self.assertIn('hardware.vfr', look_text)

    def test_hypridle_and_keybinds_use_valid_dpms_and_screenshot_paths(self):
        idle_text = (self.repo / 'hypr/hypridle.conf').read_text()
        self.assertIn('hl.dsp.dpms("off")', idle_text)
        self.assertIn('hl.dsp.dpms("on")', idle_text)
        kb_text = (self.repo / 'hypr/keybinds.lua').read_text()
        self.assertIn('hl.dsp.dpms("on")', kb_text)
        self.assertIn('paths.script("screenshot.sh")', kb_text)

    def test_clipboard_caching_paths_and_search_control_protocol(self):
        caching_text = (self.repo / 'quickshell/clipboard/Caching.qml').read_text()
        self.assertNotIn('wallpaper-picker', caching_text)
        self.assertIn('minimalCache + "/clipboard"', caching_text)
        ctrl_text = (self.repo / 'quickshell/wallpaper-picker/search-control.sh').read_text()
        self.assertNotIn('kill -STOP', ctrl_text)
        self.assertIn('ddg_search_control', ctrl_text)

    def test_battery_not_charging_and_device_scope_filtering(self):
        supplies = self.base / 'power'
        sys_bat = supplies / 'BAT0'
        sys_bat.mkdir(parents=True)
        for k, v in [('type', 'Battery'), ('capacity', '80'), ('status', 'Not charging')]:
            (sys_bat / k).write_text(v + '\n')
        mouse_bat = supplies / 'hidpp_battery_0'
        mouse_bat.mkdir(parents=True)
        for k, v in [('type', 'Battery'), ('capacity', '10'), ('status', 'Discharging'), ('scope', 'Device')]:
            (mouse_bat / k).write_text(v + '\n')
        self.env['MINIMAL_POWER_SUPPLY_ROOT'] = str(supplies)
        res = self.run_script('scripts/battery-status.sh')
        self.assertIn('80% · Plugged in', res.stdout)

    def test_keybinds_quickshell_popup_and_search(self):
        kb_lua = self.repo / 'hypr/keybinds.lua'
        kb_lua.write_text(
            kb_lua.read_text().replace('mainMod .. " + T"', 'mainMod .. " + Return"')
            + '\nhl.bind(mainMod .. " + G", hl.dsp.exec_cmd("gimp")) -- Launch GIMP\n'
        )
        dmenu_res = self.run_script('scripts/parse-keybinds.py', '--dmenu')
        self.assertIn('Super + Enter', dmenu_res.stdout)
        self.assertIn('Launch GIMP', dmenu_res.stdout)
        wb_res = self.run_script('scripts/parse-keybinds.py', '--waybar')
        wb_json = json.loads(wb_res.stdout)
        self.assertEqual(wb_json['text'], '󰌌')
        self.assertIn('Super + Enter', wb_json['tooltip'])
        json_res = self.run_script('scripts/parse-keybinds.py', '--json')

        source = (self.repo / 'quickshell/keybinds/shell.qml').read_text()
        harness = self.repo / 'quickshell/keybinds/regression.qml'
        checks = r"""
    Timer {
        interval: 100; running: true
        onTriggered: {
            if (root.results.length > 15) {
                root.activeCategory = "Apps";
                const appsCount = root.results.length;
                root.activeCategory = "All";
                root.query = "gimp";
                if (appsCount > 0 && root.results.length >= 1 && root.results[0].title === "Launch GIMP") {
                    console.log("KEYBINDS_PASS");
                } else {
                    console.log("KEYBINDS_FAIL", appsCount, root.results.length);
                }
            } else {
                console.log("KEYBINDS_FAIL_INIT", root.results.length);
            }
            Qt.quit();
        }
    }
"""
        logic = source[:source.index('    PanelWindow {')]
        harness.write_text(logic + '    QtObject { id: list; property int currentIndex: -1 }\n' + checks + '}')
        env = dict(self.env, QT_QPA_PLATFORM='offscreen', MINIMAL_KEYBINDS_JSON=json_res.stdout)
        result = subprocess.run(['quickshell', '-n', '-p', str(harness)], env=env,
                                capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('KEYBINDS_PASS', output)

    def test_quickshell_settings_and_clean_waybar(self):
        settings_script = self.repo / 'scripts/settings.sh'
        self.assertTrue(settings_script.is_file(), "scripts/settings.sh must exist")
        self.assertTrue(os.access(settings_script, os.X_OK), "scripts/settings.sh must be executable")

        help_res = self.run_script('scripts/settings.sh', '--help')
        self.assertIn('Usage: settings.sh', help_res.stdout + help_res.stderr)

        # Verify Waybar center pill has clean workspaces and window without notch
        cfg = json.loads((self.repo / 'waybar/config.jsonc').read_text())
        center_modules = cfg['group/pill#center']['modules']
        self.assertNotIn('custom/notch', center_modules)
        self.assertIn('hyprland/workspaces', center_modules)

        # Verify Theme.qml in settings exists and references Minimal tokens
        theme_qml = (self.repo / 'quickshell/settings/Theme.qml').read_text()
        self.assertIn('pragma Singleton', theme_qml)
        self.assertIn('theme.json', theme_qml)

        # Verify Network, Bluetooth, and Sound tabs exist
        for tab in ['Network.qml', 'Bluetooth.qml', 'Sound.qml']:
            tab_file = self.repo / f'quickshell/settings/Tabs/{tab}'
            self.assertTrue(tab_file.is_file(), f'Tabs/{tab} must exist')


    def test_control_center_wifi_bluetooth_audio_and_qml(self):
        self.mock('nmcli', r'''
args = sys.argv[1:]
if "radio" in args and "WIFI" in args: print("enabled")
elif "connection" in args and "--active" in args: print("HomeNet:802-11-wireless:wlan0")
elif "connection" in args and "show" in args: print("HomeNet:802-11-wireless")
elif "IP4.ADDRESS" in args: print("IP4.ADDRESS[1]:192.168.1.42/24")
elif "wifi" in args and "list" in args: print("*:HomeNet:92:WPA2\n :Cafe\\:5G:64:WPA2")
''')
        self.mock('bluetoothctl', '''
args = sys.argv[1:]
if args == ["show"]: print("Controller AA:BB:CC:DD:EE:FF\\n\\tAlias: MinimalBT\\n\\tPowered: yes\\n\\tDiscoverable: no")
elif args == ["devices", "Paired"]: print("Device 11:22:33:44:55:66 Sony WH-1000XM5")
elif args == ["devices", "Connected"]: print("Device 11:22:33:44:55:66 Sony WH-1000XM5")
elif args == ["devices", "Trusted"]: print("Device 11:22:33:44:55:66 Sony WH-1000XM5")
elif args == ["devices"]: print("Device 11:22:33:44:55:66 Sony WH-1000XM5")
elif args[:1] == ["info"]: print("Battery Percentage: 0x55 (85)")
''')
        self.mock('wpctl', '''
if sys.argv[1] == "get-volume": print("Volume: 0.65")
elif sys.argv[1] == "status": print("Audio\\n ├─ Sinks:\\n │  * 42. Built-in Analog Stereo [vol: 0.65]\\n └─ Sources:\\n    * 43. Internal Mic [vol: 0.80]")
''')
        state_raw = self.run_script('scripts/control-center-backend.py', '--state').stdout
        state = json.loads(state_raw)
        self.assertTrue(state['wifi']['enabled'])
        self.assertEqual(state['wifi']['connectedSsid'], 'HomeNet')
        self.assertEqual(len(state['wifi']['networks']), 2)
        self.assertEqual(state['wifi']['networks'][1]['ssid'], 'Cafe:5G')
        self.assertEqual(state['bluetooth']['devices'][0]['battery'], '85%')
        self.assertEqual(state['audio']['volume'], 65)

        source = (self.repo / 'quickshell/control-center/shell.qml').read_text()
        harness = self.repo / 'quickshell/control-center/regression.qml'
        logic = source[:source.index('    PanelWindow {')]
        harness.write_text(logic + """
    Timer {
        interval: 100; running: true
        onTriggered: {
            if (root.stateData.wifi.connectedSsid === "HomeNet" && root.stateData.bluetooth.devices.length === 1 && root.activeTab === "wifi")
                console.log("CC_PASS");
            else console.log("CC_FAIL", JSON.stringify(root.stateData));
            Qt.quit();
        }
    }
}""")
        res = subprocess.run(['quickshell', '-n', '-p', str(harness)],
                             env=dict(self.env, QT_QPA_PLATFORM='offscreen', MINIMAL_CC_TAB='wifi', MINIMAL_CC_JSON=state_raw),
                             capture_output=True, text=True, timeout=15)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn('CC_PASS', res.stdout + res.stderr)

    def test_monitors_switcher_presets_persistence_and_qml(self):
        self.mock('hyprctl', '''
if "-j" in sys.argv:
    print(json.dumps([
        {"name":"eDP-1","description":"Laptop","width":1920,"height":1080,"refreshRate":60,"scale":1.0,"x":0,"y":0,"vrr":False,"disabled":False,"focused":True,"availableModes":["1920x1080@60.00Hz"]},
        {"name":"HDMI-A-1","description":"External","width":2560,"height":1440,"refreshRate":144,"scale":1.25,"x":1920,"y":0,"vrr":True,"disabled":False,"focused":False,"availableModes":["2560x1440@144.00Hz","2560x1440@60.00Hz"]}
    ]))
''')
        self.mock('notify-send', '')
        out = self.run_script('scripts/monitors.py', '--preset', 'extend-right').stdout
        parsed = json.loads(out)
        self.assertEqual(len(parsed['monitors']), 2)
        self.assertTrue((self.base / 'state/minimal/monitors.json').is_file())
        self.assertTrue((self.base / 'state/minimal/monitors.lua').is_file())
        self.assertTrue(any(e[:3] == ['hyprctl', 'keyword', 'monitor'] for e in self.events()))

    def test_screen_recording_toggle_and_region_ocr(self):
        self.mock('slurp', 'print("10,10 200x100")')
        self.mock('grim', 'open(sys.argv[-1], "wb").write(b"PNG")')
        self.mock('tesseract', 'print("Extracted Minimal Text")')
        self.mock('wl-copy', 'open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "ocr.txt"), "w").write(sys.stdin.read())')
        self.mock('notify-send', '')
        self.run_script('scripts/screenshot.sh', 'ocr')
        self.assertEqual((self.base / 'runtime/ocr.txt').read_text(), 'Extracted Minimal Text')

    def test_bootstrap_dry_run_check(self):
        res = self.run_script('bootstrap.sh', '--check')
        self.assertIn('Minimal Bootstrap Check', res.stdout)
        self.assertEqual(list(self.config.iterdir()), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
