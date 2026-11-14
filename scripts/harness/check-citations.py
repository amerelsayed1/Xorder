#!/usr/bin/env python3
"""Mechanical citation check for the documentation core (read-only, stdlib only).

Resolves prefixed `path:line` citations (C: = apps/xorder-cloud/apps/api/, P: = apps/xorder-pos/,
W: = apps/xorder-cloud/apps/web/, or a workspace-relative `apps/...` path), reports missing files,
out-of-range lines and prefixed shorthand such as `C:Name.php:12` (no directories). Scope: feature core
files (BEHAVIORAL_ANALYSIS.md is excluded), the feature inventory and module docs. Existence and range only;
it cannot tell whether the cited line supports the sentence.
"""
import re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
PREFIX = {"C:": "apps/xorder-cloud/apps/api/", "P:": "apps/xorder-pos/", "W:": "apps/xorder-cloud/apps/web/", "K:": "apps/xorder-cloud/packages/", "A:": "apps/xorder-cloud/apps/"}
files = [p for p in sorted((root / "docs/features").glob("*/*.md")) if p.name != "BEHAVIORAL_ANALYSIS.md"]
files += [root / "docs/FEATURE_INVENTORY.md"] + sorted((root / "docs/modules").glob("*.md"))
cite = re.compile(r"(?<![\w/.-])((?:C:|P:|W:|K:|A:)?)((?:apps/|lib/|test/|app/|routes/|bootstrap/|database/|src/|docs/)[\w./{}<>*,-]*\.(?:php|dart|vue|js|md))(?::(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*))?")
short = re.compile(r"(?<![\w/.-])[CPWKA]:[A-Za-z_]+\.(?:php|dart|vue|js)\b")
bad, ok, file_only, shorthand = [], 0, 0, 0
for f in files:
    if not f.exists():
        continue
    for n, line in enumerate(f.read_text().splitlines(), 1):
        for m in short.finditer(line):
            shorthand += 1
            bad.append((f.relative_to(root), n, f"shorthand citation {m.group(0)}"))
        for m in cite.finditer(line):
            prefix, path, lines = m.groups()
            if any(c in path for c in "*{<"):
                continue
            if path.startswith("apps/"):
                target = root / path
            elif prefix in PREFIX:
                target = root / (PREFIX[prefix] + path)
            else:
                continue  # unprefixed relative path: cannot be resolved mechanically
            if not target.exists():
                bad.append((f.relative_to(root), n, f"missing file {prefix}{path}"))
                continue
            if not lines:
                file_only += 1
                continue
            total = len(target.read_text(errors="replace").splitlines())
            for part in lines.split(","):
                a, _, b = part.partition("-")
                if int(a) < 1 or int(b or a) > total:
                    bad.append((f.relative_to(root), n, f"line {part} outside {prefix}{path} ({total} lines)"))
                    break
            else:
                ok += 1
print(f"citation check: {ok} line citations resolve, {file_only} file-only references, {shorthand} shorthand, {len(bad)} problem(s)")
for b in bad:
    print("PROBLEM", *b)
sys.exit(1 if bad else 0)
