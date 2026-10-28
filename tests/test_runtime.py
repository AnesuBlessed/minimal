import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='minimal runtime ')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base/'bin';self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin)+':'+os.environ['PATH'], XDG_STATE_HOME=str(self.base/'state'))
        self.stub('notify-send', 'exit 0')
        self.stub('sleep', 'exit 0')

    def stub(self,name,body):
        path=self.bin/name;path.write_text('#!/bin/sh\n'+body+'\n');path.chmod(0o755)

    def wallpaper(self):
        wall=self.base/'wall with spaces.png';wall.write_bytes(b'test asset')
        return wall

    def test_wallpaper_failure_preserves_previous_selection(self):
        self.stub('hyprctl','echo "error: unavailable"; exit 0')
        state=self.base/'state/minimal';state.mkdir(parents=True)
        (state/'current_wallpaper').write_text('previous')
        result=subprocess.run([str(ROOT/'scripts/wallpaper.sh'),str(self.wallpaper())],env=self.env,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((state/'current_wallpaper').read_text(),'previous')
        self.assertFalse((state/'wallpaper.set').exists())

    def test_wallpaper_success_records_absolute_path(self):
        self.stub('hyprctl','echo ok')
        wall=self.wallpaper()
        subprocess.run([str(ROOT/'scripts/wallpaper.sh'),str(wall)],env=self.env,check=True,capture_output=True)
        state=self.base/'state/minimal'
        self.assertEqual((state/'current_wallpaper').read_text().strip(),str(wall))
        self.assertEqual((state/'wallpaper.set').resolve(),wall)

    def test_update_failure_is_not_zero_updates(self):
        self.stub('checkupdates','exit 1')
        result=subprocess.run([str(ROOT/'scripts/updates.sh')],env=self.env,capture_output=True,text=True,check=True)
        self.assertEqual(json.loads(result.stdout)['class'],'unavailable')

    def test_no_updates_is_valid_empty_status(self):
        self.stub('checkupdates','exit 2')
        result=subprocess.run([str(ROOT/'scripts/updates.sh')],env=self.env,capture_output=True,text=True,check=True)
        self.assertEqual(json.loads(result.stdout)['text'],'')

    def test_clipboard_follows_bottom_bar(self):
        state=self.base/'state/minimal';state.mkdir(parents=True)
        (state/'waybar.json').write_text('{"position":"bottom", "height":40}')
        result=subprocess.run(['python3',str(ROOT/'scripts/clipboard-placement.py')],env=self.env,capture_output=True,text=True,check=True)
        self.assertIn('south east',result.stdout)
        self.assertIn('y-offset: -54px',result.stdout)

    def test_powermenu_tempfiles_are_removed(self):
        self.stub('pgrep','exit 1')
        self.stub('wlogout','printf "%s\\n" "$@" > "$TEST_ARGUMENTS"')
        args=self.base/'args'
        subprocess.run([str(ROOT/'scripts/powermenu.sh')],env=dict(self.env,TEST_ARGUMENTS=str(args)),check=True,capture_output=True)
        values=args.read_text().splitlines()
        for flag in ['--layout','--css']:
            self.assertFalse(Path(values[values.index(flag)+1]).exists())


if __name__=='__main__':unittest.main()
