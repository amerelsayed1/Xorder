# Xorder QA Audit — Claude Review Handoff

**Audit date:** 2026-08-22  
**Audit role:** QA  
**Repository:** Xorder QR menu and ordering platform  
**Purpose:** Independent review and validation by Claude before release

## 10×12 audit scope

This handoff uses a **10 product areas × 12 test cases** model: 120 explicit QA checks. Claude should mark every check as `PASS`, `FAIL`, `BLOCKED`, or `NOT APPLICABLE`, attach evidence, and open a finding for every failure.

### Result format

| Status | Meaning |
|---|---|
| PASS | Behavior was exercised and matched the expected result. |
| FAIL | Behavior was exercised and did not match the expected result. |
| BLOCKED | The check could not be executed; state the exact dependency. |
| NOT APPLICABLE | The check does not apply; explain why. |

For every check, record the environment, role, language, viewport, steps, actual result, evidence, and related issue ID.

## 10×12 QA matrix

### Area 1/10 — Public landing and acquisition

| ID | Test case | Expected result |
|---|---|---|
| 1.1 | Load the landing page directly | Page renders without console errors or broken critical assets. |
| 1.2 | Switch Arabic to English and back | All visible content, direction, and controls update consistently. |
| 1.3 | Submit an empty lead form | Required fields receive accessible, localized validation. |
| 1.4 | Submit malformed phone and email values | Invalid values are rejected without losing other input. |
| 1.5 | Submit a valid lead once | One lead is created and a clear success state appears. |
| 1.6 | Double-click lead submission | At most one lead is created and duplicate submission is prevented. |
| 1.7 | Exceed the lead rate limit | A helpful localized rate-limit message appears. |
| 1.8 | Open every primary CTA and navigation link | Every destination is correct and no link is dead. |
| 1.9 | Test SEO title, description, canonical, Open Graph, and structured data | Metadata is complete, valid, and matches CMS content. |
| 1.10 | Test 390 px, 768 px, and 1440 px widths | No horizontal overflow, clipped CTA, overlap, or unreadable text occurs. |
| 1.11 | Disable JavaScript and block third-party fonts/analytics | Essential identity and fallback content remain safe; optional failures do not break the page. |
| 1.12 | Refresh and deep-link with query strings and campaign parameters | The page loads correctly, preserves approved attribution, and does not expose sensitive values. |

### Area 2/10 — Public menu discovery

| ID | Test case | Expected result |
|---|---|---|
| 2.1 | Open a valid restaurant menu | Correct branding, branches, categories, items, prices, and currency load. |
| 2.2 | Open an unknown, archived, suspended, or hidden restaurant | A deliberate unavailable/not-found state appears without data leakage. |
| 2.3 | Switch language | Names, descriptions, controls, direction, and currency formatting update. |
| 2.4 | Search by Arabic and English item name | Matching items appear and clearing search restores the menu. |
| 2.5 | Navigate category tabs and scroll spy | The selected category remains synchronized with visible content. |
| 2.6 | Exercise photo, text-grid, and text-list layouts | All layouts remain functional and accessible at supported breakpoints. |
| 2.7 | Load missing, slow, and failed images | Stable fallbacks appear without layout shift or broken controls. |
| 2.8 | Simulate slow API, HTTP 404, HTTP 500, and offline mode | Loading, unavailable, error, and retry states are accurate. |
| 2.9 | Open restaurant information, branches, social links, and maps | Data and external destinations belong to the current tenant. |
| 2.10 | Navigate using keyboard and screen-reader names | All actions are reachable, named, and visibly focused. |
| 2.11 | Load a catalog with zero, one, and hundreds of categories/items | Empty and large states remain understandable, responsive, and stable. |
| 2.12 | Refresh or share URLs containing layout, restaurant, and table parameters | Supported context is restored and untrusted parameters cannot alter another tenant's data. |

### Area 3/10 — Cart, items, variants, and combos

| ID | Test case | Expected result |
|---|---|---|
| 3.1 | Quick-add and quick-remove a simple item | Quantity and total update exactly once per action. |
| 3.2 | Open an item with required single-choice options | A valid default or explicit required selection is enforced. |
| 3.3 | Exercise optional and multi-select option groups | Minimum/maximum limits and pricing are correct. |
| 3.4 | Add the same item with different options and notes | Distinct cart lines are preserved with correct totals. |
| 3.5 | Add and configure a combo | Required combo groups, membership, quantity, and price are correct. |
| 3.6 | Increase and decrease quantities at limits | Zero removes the line and maximum limits cannot be exceeded. |
| 3.7 | Refresh or reopen the menu | Cart persistence follows the documented behavior for that restaurant. |
| 3.8 | Change language after adding items | Cart identity and prices remain stable while labels relocalize safely. |
| 3.9 | Make an item unavailable after it enters the cart | Checkout revalidates and explains the stale item without silent loss. |
| 3.10 | Compare displayed subtotal, line totals, submitted total, and server total | All values match authoritative server-side pricing. |
| 3.11 | Test decimal prices, zero-price options, large quantities, and currency rounding | Every displayed and persisted amount follows the currency's rounding rules. |
| 3.12 | Corrupt or downgrade persisted cart data in browser storage | Invalid lines are discarded or repaired safely without breaking the menu. |

### Area 4/10 — Checkout and order integrity

| ID | Test case | Expected result |
|---|---|---|
| 4.1 | Submit a valid system-only order | Success appears only after HTTP 201 and the manager receives one order. |
| 4.2 | Fail system checkout with HTTP 422, 403, 500, timeout, and offline mode | Cart/input remain intact and a retryable accurate error appears. |
| 4.3 | Submit a WhatsApp-only order | Customer capture is best-effort and the handoff message is correct. |
| 4.4 | Submit an order in both mode | WhatsApp opens and the durable order result is communicated accurately. |
| 4.5 | Double-click or rapidly repeat checkout | At most one durable order is created for one submission intent. |
| 4.6 | Tamper with item ID, name, price, quantity, options, and total | Server rejects invalid identity/options and calculates trusted totals. |
| 4.7 | Submit cross-tenant or unavailable menu entity IDs | Request is rejected without disclosing foreign tenant data. |
| 4.8 | Test pickup, delivery, and dine-in eligibility | Only restaurant-enabled and context-valid order types are accepted. |
| 4.9 | Validate customer name, phone, email, address, and note boundaries | Validation is localized and preserves valid data. |
| 4.10 | Return after an order is completed | Status lookup and review prompt occur only for the intended order. |
| 4.11 | Retry after an ambiguous timeout where the server may have committed | Idempotency prevents duplicate orders and the client can resolve the original result. |
| 4.12 | Modify restaurant menu/plan/order mode during an open checkout | The server applies current authoritative rules and the client explains any conflict. |

### Area 5/10 — Table QR and dine-in journey

| ID | Test case | Expected result |
|---|---|---|
| 5.1 | Scan a valid active table QR | Correct restaurant, branch, area, and table context appear. |
| 5.2 | Scan invalid, regenerated, disabled-table, or disabled-area tokens | Access is rejected with an accurate recoverable state. |
| 5.3 | Create and reuse a menu session | Session binds only to the intended tenant/table and respects expiry. |
| 5.4 | Test required branch Wi-Fi from matching and nonmatching IPs | Ordering is permitted or blocked according to policy. |
| 5.5 | Submit multiple rounds from one table | One open order receives correctly sequenced, nonduplicated rounds. |
| 5.6 | Submit concurrently from two devices at one table | Locks prevent duplicate open orders and round collisions. |
| 5.7 | Request, inspect, and cancel a bill | Status and manager notifications remain synchronized. |
| 5.8 | Finish a visit while requests/orders remain active | The system enforces and explains the intended lifecycle rule. |
| 5.9 | Regenerate a table QR | Old token behavior matches policy and the new token works immediately. |
| 5.10 | Attempt cross-tenant table/session/bill tokens | Every request resolves safely without foreign data exposure. |
| 5.11 | Leave a table session idle past each expiry boundary | Expired state is enforced consistently by browse, order, bill, and review endpoints. |
| 5.12 | Move between background/foreground and reconnect during a visit | Session, table, active order, and request state resynchronize without duplication. |

### Area 6/10 — Restaurant manager operations

| ID | Test case | Expected result |
|---|---|---|
| 6.1 | Log in, log out, remember session, and use expired/invalid token | Authentication states and redirects are accurate and loop-free. |
| 6.2 | View dashboard stats and insights | Metrics match underlying orders, customers, reviews, and date filters. |
| 6.3 | Create, edit, reorder, toggle, and delete categories/items | Changes are tenant-scoped and reflected on the public menu. |
| 6.4 | Manage branches, areas, tables, and QR downloads | Limits, validation, exports, and public context remain consistent. |
| 6.5 | Process orders through every allowed status transition | Invalid transitions are blocked and counts/notifications update once. |
| 6.6 | Use the live board during concurrent updates | Orders, bill requests, occupancy, and visits do not become stale or duplicated. |
| 6.7 | Import and export menu data | Round-trip preserves bilingual data, variants, prices, and validation errors. |
| 6.8 | Manage customers and reviews | PII remains scoped; notes, status, summaries, and detail views agree. |
| 6.9 | Exercise every feature on enabled and disabled plans | Navigation and API enforcement match plan entitlements. |
| 6.10 | Exercise active, expired, suspended, and archived states | Read/write behavior matches subscription and status policy. |
| 6.11 | Use two manager tabs/devices to edit the same entity | Stale updates are detected or resolved without silently overwriting newer work. |
| 6.12 | Test browser refresh and direct deep links for every manager route | Authorized pages recover state; unauthorized/unknown routes render safe outcomes. |

### Area 7/10 — Platform manager and administration

| ID | Test case | Expected result |
|---|---|---|
| 7.1 | Log in as SUPER_ADMIN, ADMIN, MODERATOR, SALES, and SUPPORT | Each role sees and accesses exactly its allowed capabilities. |
| 7.2 | Provision a restaurant and first admin | Tenant, admin, defaults, plan, and credential delivery are correct and atomic. |
| 7.3 | Edit restaurant identity, domain slug, status, and subscription | Changes propagate safely and warnings cover broken links/QR impact. |
| 7.4 | Reset restaurant-admin and platform-user passwords | Old tokens are invalidated and generated credentials are not leaked. |
| 7.5 | Create, edit, disable, and delete platform staff | Self-lockout and last-super-admin scenarios are prevented. |
| 7.6 | Create and change subscription plans | Feature and limit reconciliation occurs immediately and predictably. |
| 7.7 | Manage leads, filters, statuses, and CSV export | Counts and exports match filters; spreadsheet injection is neutralized. |
| 7.8 | Edit every landing CMS section | Validation, sanitization, localization, defaults, and public rendering agree. |
| 7.9 | Review audit-log filters and sensitive actions | Actor, tenant, action, before/after data, and timestamps are correct without secrets. |
| 7.10 | Attempt direct URLs and APIs without capability | UI redirects safely and API remains authoritative with 403 responses. |
| 7.11 | Perform destructive operations with dependencies and concurrent activity | Confirmation, constraints, audit records, and recovery behavior prevent accidental loss. |
| 7.12 | Paginate, filter, sort, and export large administration datasets | Results remain complete, stable, performant, and consistent across UI/export. |

### Area 8/10 — Security, privacy, and abuse resistance

| ID | Test case | Expected result |
|---|---|---|
| 8.1 | Attempt IDOR across every tenant-owned resource | Foreign IDs return safe 404/403 responses with no metadata leak. |
| 8.2 | Inject script/HTML into all public and manager text fields | Stored/reflected XSS is prevented in UI, exports, notifications, and metadata. |
| 8.3 | Test JWT expiry, revocation, password change, and logout | Tokens become unusable according to policy on every device. |
| 8.4 | Inspect authentication and sensitive responses | Tokens, passwords, PII, and internal fields are minimized and never logged. |
| 8.5 | Exercise login, signup, leads, orders, reviews, sessions, and resets at limits | Rate limits resist abuse without blocking normal shared-Wi-Fi traffic. |
| 8.6 | Upload malformed, oversized, polyglot, metadata-rich, and unsupported images | Unsafe files are rejected; accepted images are re-encoded safely. |
| 8.7 | Test CORS, security headers, content sniffing, framing, and referrer policy | Production responses enforce the documented security posture. |
| 8.8 | Test CSV/XLSX export values beginning with formula characters | Exports cannot execute spreadsheet formulas. |
| 8.9 | Test map-link resolution against private/local network targets | SSRF protections block internal addressing and unsafe redirects. |
| 8.10 | Review dependencies, secrets, environment examples, and deployment SSH trust | No vulnerable dependency, committed secret, or unpinned production host remains. |
| 8.11 | Test mass assignment, duplicate parameters, malformed JSON, and oversized payloads | Requests fail safely without unintended field changes or resource exhaustion. |
| 8.12 | Verify deletion, retention, export, and redaction of customer data | PII lifecycle matches documented privacy policy and tenant authorization. |

### Area 9/10 — Performance, accessibility, and compatibility

| ID | Test case | Expected result |
|---|---|---|
| 9.1 | Measure landing cold load on throttled mobile | LCP, CLS, INP, and transfer size meet an agreed budget. |
| 9.2 | Measure menu cold/warm load with a large catalog | Menu becomes usable promptly without long tasks or excessive memory. |
| 9.3 | Measure manager dashboard and first chart load | Route and chart chunks load lazily within the agreed budget. |
| 9.4 | Navigate all primary journeys by keyboard | Focus order, visibility, traps, Escape, and restoration are correct. |
| 9.5 | Audit labels, roles, headings, landmarks, announcements, and errors | Screen-reader semantics meet WCAG 2.2 AA expectations. |
| 9.6 | Test 200% zoom and large text | Content reflows without clipping, overlap, or lost actions. |
| 9.7 | Test reduced motion, high contrast, and light/dark OS preferences | Content remains understandable and motion preferences are respected. |
| 9.8 | Test current Chrome, Safari, Firefox, and Edge | Core flows behave consistently on supported browsers. |
| 9.9 | Test iOS Safari and Android Chrome | Touch targets, fixed drawers, keyboard, scrolling, WhatsApp, and QR flows work. |
| 9.10 | Test slow, intermittent, and recovered connectivity | Retry and stale-state behavior avoid data loss or duplicate actions. |
| 9.11 | Measure API query counts and response times with production-sized data | No N+1 query or unbounded payload breaks the agreed latency budget. |
| 9.12 | Test print, QR download, CSV/XLSX download, and browser download restrictions | Generated artifacts are complete, named correctly, and usable on supported devices. |

### Area 10/10 — Engineering, data, release, and observability

| ID | Test case | Expected result |
|---|---|---|
| 10.1 | Run frontend build, real lint, type checks, and automated tests | Every configured quality gate executes meaningful work and passes. |
| 10.2 | Run PHP syntax, Pint, feature tests, and dependency audits | All backend quality and security gates pass. |
| 10.3 | Run tests with PostgreSQL in addition to SQLite | Queries, locks, constraints, JSON, dates, and migrations behave in production parity. |
| 10.4 | Migrate a production-like database forward | Migrations are safe, timed, resumable where needed, and preserve data. |
| 10.5 | Exercise rollback or forward-fix procedure | The team can recover without undocumented destructive operations. |
| 10.6 | Deploy through CI with branch and environment protections | Only reviewed artifacts reach the pinned production host. |
| 10.7 | Perform post-deployment smoke tests | Landing, menu, login, order, manager board, uploads, and notifications pass. |
| 10.8 | Trigger representative frontend, API, queue, notification, and deployment failures | Logs/alerts contain actionable context without secrets or PII. |
| 10.9 | Verify backup creation and restore | A documented restore meets agreed RPO/RTO and validates recovered data. |
| 10.10 | Compare documentation and environment examples to implementation | Auth, ports, commands, domains, features, and release procedures are current. |
| 10.11 | Verify telemetry consent/configuration and analytics event quality | Events are accurate, deduplicated, environment-scoped, and contain no prohibited PII. |
| 10.12 | Run a release go/no-go review using all 120 results | Every blocker has an owner; waivers are explicit; final evidence and sign-off are recorded. |

## Review instructions for Claude

Please verify every finding below against the current source. For each finding:

1. Confirm or reject it with file and line references.
2. Check whether existing tests already cover the reported behavior.
3. Identify related edge cases or regressions that are not listed.
4. Recommend the smallest safe fix.
5. Do not modify source code unless explicitly requested.

Pay special attention to the two release blockers in the next section.

## Release recommendation

**Current recommendation: DO NOT RELEASE system ordering until QA-001 and QA-002 are resolved.**

The backend test suite and production builds are healthy, but the current system-order checkout can report false success, and durable order prices are accepted from the client.

## Release blockers

### QA-001 — System-only checkout reports success when order creation fails

**Priority:** P0 / release blocker  
**Perspectives affected:** Client, restaurant manager, support

#### Evidence

File: `apps/menu/src/App.vue`, approximately lines 283–352.

`submitOrder()` starts `postOrder()` without awaiting it. Its rejection is swallowed, after which the function immediately:

- closes the cart;
- clears all cart lines;
- resets the submitting state; and
- opens the success dialog.

This behavior is unsafe in `system` ordering mode because there is no WhatsApp fallback.

#### Expected behavior

- In `system` mode, success must appear only after the API returns HTTP 201.
- On failure, the cart must remain intact.
- The client must receive a clear, retryable error.
- Repeated clicks must not create duplicate orders.
- In `both` mode, WhatsApp may still open immediately, but failure to record the dashboard copy should be communicated accurately.

#### Required QA scenarios

- Successful HTTP 201 response.
- Validation failure (HTTP 422).
- Subscription or feature rejection (HTTP 403/422 as applicable).
- Server error (HTTP 500).
- Offline/network timeout.
- Slow response followed by a second click.
- WhatsApp-only, system-only, and both ordering modes.
- Cart contents after every failure case.

### QA-002 — System-order item identity and price are client-controlled

**Priority:** P0 / release blocker  
**Perspectives affected:** Restaurant manager, reporting, kitchen operations

#### Evidence

Files:

- `apps/menu/src/App.vue`, approximately lines 302–318.
- `apps/api/app/Http/Requests/Public/StoreOrderRequest.php`, approximately lines 36–62.
- `apps/api/app/Http/Controllers/Public/PublicOrderController.php`, approximately lines 63–80.

The client sends item names, option labels, quantities, and `line_total`. The API validates their shape and sums the submitted line totals, but it does not resolve menu item/option IDs or calculate prices from tenant-owned menu data.

#### Risk

A modified request can submit arbitrary names and prices. These values can enter the kitchen queue, sales totals, insights, and product reports.

#### Expected behavior

- The client sends menu item/combo IDs and selected option IDs.
- The API resolves all entities within the target restaurant.
- The API rejects unavailable, disabled, deleted, or cross-tenant entities.
- Required options and selection limits are validated server-side.
- Names, option labels, unit prices, and totals are calculated server-side.
- The server records a deliberate snapshot after validation so historical orders remain stable after menu edits.

#### Required QA scenarios

- Changed `line_total` and `total` values.
- Changed item name with a valid ID.
- Nonexistent item ID.
- Item belonging to another restaurant.
- Disabled/unavailable item.
- Disabled option or option from another group.
- Missing required option.
- Too many options selected.
- Price-changing variant and quantity calculations.
- Combo pricing and combo membership.
- Menu item changed between cart creation and checkout.

## High-priority quality findings

### QA-003 — JavaScript lint command performs no work

**Priority:** P1

Running `pnpm lint` succeeds but Turbo reports zero executed tasks. The root script and Turbo task exist, while frontend/package manifests do not define lint scripts.

Evidence:

- `package.json`, script `lint`.
- `turbo.json`, task `lint`.
- `apps/*/package.json` and `packages/*/package.json` contain no lint scripts.

Expected resolution:

- Configure ESLint for Vue and JavaScript workspaces.
- Add real package-level lint tasks.
- Make CI fail on lint errors or on an unexpectedly empty lint run.

### QA-004 — No frontend automated test layer

**Priority:** P1

The Laravel feature suite is extensive, but no JavaScript unit, component, accessibility, or end-to-end tests were found.

Minimum recommended coverage:

- Menu load and unavailable/error states.
- Add/remove cart items and option validation.
- All three checkout modes.
- Order failure recovery from QA-001.
- Login and role-based navigation.
- Restaurant manager order status transitions.
- Arabic/English switching.
- Mobile viewport smoke test.
- Keyboard operation and modal focus management.

### QA-005 — Deployment host key is not pinned

**Priority:** P1 security/operations

`.github/workflows/deploy.yml` builds `known_hosts` dynamically with `ssh-keyscan`. This trusts whichever key responds during deployment.

Expected resolution: store the verified production host key in a protected `SSH_KNOWN_HOSTS` secret and use strict host-key verification.

## Medium-priority findings

### QA-006 — Every push to main can deploy to production

**Priority:** P2 operations

The deployment workflow triggers on every push to `main`. Confirm that the GitHub `production` environment has required reviewers, protected branches, and appropriate secret restrictions. If it does not, a merged change proceeds directly to production after CI.

### QA-007 — Authentication documentation is stale

**Priority:** P2 documentation/security

`README.md` describes Sanctum cookie authentication, while `packages/api-client/src/api.js` describes and implements JWT bearer authentication stored in `localStorage`.

Expected resolution:

- Document the deployed authentication design accurately.
- Update local-development instructions that mention Sanctum stateful domains.
- Document token expiration, logout, password-change invalidation, and XSS implications.

### QA-008 — Large chart dependency

**Priority:** P2 performance

The production build reports an ApexCharts chunk of approximately 777 KB minified / 217 KB gzip. The current uncommitted `ApexChart.vue` change dynamically imports it, which helps initial page rendering, but first chart use remains expensive.

Validate on throttled mobile and desktop networks and establish an acceptable performance budget.

### QA-009 — Operational errors are frequently generic or blocking

**Priority:** P2 UX/supportability

Several manager views use generic alert messages for failed updates/downloads. Errors should tell the manager what failed, whether their work was retained, and what action is safe next.

Review at least:

- orders and live board;
- category/item reorder;
- imports and exports;
- QR downloads;
- restaurant archive/delete;
- review status and notes.

## Verified checks

The following checks passed during the audit:

| Check | Result |
|---|---|
| Laravel feature suite | 471 passed |
| Laravel assertions | 1,633 passed |
| Frontend production builds | 3 passed |
| PHP syntax validation | Passed |
| Laravel Pint style check | Passed |
| `pnpm audit --prod` | No known vulnerabilities |
| `composer audit --locked` | No known advisories |
| `git diff --check` | Passed |
| Login at 390×844 | No horizontal overflow |
| Login at 1440×900 | No horizontal overflow |

`pnpm lint` returned exit code 0 but executed zero tasks, so it is not considered a meaningful pass.

## Test environment limitations

- The local database did not contain the documented `xorderrest` demo restaurant, so a complete rendered menu-to-order journey could not be executed with seeded data.
- The landing-page port was already occupied by a process that served the dashboard application, so the landing page was not treated as a valid visual-test result.
- No production environment, real WhatsApp handoff, Firebase project, push-notification delivery, or real payment flow was exercised.

These limitations do not invalidate QA-001 or QA-002; both are directly visible in the request lifecycle and source.

## Regression checklist after fixes

### Client

- Menu loads in Arabic and English.
- Category navigation, search, item options, combos, and cart totals work.
- Cart persists through refresh where intended.
- System checkout never shows success before server confirmation.
- Failed checkout retains all cart and customer inputs.
- WhatsApp link contains the correct localized items, options, totals, and order code where applicable.
- Mobile layouts have no clipped actions or horizontal scrolling.

### Restaurant manager

- New orders appear exactly once in live board and order list.
- Status transitions update counts, notifications, tables, and reports consistently.
- Table rounds append correctly under concurrency.
- Expired subscriptions preserve authorized read/processing behavior.
- Tenant isolation remains enforced for every entity ID in order payloads.

### Platform manager

- Roles expose only their documented sections and API capabilities.
- Restaurant provisioning and password-reset workflows do not leak generated credentials.
- Subscription and plan changes immediately affect ordering modes and features.
- Audit logs capture sensitive management actions without storing secrets.
- Production deployment requires the intended human and branch protections.

### Developer/release

- Backend feature suite passes.
- Frontend unit/component/E2E tests pass.
- JavaScript lint executes real tasks and passes.
- PHP syntax and Pint pass.
- Production builds pass without unexpected bundle regressions.
- Dependency audits pass.
- Database migrations are tested against PostgreSQL, not only SQLite.
- Rollback and post-deployment smoke procedures are documented.

## Claude response template

Please return the review in this structure:

```text
Overall verdict: CONFIRMED / PARTIALLY CONFIRMED / REJECTED
Release recommendation: GO / NO-GO

QA-001: CONFIRMED / REJECTED
Evidence:
Missing edge cases:
Recommended fix:

QA-002: CONFIRMED / REJECTED
Evidence:
Missing edge cases:
Recommended fix:

QA-003 through QA-009:
- Finding status and concise notes for each.

Additional findings:
- Priority, evidence, impact, and recommendation.
```
