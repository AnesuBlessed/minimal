#!/usr/bin/env python3
"""Generate native theme values from theme.json; unchanged files are not rewritten."""
import json
from pathlib import Path
import re
from update_fuzzel_colors import atomic_write
ROOT = Path(__file__).resolve().parent.parent

def sync():
    theme = json.loads((ROOT / 'theme.json').read_text())
    c, o, r, f = (theme[k] for k in ('colors', 'opacity', 'radius', 'font'))
    if any(not re.fullmatch(r'[0-9a-fA-F]{6}', value) for value in c.values()):
        raise ValueError('Theme colors must be six hexadecimal digits')
    if any(not 0 <= value <= 1 for value in o.values()):
        raise ValueError('Theme opacity must be between zero and one')
    def alpha(value): return f'{round(value * 255):02x}'
    def patch(relative, replacements):
        path = ROOT / relative
        text = path.read_text()
        for pattern, replacement in replacements:
            rep = replacement if callable(replacement) else (lambda _m, r=replacement: r)
            text = re.sub(pattern, rep, text, flags=re.M)
        atomic_write(path, text)
    bg, surface, accent = c['base'], c['surface'], c['accent']
    seconds = theme['motion']['duration'] / 1000
    values = {'background':bg+alpha(o['panel']), 'text':c['text']+'ff',
              'message':c['muted']+'99', 'prompt':accent+'ff', 'placeholder':c['muted']+'ff',
              'input':c['text']+'ff', 'match':accent+'ff', 'selection':surface+'ee',
              'selection-text':c['text']+'ff', 'selection-match':accent+'ff',
              'border':accent+alpha(o['border'])}
    path = ROOT / 'fuzzel/fuzzel.ini'
    main, remainder = path.read_text().split('[colors]', 1)
    section, border = remainder.split('[border]', 1)
    main = re.sub(r'^font=.*$', lambda _m: f'font={f["family"]}:size={f["secondary"]}', main, flags=re.M)
    for key, value in values.items():
        section = re.sub(r'^'+key+r'=.*$', key+'='+value, section, flags=re.M)
    border = re.sub(r'^radius=.*$', f'radius={r["panel"]}', border, flags=re.M)
    border = re.sub(r'^selection-radius=.*$', f'selection-radius={r["control"]}', border, flags=re.M)
    atomic_write(path, main+'[colors]'+section+'[border]'+border)
    definitions = {'bg-glass':f'alpha(#{bg}, {o["panel"]})',
                   'bg-reading':f'alpha(#{bg}, {o["reading"]})',
                   'bg-glass-hover':f'alpha(#{surface}, {o["control"]})',
                   'border-glass':f'alpha(#{accent}, {o["border"]})',
                   'text-main':'#'+c['text'], 'text-muted':'#'+c['muted'],
                   'text-dim':'#'+c['muted'], 'accent':'#'+accent, 'accent-dark':'#'+bg,
                   'warning':'#'+c['warning'], 'critical':'#'+c['critical']}
    css = '/* Generated from theme.json by scripts/sync-theme.py. */\n'
    css += ''.join(f'@define-color {k} {v};\n' for k,v in definitions.items())
    atomic_write(ROOT/'colors.css', css)
    atomic_write(ROOT/'waybar/theme.css', '''/* Shared palette aliases; colors.css is loaded first. */
@define-color bar-bg transparent;
@define-color main-bg @bg-glass;
@define-color main-fg @text-main;
@define-color wb-act-bg @accent;
@define-color wb-act-fg @accent-dark;
@define-color wb-hvr-bg @bg-glass-hover;
@define-color wb-hvr-fg @text-main;
@define-color wb-color @text-main;
@define-color wb-act-color @accent-dark;
@define-color wb-hvr-color @text-main;
''')
    patch('hypr/colors.lua', [(r'('+k+r'\s*=\s*)"[^"]*"', lambda m,v=v:m[1]+'"'+v+'"') for k,v in {
        'accent':f'rgba({accent}ee)', 'accent_subtle':f'rgba({accent}66)',
        'border_dark':f'rgba({surface}cc)', 'bg_dark':f'0x{bg}', 'text_main':f'0x{c["text"]}'}.items()])
    path = ROOT/'mako/config'
    section = ''
    lines = []
    for line in path.read_text().splitlines():
        if line.startswith('['): section = line
        if line.startswith('background-color='): line = f'background-color=#{bg}{alpha(o["reading"])}'
        elif line.startswith('text-color='): line = 'text-color=#'+c['text']
        elif line.startswith('border-color='): line = '#'+(c['critical'] if section == '[urgency=critical]' else accent)+alpha(o['border']); line='border-color='+line
        elif line.startswith('progress-color='): line = 'progress-color=over #'+accent+'66'
        elif line.startswith('border-radius='): line = 'border-radius='+str(r['control'] if section == '[app-name=minimal-osd]' else r['panel'])
        elif line.startswith('font='): line = f'font={f["family"]} {f["secondary"] if section == "[app-name=minimal-osd]" else f["body"]}'
        lines.append(line)
    atomic_write(path, '\n'.join(lines)+'\n')
    patch('hypr/hyprlock.conf', [(r'^\$font =.*$', f'$font = {f["family"]}'), (r'^\$accent =.*$', f'$accent = rgb({accent})'),
        (r'^\$base =.*$',f'$base = rgb({bg})'),
        (r'^\$surface =.*$',f'$surface = rgb({surface})'),
        (r'^\$text =.*$',f'$text = rgb({c["text"]})'),
        (r'^\$critical =.*$',f'$critical = rgb({c["critical"]})'),
        (r'^    rounding = \d+$',f'    rounding = {r["control"]}')])
    patch('foot/foot.ini', [(r'^background=.*$', 'background='+bg),
        (r'^foreground=.*$', 'foreground='+c['text']), (r'^alpha=.*$',f'alpha={o["reading"]}'),
        (r'^cursor=[0-9a-f].*$',f'cursor={bg} {accent}'),
        (r'^selection-background=.*$', 'selection-background='+surface),
        (r'^selection-foreground=.*$', 'selection-foreground='+c['text'])])
    # Geometry and type values for the native CSS clients.
    waybar_groups = ', '.join(
        f'window#waybar #{g}'
        for g in (
            'pill', 'pill-right', 'pill-left', 'pill-down', 'pill-up', 'pill-in', 'pill-out',
            'leaf', 'leaf-inverse', 'leaf-up', 'leaf-down', 'leaf-right', 'leaf-left',
        )
    )
    atomic_write(ROOT/'waybar/design.css', f'''/* Generated from theme.json. */
* {{ font-family: "{f['family']}"; font-size: {f['body']}px; }}
{waybar_groups} {{ border-radius: {r['panel']}px; }}
#workspaces button, menu menuitem {{ border-radius: {r['control']}px; }}
tooltip, menu {{ border-radius: {r['panel']}px; }}
#workspaces button, #taskbar button, menu menuitem {{ transition-duration: {seconds:g}s; }}
''')
    atomic_write(ROOT/'wlogout/design.css', f'''/* Generated from theme.json. */
* {{ font-family: "{f['family']}"; font-size: {f['title']}px; }}
button {{ border-radius: {r['panel']}px; transition-duration: {seconds:g}s; }}
''')

if __name__ == '__main__':
    sync()
