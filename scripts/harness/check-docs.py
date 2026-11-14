#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
base=root/'docs/features'
required={'FEATURE.md','TECHNICAL.md','API.md','DATABASE.md','TEST_PLAN.md','TEST_REPORT.md','CHANGELOG.md'}
errors=[]
for feature in sorted(p for p in base.iterdir() if p.is_dir()) if base.exists() else []:
 missing=required-{p.name for p in feature.iterdir() if p.is_file()}
 if missing: errors.append(f'{feature.name}: missing {", ".join(sorted(missing))}')
inv=root/'docs/FEATURE_INVENTORY.md'
inv_text=inv.read_text() if inv.exists() else ''
for feature in sorted(p for p in base.iterdir() if p.is_dir()) if base.exists() else []:
 if f'`{feature.name}`' not in inv_text: errors.append(f'{feature.name}: not listed in docs/FEATURE_INVENTORY.md')
print('Feature documentation structure OK' if not errors else '\n'.join(errors))
sys.exit(bool(errors))
