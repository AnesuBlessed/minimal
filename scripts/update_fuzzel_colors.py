#!/usr/bin/env python3
import os
import re

shell_colors = os.path.expanduser("~/.cache/hyde/wallbash/shell-colors")
fuzzel_conf = os.path.expanduser("~/Projects/minimal/fuzzel/fuzzel.ini")

if not os.path.exists(shell_colors) or not os.path.exists(fuzzel_conf):
    exit(0)

colors = {}
with open(shell_colors) as f:
    for line in f:
        m = re.match(r"^(\w+)=['\"]?#?([0-9a-fA-F]{6})['\"]?", line.strip())
        if m:
            colors[m.group(1)] = m.group(2)

bg = colors.get("wallbash_pry1", "181822")
accent = colors.get("wallbash_1xa7", "b8c470")
pill = colors.get("wallbash_1xa4", "383848")
match = colors.get("wallbash_1xa9", "ffffff")

with open(fuzzel_conf) as f:
    lines = f.readlines()

in_colors = False
new_lines = []
for line in lines:
    if line.strip().startswith("[colors]"):
        in_colors = True
        new_lines.append(line)
        continue
    elif line.strip().startswith("[") and in_colors:
        in_colors = False

    if in_colors:
        if line.startswith("background="):
            new_lines.append(f"background={bg}f0\n")
        elif line.startswith("prompt="):
            new_lines.append(f"prompt={accent}ff\n")
        elif line.startswith("match="):
            new_lines.append(f"match={accent}ff\n")
        elif line.startswith("selection="):
            new_lines.append(f"selection={pill}ee\n")
        elif line.startswith("selection-match="):
            new_lines.append(f"selection-match={match}ff\n")
        elif line.startswith("border="):
            new_lines.append(f"border={accent}55\n")
        elif line.startswith("text="):
            new_lines.append("text=ffffffff\n")
        elif line.startswith("selection-text="):
            new_lines.append("selection-text=ffffffff\n")
        else:
            new_lines.append(line)
    elif line.startswith("prompt="):
        # Keep the search icon in [main]
        new_lines.append('prompt="   "\n')
    else:
        new_lines.append(line)

with open(fuzzel_conf, "w") as f:
    f.writelines(new_lines)

# Sync to ~/.config/fuzzel/fuzzel.ini if different
user_fuzzel = os.path.expanduser("~/.config/fuzzel/fuzzel.ini")
if not os.path.samefile(fuzzel_conf, user_fuzzel):
    with open(user_fuzzel, "w") as f:
        f.writelines(new_lines)
