#!/usr/bin/env python3
"""Structural validation of the workspace Claude harness (read-only, stdlib only)."""
import json, re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
errors, warnings = [], []
OLD_NAME = "xorder-" + "new"  # retired name of xorder-cloud
TOOLS = {"Read", "Write", "Edit", "Grep", "Glob", "Bash", "WebFetch", "WebSearch", "TodoWrite", "Task", "Agent", "NotebookEdit"}

def frontmatter(path):
    text = path.read_text()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None, text
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm, text[m.end():]

skills = sorted((root / ".claude/skills").glob("*/SKILL.md"))
names = set()
for f in skills:
    fm, body = frontmatter(f)
    d = f.parent.name
    if fm is None: errors.append(f"skill {d}: missing YAML frontmatter"); continue
    if fm.get("name") != d: errors.append(f"skill {d}: name '{fm.get('name')}' != directory")
    if not fm.get("description"): errors.append(f"skill {d}: missing description")
    if len(body.strip()) < 800: warnings.append(f"skill {d}: body is very short ({len(body.strip())} chars)")
    names.add(d)

agents = sorted((root / ".claude/agents").glob("*.md"))
for f in agents:
    fm, body = frontmatter(f)
    if fm is None: errors.append(f"agent {f.name}: missing YAML frontmatter"); continue
    if fm.get("name") != f.stem: errors.append(f"agent {f.name}: name '{fm.get('name')}' != filename")
    if not fm.get("description"): errors.append(f"agent {f.name}: missing description")
    bad = {t.strip() for t in fm.get("tools", "").split(",") if t.strip()} - TOOLS
    if bad: errors.append(f"agent {f.name}: unknown tools {sorted(bad)}")

try:
    s = json.loads((root / ".claude/settings.json").read_text())
    deny = " ".join(s.get("permissions", {}).get("deny", []))
    for needed in ("db-backups", ".env"):
        if needed not in deny: errors.append(f"settings.json: no deny rule mentioning {needed}")
except Exception as e:
    errors.append(f"settings.json invalid: {e}")

for r in ("architecture", "coding-standards", "database-safety", "documentation", "security", "testing", "cloud-laravel-vue", "pos-flutter", "postgres-migrations", "api-contracts", "reporting", "domain-expert", "production-safety", "knowledge"):
    if not (root / f".claude/rules/{r}.md").exists(): errors.append(f"rules/{r}.md missing")
if not (root / "CLAUDE.md").exists(): errors.append("CLAUDE.md missing")
for t in ("FEATURE", "TECHNICAL", "API", "DATABASE", "TEST_PLAN", "TEST_REPORT", "CHANGELOG"):
    if not (root / f"docs/templates/{t}.md").exists(): errors.append(f"docs/templates/{t}.md missing")

# Three jobs, three skills (2026-10-25): develop-feature writes the description, bug-investigation finds the root cause,
# implement builds and tests. Each only references skills that exist; implement documents every build phase.
EXPECTED_SKILLS = {"develop-feature", "implement", "project-documentation", "bug-investigation", "security-audit", "project-testing", "release-check"}
for extra in sorted(set(names) - EXPECTED_SKILLS): warnings.append(f"unexpected skill {extra} (consolidated set is {sorted(EXPECTED_SKILLS)})")
for missing in sorted(EXPECTED_SKILLS - set(names)): errors.append(f"skill {missing} missing")
for skill, phases in (("develop-feature", ("discover",)), ("implement", ("plan", "implement", "test", "review", "ready")), ("bug-investigation", ())):
    f = root / f".claude/skills/{skill}/SKILL.md"
    if not f.exists(): continue
    txt = f.read_text()
    for phase in phases:
        if f"## Phase: {phase}" not in txt: errors.append(f"{skill}: phase {phase} not documented")
    for ref in set(re.findall(r"`/([a-z]+(?:-[a-z]+)+)", txt)):
        if ref not in names: errors.append(f"{skill} references missing skill /{ref}")

# Knowledge layer: project-documentation skill and lifecycle integration
pd = root / ".claude/skills/project-documentation"
for rel in ("SKILL.md", "references/discovery-workflow.md", "references/documentation-standards.md", "references/progress-management.md",
            "references/validation-rules.md", "references/cross-application-analysis.md", "references/knowledge-retrieval.md",
            "templates/PROJECT_OVERVIEW.md", "templates/FEATURE_INVENTORY.md", "templates/MODULE.md", "templates/FEATURE.md", "templates/TECHNICAL.md",
            "templates/API.md", "templates/DATABASE.md", "templates/WORKFLOWS.md", "templates/BEHAVIORAL_ANALYSIS.md", "templates/DOCUMENTATION_PROGRESS.md"):
    if not (pd / rel).exists(): errors.append(f"project-documentation: {rel} missing")
for cmd in ("scan", "plan", "all", "module", "feature", "update", "validate", "status", "context"):
    sk = pd / "SKILL.md"
    if sk.exists() and f"`{cmd}" not in sk.read_text(): errors.append(f"project-documentation: command {cmd} not documented in SKILL.md")
for s in ("develop-feature", "bug-investigation", "implement"):
    f = root / f".claude/skills/{s}/SKILL.md"
    if f.exists() and "project-documentation" not in f.read_text(): errors.append(f"skill {s}: does not reference /project-documentation")
for need in ("docs/FEATURE_INVENTORY.md", "docs/PROJECT_OVERVIEW.md", "docs/DOCUMENTATION_PROGRESS.md"):
    if not (root / need).exists(): errors.append(f"{need} missing")
if "knowledge.md" not in (root / "CLAUDE.md").read_text(): warnings.append("CLAUDE.md does not point to .claude/rules/knowledge.md")

# Stale workspace name
for p in [root/"CLAUDE.md", root/"README.md", root/".claude/skills", root/".claude/agents", root/".claude/rules", root/"scripts/harness/verify.sh"]:
    for f in ([p] if p.is_file() else p.rglob("*.md")):
        if f.is_file() and OLD_NAME in f.read_text():
            warnings.append(f"{f.relative_to(root)} mentions stale name {OLD_NAME}")

broken=[str(l.relative_to(root)) for l in list((root/".claude/agents").glob("*"))+list((root/".claude/skills").glob("*")) if l.is_symlink() and not l.exists()]
for b in broken: errors.append(f"broken symlink {b}")
print(f"Harness: {len(skills)} skills, {len(agents)} agents checked ({sum(1 for l in list((root/'.claude/agents').glob('*'))+list((root/'.claude/skills').glob('*')) if l.is_symlink())} linked from app repos)")
for w in warnings: print("WARN:", w)
for e in errors: print("ERROR:", e)
print("Harness structure OK" if not errors else f"{len(errors)} harness error(s)")
sys.exit(1 if errors else 0)
