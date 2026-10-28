"""Small, dependency-free JSONC reader and Minimal bar configuration resolver."""
import json
import re
from pathlib import Path


def read_jsonc(path):
    text = Path(path).read_text()
    # Preserve quoted strings (including URLs) while removing comments.
    token = r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/'
    text = re.sub(token, lambda m: m[0] if m[0].startswith('"') else ' ', text)
    text = re.sub(r'"(?:\\.|[^"\\])*"|,\s*(?=[}\]])',
                  lambda m: m[0] if m[0].startswith('"') else '', text)
    return json.loads(text)


def resolve(path, seen=None):
    path = Path(path).resolve()
    seen = set() if seen is None else seen
    if path in seen:
        raise ValueError(f'Circular include: {path}')
    data = read_jsonc(path)
    if not isinstance(data, dict):
        raise ValueError(f'Expected an object: {path}')
    merged = dict(data)
    for include in data.get('include', []):
        child = resolve(path.parent / include, seen | {path})
        for key, value in child.items():
            merged.setdefault(key, value)
    merged.pop('include', None)
    return merged


def validate_bar(path):
    data = resolve(path)
    def check(names, stack=()):
        for name in names:
            if name in stack:
                raise ValueError(f'Circular group: {name}')
            if name not in data:
                raise ValueError(f'{path}: undefined module {name}')
            if name.startswith('group/'):
                check(data[name]['modules'], (*stack, name))
    for side in ('left', 'center', 'right'):
        check(data.get('modules-' + side, []))
    return data
