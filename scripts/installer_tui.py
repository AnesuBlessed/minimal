#!/usr/bin/env python3
"""Responsive review screen; deployment is owned exclusively by install.py."""
import curses


def confirm(dry_run, config):
    def screen(win):
        curses.curs_set(0)
        lines = [
            'MINIMAL / Desktop setup', '',
            'Preview only' if dry_run else 'Install with a recoverable configuration backup',
            f'Destination: {config}', '',
            'Hyprland  /  Waybar  /  Rofi  /  Mako',
            'Foot  /  Wlogout  /  Fastfetch', '',
            'Your existing configurations are backed up before replacement.',
            'Package installation is handled after this screen.', '',
            'Enter: continue    Esc or q: cancel',
        ]
        while True:
            win.erase()
            h, w = win.getmaxyx()
            for y, text in enumerate(lines[:max(0, h - 2)]):
                win.addnstr(y, 0, text, max(0, w - 1))
            win.refresh()
            key = win.getch()
            if key in (10, 13, curses.KEY_ENTER):
                return True
            if key in (27, ord('q')):
                return False
    return curses.wrapper(screen)
