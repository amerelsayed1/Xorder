# Database impact: <feature title>

Verified against: <date> · cloud `<HEAD>` · POS `<HEAD>`
Headings keep the order of `docs/templates/DATABASE.md`; (+) sections are added by `/project-documentation`. Write from migrations, not from models. For as-built documentation "Proposed changes" is "None".

## Tables and constraints
### Cloud (PostgreSQL in production, SQLite in tests)
| Table | Created in (migration) | Altered in | Tenant column | Notes |
| --- | --- | --- | --- | --- |

| Table.column | Type | Null | Default | Key / FK / unique / index | Meaning and allowed values |
| --- | --- | --- | --- | --- | --- |

### Desktop POS (local PostgreSQL on the branch server, `lib/data/postgres/migrations.dart`)
| Table | Migration step | Tenant / branch column | Notes |
| --- | --- | --- | --- |

| Table.column | Type | Null | Default | Key / FK / unique / index | Meaning |
| --- | --- | --- | --- | --- | --- |

## Relationships (+)
(Entity relationships on each side as a list or small diagram; include polymorphic or soft-delete conventions. Cite models and migrations.)

## Shared entities across applications (+)
| Entity | Cloud table | POS table | Identifier mapping | Source of truth |
| --- | --- | --- | --- | --- |

## Proposed changes
None (as-built documentation). (List here only if the feature doc describes proposed work, clearly marked.)

## Transactions and concurrency
(Where transactions wrap writes, row locks, unique constraints that enforce invariants, sequences such as invoice numbers.)

## Indexes and query performance
(Existing indexes, queries that rely on them, unbounded scans, N+1 risks found in code.)

## PostgreSQL vs SQLite differences (+)
(Raw SQL, functions, constraints or behavior that tests on SQLite cannot prove. "None found" with the search used.)

## Migration and rollback plan
(Migrations that exist for this feature, their order and whether they are additive; no destructive change is proposed by documentation.)

## Backup/data access constraints
(Retention jobs such as prune commands, data classes holding PII or payment data, backup features of the POS. Do not read or reference backup contents.)
