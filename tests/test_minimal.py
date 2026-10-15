"""Integration checks in temporary directories; never touch the live desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = ('hypr', 'waybar', 'wlogout', 'fuzzel', 'foot', 'mako', 'fastfetch', 'minimal')


class MinimalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='minimal test ')
        self.base = Path(self.temp.name)
        self.repo = self.base / 'source rice'
        self.repo.mkdir()
        for directory in ('hypr', 'waybar', 'wlogout', 'fuzzel', 'foot', 'mako', 'fastfetch', 'scripts', 'quickshell'):
            shutil.copytree(ROOT / directory, self.repo / directory, symlinks=True)
        for filename in ('deploy.sh', 'restore.sh', 'colors.css'):
            shutil.copy2(ROOT / filename, self.repo / filename)
        self.config = self.base / 'config'
        self.config.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.trace = self.base / 'trace.jsonl'
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        XDG_CONFIG_HOME=str(self.config), XDG_CACHE_HOME=str(self.base / 'cache'),
                        XDG_STATE_HOME=str(self.base / 'state'), XDG_RUNTIME_DIR=str(self.base / 'runtime'),
                        MOCK_TRACE=str(self.trace))
        (self.base / 'runtime').mkdir()
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
        return [json.loads(line) for line in self.trace.read_text().splitlines()]

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

    def test_launcher_position_and_scaled_monitor(self):
        self.mock('hyprctl', 'print(json.dumps([{"focused":True,"name":"test","height":1536,"width":2732,"scale":2,"transform":0}]))')
        self.mock('fuzzel', '')
        self.run_script('scripts/launcher.sh')
        args = self.events()[-1]
        self.assertEqual(args[args.index('--y-margin') + 1], '266')
        self.assertEqual(args[args.index('--output') + 1], 'test')

    def test_launcher_toggle_kills_running_fuzzel(self):
        self.mock('pgrep', 'sys.exit(0)')
        self.mock('pkill', '')
        self.mock('fuzzel', '')
        self.run_script('scripts/launcher.sh')
        events = self.events()
        self.assertIn(['pgrep', '-x', 'fuzzel'], events)
        self.assertIn(['pkill', '-x', 'fuzzel'], events)
        self.assertFalse(any(e[0] == 'fuzzel' for e in events))

    def test_launcher_cancels_cleanly_on_fuzzel_exit(self):
        self.mock('fuzzel', 'sys.exit(1)')
        result = self.run_script('scripts/launcher.sh', expected=0)
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
        self.assertIn('width=42', (self.repo / 'fuzzel/fuzzel.ini').read_text())
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

        forbidden = ['hyde-shell', 'wallbash', '.local/lib/hyde', 'rofilaunch', 'hl.dsp', 'HYDE_WAYBAR_MENU_DIR']
        for mf in module_files:
            text = mf.read_text(encoding='utf-8')
            for bad in forbidden:
                self.assertNotIn(bad, text, f"Found forbidden '{bad}' in {mf.name}")

        config_path = self.repo / 'waybar/config.jsonc'
        self.assertTrue(config_path.is_file(), "waybar/config.jsonc must exist")
        cfg_text = config_path.read_text(encoding='utf-8')
        # Check modular include directive
        self.assertIn('$HOME/.config/waybar/modules/*.jsonc', cfg_text)

        # Verify waybar execution parses modular config and style
        try:
            res = subprocess.run([
                "waybar", "-c", str(config_path), "-s", str(self.repo / 'waybar/style.css'), "-l", "info"
            ], capture_output=True, text=True, timeout=2)
            combined = res.stdout + res.stderr
        except subprocess.TimeoutExpired as e:
            out = e.stdout.decode('utf-8', errors='replace') if isinstance(e.stdout, bytes) else (e.stdout or "")
            err = e.stderr.decode('utf-8', errors='replace') if isinstance(e.stderr, bytes) else (e.stderr or "")
            combined = out + err
        self.assertNotIn("Failed to read config file", combined)
        self.assertNotIn("JSON", combined.lower())
        self.assertIn("Bar configured", combined)

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


if __name__ == '__main__':
    unittest.main(verbosity=2)


