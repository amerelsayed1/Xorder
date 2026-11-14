# Technical design: <feature title>

Verified against: <date> · cloud `<HEAD>` · POS `<HEAD>`
Headings keep the order of `docs/templates/TECHNICAL.md`; (+) sections are added by `/project-documentation`. Describe as-built design; cite `path:line`.

## Architecture and modules
(Components and layers involved, with a short diagram or table if it helps.)

## Cloud implementation (+)
| Layer | Files and symbols | Responsibility |
| --- | --- | --- |
| Routes and middleware | | |
| Controllers | | |
| Requests (validation) | | |
| Services | | |
| Models and scopes | | |
| Resources | | |
| Enums / capabilities | | |
| Scheduled commands, notifications, push | | |

## Web frontend implementation (+)
| App | Pages and components | Stores / composables | API calls | i18n / RTL notes |
| --- | --- | --- | --- | --- |

## Desktop POS implementation (+)
| Layer | Files and symbols | Responsibility |
| --- | --- | --- |
| Screens and widgets | | |
| State (Riverpod providers) | | |
| Domain services and models | | |
| Repositories (interface and PostgreSQL implementation) | | |
| Cloud client / sync / outbox | | |
| Printing, licensing, installer, backup (if applicable) | | |

## Source references
(Every file the feature depends on, `path:line` and symbol. Mirrors the evidence index in `FEATURE_INVENTORY.md`.)

## State and data flow
(Where state lives on each side, how it moves, which side is authoritative for prices, taxes, totals, permissions and order transitions.)

## Local persistence and caching (+)
(POS local PostgreSQL tables and caches, config stores, parked or queued data, cloud-side caching. "Not applicable" if none.)

## Offline operation and synchronization (+)
(What works when the cloud or the branch server is unreachable, what is queued, idempotency keys, retry and conflict behavior. State only what the code does.)

## Dependencies
(Libraries, services, other features, configuration keys by name only — never values.)

## Failure handling and observability
(Error types and mapping, logging and audit trail, retries, user-visible messages, monitoring hooks.)

## Platform-specific behavior (+)
(Windows vs macOS code paths, browser or locale differences, hardware drivers. "None found" with the search used if none.)

## Compatibility and rollout
(Backward compatibility, deployment independence of cloud and POS, migration order, feature flags / plan entitlements.)
