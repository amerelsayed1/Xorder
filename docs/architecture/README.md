# Architecture documents

| File | What it holds |
| --- | --- |
| `repo-map.md` | Repositories, verified stack, entry points, integration surface (verified 2026-10-20) |
| `cloud-route-index.md` | Generated static index of the 252 cloud routes (`scripts/harness/route-index.py`) |
| `web-route-index.md` | Generated index of the dashboard SPA routes (`scripts/harness/web-route-index.py`) |
| `feature-route-map.md` | Per feature: footprint, route counts, gates, Vue pages by name; the footprint rules and method notes |
| `../PROJECT_OVERVIEW.md` | Platform map, authentication/tenancy table, cross-application analysis, documented-vs-actual differences |
| `../FEATURE_INVENTORY.md` | Every module and feature with entry points, contracts, tables, tests, documentation and verification status |
| `../modules/` | One architecture doc per module |
| `../features/<slug>/` | Per-feature docs (FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG, optional WORKFLOWS) |
| `../DOCUMENTATION_PROGRESS.md` | What is documented, stale or pending |

Read `repo-map.md` first for cross-application tasks, then look up the feature in the inventory. Do not load the whole folder into a session; see `.claude/skills/project-documentation/references/knowledge-retrieval.md`.
