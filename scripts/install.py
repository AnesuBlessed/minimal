#!/usr/bin/env python3
"""Minimal deployment engine. Python standard library only; no resident process."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from minimal_config import validate_bar

ROOT = Path(__file__).resolve().parent.parent
COMPONENTS = ('hypr', 'waybar', 'rofi', 'mako', 'foot', 'wlogout', 'fastfetch')
# Package names are separate from the executables they supply.
# Core packages required for Minimal's desktop session.
CORE_PACKAGES = {
    'hyprland': 'Hyprland', 'waybar': 'waybar', 'rofi': 'rofi',
    'mako': 'mako', 'foot': 'foot', 'wlogout': 'wlogout',
    'hyprpaper': 'hyprpaper', 'hypridle': 'hypridle', 'hyprlock': 'hyprlock',
    'wireplumber': 'wpctl', 'brightnessctl': 'brightnessctl',
    'cliphist': 'cliphist', 'wl-clipboard': 'wl-copy', 'grim': 'grim',
    'slurp': 'slurp', 'ttf-jetbrains-mono-nerd': None,
    'playerctl': 'playerctl', 'libnotify': 'notify-send',
    'pacman-contrib': 'checkupdates',
    'hyprpolkitagent': '/usr/lib/hyprpolkitagent/hyprpolkitagent',
    'xdg-desktop-portal-hyprland': None, 'xdg-desktop-portal-gtk': None,
    'xdg-utils': 'xdg-open', 'fastfetch': 'fastfetch',
}

# Optional packages for enhanced features (annotator, OCR, tray applets, GUI tools).
OPTIONAL_PACKAGES = {
    'pamixer': 'pamixer',
    'satty': 'satty',
    'tesseract': 'tesseract',
    'tesseract-data-eng': None,
    'network-manager-applet': 'nm-applet',
    'blueman': 'blueman-manager',
    'pavucontrol': 'pavucontrol',
    'thunar': 'thunar',
    'firefox': 'firefox',
}

PACKAGES = {**CORE_PACKAGES, **OPTIONAL_PACKAGES}


def xdg(name, fallback):
    value = Path(os.environ.get(name, str(Path.home() / fallback)))
    if not value.is_absolute():
        raise ValueError(f'{name} must be absolute')
    return value


def paths():
    return xdg('XDG_CONFIG_HOME', '.config'), xdg('XDG_STATE_HOME', '.local/state') / 'minimal'


def exists(path):
    return path.exists() or path.is_symlink()


def remove(path):
    # Only real directories are trees; files, symlinks, FIFOs and sockets unlink.
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif exists(path):
        path.unlink()


def copy(source, dest):
    if source.is_symlink():
        dest.symlink_to(os.readlink(source))
    elif source.is_dir():
        shutil.copytree(source, dest, symlinks=True)
    else:
        shutil.copy2(source, dest)


def write_atomic(path, text):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(text)
    temporary.replace(path)


def write_json(path, data):
    write_atomic(path, json.dumps(data, indent=2) + '\n')


def previous_snapshot(state):
    """Return (snapshot, manifest) for the recorded recovery point, if usable."""
    try:
        snapshot = Path((state / 'latest_backup').read_text().strip())
        return snapshot, json.loads((snapshot / 'manifest.json').read_text())
    except (OSError, ValueError):
        return None, None


def is_minimal_link(path, name, roots):
    """True when path is a symlink Minimal itself created for component name."""
    if not path.is_symlink():
        return False
    target = path.resolve()
    return any(target == Path(r).resolve() / name for r in roots)


def restore(snapshot, dry_run=False):
    manifest = json.loads((snapshot / 'manifest.json').read_text())
    config = Path(manifest['config'])
    if not config.is_absolute() or set(manifest['components']) != set(COMPONENTS):
        raise ValueError('Invalid backup manifest')
    # Prepare every original before touching deployed files.
    if dry_run:
        print(f'Would restore {snapshot} to {config}')
        return
    config.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.minimal-restore-', dir=config) as tmp:
        stage = Path(tmp)
        for name, present in manifest['components'].items():
            if present:
                copy(snapshot / 'original' / name, stage / name)
        for name, present in manifest['components'].items():
            remove(config / name)
            if present:
                (stage / name).replace(config / name)
    print(f'Restored {snapshot}')


def deploy(root, config, state, dry_run=False):
    for name in COMPONENTS:
        if not (root / name).is_dir():
            raise ValueError(f'Missing component: {name}')
    if dry_run:
        for name in COMPONENTS:
            print(f'Would back up {config / name} and link to {root / name}')
        return None
    # Reinstall of the same checkout is a no-op, preserving the recovery point.
    if all((config / n).is_symlink() and (config / n).resolve() == root / n for n in COMPONENTS):
        print('All components already linked; existing recovery point retained.')
        return None
    config.mkdir(parents=True, exist_ok=True)
    backups = state / 'backups'
    backups.mkdir(parents=True, exist_ok=True)
    # Paths that are already Minimal's own links must not be snapshotted as
    # "originals"; carry the user's real originals over from the prior snapshot.
    prior, prior_manifest = previous_snapshot(state)
    roots = {str(root)}
    if prior_manifest and Path(prior_manifest.get('config', '')) == config:
        roots.add(prior_manifest.get('root', str(root)))
    else:
        prior = prior_manifest = None
    sources = {}
    links = {}  # Minimal links present before this run, for exact rollback.
    for name in COMPONENTS:
        if is_minimal_link(config / name, name, roots):
            links[name] = os.readlink(config / name)
            carried = prior_manifest and prior_manifest['components'].get(name)
            sources[name] = prior / 'original' / name if carried else None
        else:
            sources[name] = config / name if exists(config / name) else None
    snapshot = Path(tempfile.mkdtemp(prefix='backup-' + datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S-'), dir=backups))
    (snapshot / 'original').mkdir()
    manifest = {'version': 1, 'config': str(config), 'root': str(root),
                'components': {name: sources[name] is not None for name in COMPONENTS}}
    # Back up everything before removing anything, including broken symlinks.
    for name, source in sources.items():
        if source is not None:
            copy(source, snapshot / 'original' / name)
    write_json(snapshot / 'manifest.json', manifest)
    # Standalone recovery survives moving or deleting the checkout.
    shutil.copy2(Path(__file__), snapshot / 'install.py')
    shutil.copy2(Path(__file__).with_name('minimal_config.py'), snapshot / 'minimal_config.py')
    recovery = snapshot / 'restore.sh'
    recovery.write_text('#!/usr/bin/env bash\nset -euo pipefail\nbase=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")\nexec python3 "$base/install.py" --restore "$base" "$@"\n')
    recovery.chmod(0o755)
    # latest_backup is only advanced after a successful deploy (below), so a
    # failed run never displaces the previous good recovery point.
    try:
        with tempfile.TemporaryDirectory(prefix='.minimal-stage-', dir=config) as tmp:
            stage = Path(tmp)
            for name in COMPONENTS:
                (stage / name).symlink_to(root / name)
            for name in COMPONENTS:
                remove(config / name)
                (stage / name).replace(config / name)
    except BaseException:
        # Return to the exact pre-run state: user originals plus any Minimal
        # links that already existed. The unreferenced snapshot is discarded.
        restore(snapshot)
        for name, target in links.items():
            remove(config / name)
            (config / name).symlink_to(target)
        shutil.rmtree(snapshot, ignore_errors=True)
        raise
    write_atomic(state / 'latest_backup', str(snapshot) + '\n')
    print(f'Deployed Minimal. Recovery: {recovery}')
    return snapshot


def missing_packages(packages=None):
    if packages is None:
        packages = CORE_PACKAGES
    missing = []
    for package, binary in packages.items():
        if binary and shutil.which(binary):
            continue
        if shutil.which('pacman') and subprocess.run(['pacman', '-Qq', package], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            continue
        missing.append(package)
    return missing


def unavailable_packages(packages):
    """Packages pacman's sync repositories cannot provide (e.g. AUR-only)."""
    if not shutil.which('pacman'):
        return list(packages)
    return [p for p in packages if subprocess.run(['pacman', '-Si', p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode]


def doctor(root=ROOT):
    from check import check
    errors = check(root)
    for path in [root / 'waybar/config.jsonc', *sorted((root / 'waybar/layouts').glob('[0-9][0-9].jsonc'))]:
        try:
            validate_bar(path)
        except (ValueError, OSError, KeyError) as exc:
            print(f'FAIL: {exc}')
            errors += 1
    if not errors:
        print('PASS: active bar and all layout includes/module references')
    binary = shutil.which('Hyprland')
    if binary:
        result = subprocess.run([binary, '--config', str(root / 'hypr/hyprland.lua'), '--verify-config'], capture_output=True, text=True)
        output = result.stdout + result.stderr
        if result.returncode or 'config ok' not in output.lower():
            print('FAIL: Hyprland configuration\n' + output)
            errors += 1
        else:
            print('PASS: Hyprland configuration')
    else:
        print('FAIL: Hyprland unavailable; compositor validation skipped')
        errors += 1
    # Hyprland honours $HYPRLAND_CONFIG over ~/.config/hypr, silently bypassing Minimal.
    override = os.environ.get('HYPRLAND_CONFIG')
    expected = paths()[0] / 'hypr/hyprland.lua'
    if override and Path(override).expanduser().resolve() != expected.resolve():
        print(f'FAIL: HYPRLAND_CONFIG={override} overrides Minimal ({expected}); unset it in your shell/session environment')
        errors += 1
    missing_core = missing_packages(CORE_PACKAGES)
    if missing_core:
        print('FAIL: missing core dependencies: ' + ', '.join(missing_core))
        errors += 1
    missing_opt = missing_packages(OPTIONAL_PACKAGES)
    if missing_opt:
        print('INFO: optional packages not installed: ' + ', '.join(missing_opt))
    print('Live rendering, hardware and suspend/resume require a desktop smoke test.')
    return 1 if errors else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description='Minimal desktop deployment and recovery')
    parser.add_argument('--dry-run', action='store_true', help='Print the plan without changing files or installing packages')
    parser.add_argument('-y', '--yes', action='store_true')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--restore', nargs='?', const='latest', metavar='SNAPSHOT')
    mode.add_argument('--uninstall', action='store_true', help='Restore the latest recorded snapshot')
    mode.add_argument('--doctor', action='store_true')
    parser.add_argument('--no-tui', action='store_true')
    parser.add_argument('--all-packages', action='store_true', help='Include optional desktop apps (Firefox, Thunar, Satty, Tesseract, Blueman, Pavucontrol)')
    parser.add_argument('--skip-packages', action='store_true', help='Deploy configs only; dependencies must be supplied separately')
    args = parser.parse_args(argv)
    config, state = paths()
    if args.doctor:
        return doctor()
    if args.restore or args.uninstall:
        choice = args.restore or 'latest'
        snapshot = Path((state / 'latest_backup').read_text().strip()) if choice == 'latest' else Path(choice).resolve()
        if args.dry_run:
            restore(snapshot, True)
            return 0
        # Standalone restore uses the same lock as deployment.
        state.mkdir(parents=True, exist_ok=True)
        with (state / 'install.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            restore(snapshot)
        return 0
    if sys.stdin.isatty() and not args.yes and not args.no_tui:
        from installer_tui import confirm
        if not confirm(args.dry_run, config):
            return 0
    # Structural preflight runs before any system change (packages or files).
    for path in [ROOT / 'waybar/config.jsonc', *sorted((ROOT / 'waybar/layouts').glob('[0-9][0-9].jsonc'))]:
        validate_bar(path)
    for name in COMPONENTS:
        if not (ROOT / name).is_dir():
            raise ValueError(f'Missing component: {name}')
    if not args.skip_packages:
        target_pkgs = PACKAGES if args.all_packages else CORE_PACKAGES
        missing = missing_packages(target_pkgs)
        if missing:
            label = 'packages' if args.all_packages else 'core desktop packages'
            print(f'Missing {label}: ' + ' '.join(missing))
            unavailable = unavailable_packages(missing)
            if unavailable:
                print('Not in your pacman repositories (install from the AUR or another source, '
                      'then re-run, or use --skip-packages): ' + ' '.join(unavailable))
                if not args.dry_run:
                    return 1
            if not args.dry_run:
                if not args.yes and input('Install these packages with pacman? [y/N] ').lower() not in ('y', 'yes'):
                    print('Installation cancelled; use --skip-packages for config-only deployment.')
                    return 1
                subprocess.run(['sudo', 'pacman', '-S', '--needed', *(['--noconfirm'] if args.yes else []), *missing], check=True)
    if args.dry_run:
        deploy(ROOT, config, state, True)
        print('Dry run complete; no files changed.')
        return 0
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'install.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        deploy(ROOT, config, state)
    print('Start a fresh Hyprland session to activate Minimal. Run ./install.sh --doctor for diagnostics.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
