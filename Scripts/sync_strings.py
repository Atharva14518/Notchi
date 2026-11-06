#!/usr/bin/env python3
"""Sync UI and App Shortcut phrase catalogs after a Debug or Release build."""
from pathlib import Path
import argparse, json, subprocess, plistlib
root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--configuration', default='Debug')
args = parser.parse_args()
metadata = root / 'build/Build/Intermediates.noindex/Notchi.build' / args.configuration / 'Notchi.build'
files = sorted(metadata.rglob('*.stringsdata'))
if not files:
    raise SystemExit('Build the app first with SWIFT_EMIT_LOC_STRINGS=YES.')
used = {}
for path in files:
    raw = path.read_bytes()
    source = plistlib.loads(raw) if raw.startswith(b'bplist') else json.loads(raw)
    for table, entries in source.get('tables', {}).items():
        used.setdefault(table, set()).update(item['key'] for item in entries)
for table in ['Localizable', 'AppShortcuts']:
    catalog = root / 'Resources' / (table + '.xcstrings')
    subprocess.run(['xcrun', 'xcstringstool', 'sync', str(catalog), '--stringsdata',
                    *[str(p) for p in files], '--skip-marking-strings-stale'], check=True)
    data = json.loads(catalog.read_text())
    for key, entry in list(data['strings'].items()):
        # Preserve manual dynamic keys and translations for explicit review.
        if key not in used.get(table, set()) and entry.get('extractionState') != 'manual' and set(entry.get('localizations', {})) <= {'en'}:
            del data['strings'][key]
    for key, entry in data['strings'].items():
        if key:
            entry.setdefault('localizations', {}).setdefault('en', {'stringUnit': {'state': 'translated', 'value': key}})
    catalog.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print(f'{table}: {len(data["strings"])} keys')
