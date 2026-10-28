import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import install
from minimal_config import read_jsonc, validate_bar


def exists_any(path):
    return path.exists() or path.is_symlink()


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='minimal test ')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'checkout with spaces'
        self.config = self.base / 'config'
        self.state = self.base / 'state'
        for name in install.COMPONENTS:
            (self.root / name).mkdir(parents=True)
            (self.root / name / 'new').write_text('minimal')
        self.config.mkdir()

    def deploy(self, dry=False):
        with contextlib.redirect_stdout(io.StringIO()):
            return install.deploy(self.root, self.config, self.state, dry)

    def test_clean_install_restore_removes_new_paths(self):
        snapshot = self.deploy()
        self.assertTrue(all((self.config / n).is_symlink() for n in install.COMPONENTS))
        install.restore(snapshot)
        self.assertEqual(list(self.config.iterdir()), [])

    def test_preserves_directories_files_and_broken_symlinks(self):
        (self.config / 'hypr').mkdir()
        (self.config / 'hypr/original').write_text('user data')
        (self.config / 'foot').write_text('file instead of directory')
        (self.config / 'rofi').symlink_to('missing-target')
        snapshot = self.deploy()
        install.restore(snapshot)
        self.assertEqual((self.config / 'hypr/original').read_text(), 'user data')
        self.assertEqual((self.config / 'foot').read_text(), 'file instead of directory')
        self.assertEqual(os.readlink(self.config / 'rofi'), 'missing-target')
        self.assertFalse((self.config / 'waybar').exists())

    def test_reinstall_retains_recovery_point(self):
        snapshot = self.deploy()
        self.assertIsNone(self.deploy())
        self.assertEqual((self.state / 'latest_backup').read_text().strip(), str(snapshot))

    def test_partial_relink_keeps_user_originals(self):
        # Critical #1: re-deploying after one link changed must not snapshot
        # Minimal's own links as the user's originals.
        (self.config / 'hypr').mkdir()
        (self.config / 'hypr/original').write_text('user hypr')
        self.deploy()
        (self.config / 'foot').unlink()
        (self.config / 'foot').write_text('replaced by user')
        second = self.deploy()
        manifest = json.loads((second / 'manifest.json').read_text())
        self.assertTrue(manifest['components']['hypr'])
        self.assertFalse((second / 'original/hypr').is_symlink())
        self.assertEqual((second / 'original/hypr/original').read_text(), 'user hypr')
        self.assertFalse(manifest['components']['waybar'])
        install.restore(Path((self.state / 'latest_backup').read_text().strip()))
        self.assertEqual((self.config / 'hypr/original').read_text(), 'user hypr')
        self.assertEqual((self.config / 'foot').read_text(), 'replaced by user')
        self.assertFalse(exists_any(self.config / 'waybar'))

    def test_failed_deploy_keeps_previous_recovery_pointer(self):
        # High #2: a failed run must not move latest_backup.
        first = self.deploy()
        (self.config / 'foot').unlink()
        original = Path.replace
        def fail(path, target):
            if '.minimal-stage-' in str(path) and path.name == 'rofi':
                raise OSError('simulated deployment failure')
            return original(path, target)
        with patch.object(Path, 'replace', fail):
            with self.assertRaises(OSError):
                self.deploy()
        self.assertEqual((self.state / 'latest_backup').read_text().strip(), str(first))
        # Rollback returns to the exact pre-run state, Minimal links included.
        self.assertTrue((self.config / 'hypr').is_symlink())
        self.assertFalse(exists_any(self.config / 'foot'))
        self.assertEqual(sorted(p.name for p in (self.state / 'backups').iterdir()), [first.name])

    def test_remove_handles_fifo(self):
        fifo = self.base / 'pipe'
        os.mkfifo(fifo)
        install.remove(fifo)
        self.assertFalse(exists_any(fifo))

    def test_dry_run_creates_nothing(self):
        before = sorted(str(p) for p in self.base.rglob('*'))
        self.deploy(True)
        self.assertEqual(before, sorted(str(p) for p in self.base.rglob('*')))

    def test_partial_deployment_failure_restores_all(self):
        (self.config / 'hypr').mkdir()
        (self.config / 'hypr/original').write_text('keep me')
        original = Path.replace
        failed = False
        def fail_once(path, target):
            nonlocal failed
            if '.minimal-stage-' in str(path) and path.name == 'rofi' and not failed:
                failed = True
                raise OSError('simulated deployment failure')
            return original(path, target)
        with patch.object(Path, 'replace', fail_once):
            with self.assertRaises(OSError):
                self.deploy()
        self.assertEqual((self.config / 'hypr/original').read_text(), 'keep me')
        self.assertFalse((self.config / 'waybar').exists())

    def test_backup_failure_does_not_touch_configuration(self):
        (self.config / 'hypr').mkdir()
        (self.config / 'hypr/original').write_text('keep me')
        with patch.object(install, 'copy', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.deploy()
        self.assertEqual((self.config / 'hypr/original').read_text(), 'keep me')

    def test_standalone_restore_and_dry_run(self):
        snapshot = self.deploy()
        args = ['bash', str(snapshot / 'restore.sh')]
        env = dict(os.environ, XDG_STATE_HOME=str(self.base / 'xdg-state'))
        subprocess.run([*args, '--dry-run'], env=env, check=True, capture_output=True)
        self.assertTrue((self.config / 'hypr').is_symlink())
        subprocess.run(args, env=env, check=True, capture_output=True)
        self.assertEqual(list(self.config.iterdir()), [])

    def test_cli_dry_run_custom_xdg(self):
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.base/'fresh/config'), XDG_STATE_HOME=str(self.base/'fresh/state'), XDG_CACHE_HOME=str(self.base/'fresh/cache'))
        result = subprocess.run([str(ROOT/'install.sh'),'--no-tui','--dry-run','--skip-packages'],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((self.base/'fresh').exists())


class ConfigTests(unittest.TestCase):
    def test_every_layout_resolves(self):
        layouts = list((ROOT/'waybar/layouts').glob('[0-9][0-9].jsonc'))
        self.assertEqual(len(layouts),17)
        for p in [ROOT/'waybar/config.jsonc',*layouts]:
            validate_bar(p)

    def test_jsonc_preserves_string_contents(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'config.jsonc'
            path.write_text('{/* comment */ "url": "https://example.com/a,}", // note\n "other": [1,2,],}')
            self.assertEqual(read_jsonc(path), {'url':'https://example.com/a,}', 'other':[1,2]})

    def test_symlinked_lua_root_resolution(self):
        import shutil
        if not shutil.which('lua'): self.skipTest('lua unavailable')
        with tempfile.TemporaryDirectory(prefix='minimal lua ') as tmp:
            link=Path(tmp)/'config/hypr';link.parent.mkdir();link.symlink_to(ROOT/'hypr')
            lua='hl = {env=function() end}; local p=dofile(arg[1]); print(p.root)'
            result=subprocess.run(['lua','-',str(link/'paths.lua')],input=lua,text=True,capture_output=True,check=True)
            self.assertEqual(result.stdout.strip(),str(ROOT))

    def test_bar_render_does_not_modify_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            original=(ROOT/'waybar/config.jsonc').read_bytes()
            env=dict(os.environ,XDG_STATE_HOME=tmp)
            result=subprocess.run([str(ROOT/'scripts/bar.sh'),'render'],env=env,capture_output=True,text=True,check=True)
            generated=json.loads(Path(result.stdout.strip()).read_text())
            self.assertNotIn('include',generated)
            self.assertEqual((ROOT/'waybar/config.jsonc').read_bytes(),original)


if __name__=='__main__': unittest.main()
