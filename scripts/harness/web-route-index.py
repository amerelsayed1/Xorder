#!/usr/bin/env python3
"""Static index of the dashboard SPA routes (apps/xorder-cloud/apps/web/src/router/index.js). Read-only, stdlib only.
Prints markdown: section (portal array), path as written (relative to its parent layout), name, page file, meta capability/feature/role."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
src = (root / "apps/xorder-cloud/apps/web/src/router/index.js").read_text()
section, rows = "", []
for n, line in enumerate(src.splitlines(), 1):
    m = re.match(r"\s*const (\w+Routes)\s*=\s*\[", line)
    if m:
        section = m.group(1)
    p = re.search(r"path:\s*'([^']*)'", line)
    if not p:
        continue
    name = re.search(r"name:\s*'([^']*)'", line)
    comp = re.search(r"import\('\.\./([^']+)'\)", line)
    meta = re.search(r"meta:\s*\{([^}]*)\}", line)
    rows.append((section, p.group(1), name.group(1) if name else "", comp.group(1) if comp else "", meta.group(1).strip() if meta else "", n))
print("| Section | Path | Name | Page | Meta | router/index.js |")
print("| --- | --- | --- | --- | --- | --- |")
for s, p, nm, c, meta, n in rows:
    print(f"| {s} | `{p}` | {nm or '-'} | {('`' + c + '`') if c else '-'} | {meta.replace('|', chr(92) + '|') or '-'} | {n} |")
