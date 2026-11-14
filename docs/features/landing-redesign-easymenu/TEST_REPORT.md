# Test report — landing-redesign-easymenu

Date: 2026-10-31 · Source: xorder-cloud 775bf0f + uncommitted working tree (nothing committed) · Environment: macOS arm64, PHP SQLite `:memory:`, Node 24, Vite 8.

## Commands and real results
| Command | Result |
|---|---|
| `cd apps/xorder-cloud/apps/api && php artisan test --filter 'LandingContent\|LeadTest'` | passed: 21 tests, 149 assertions (includes 4 new tests) |
| `php artisan test` (full) | **did not run**: PHP 128 MB memory limit exhausted (environment, `routes/api.php`); `php -d memory_limit` is not passed to the child process |
| `php -d memory_limit=1G vendor/bin/phpunit` (full suite) | passed: 1157 tests, 5707 assertions, 49.8 s |
| `pnpm --filter @xorder/landing build` | first run failed (installed Rolldown binding was x64 on an arm64 Mac); after owner-approved `pnpm install --frozen-lockfile` (lockfile checksum unchanged) the build succeeded (`built in 587ms`). Bundle: main JS 521 kB (159 kB gzip), CSS 54 kB (10.7 kB gzip). Rolldown prints its >500 kB chunk warning; the pre-change size was **not measured**, so no before/after comparison |
| `@vue/compiler-sfc` parse + template compile of the 4 SFCs | 0 errors |

## Acceptance criteria
| AC | Proof | Status |
|---|---|---|
| AC-4 legacy row renders defaults | `test_legacy_rows_resolve_redesign_keys_from_defaults` + browser load against dev API | proven (API test run; page rendered) |
| AC-5 save/validate new keys | `test_redesign_keys_are_saved_and_not_stripped`, `test_payload_without_redesign_keys_still_saves`, `test_demo_tab_validation_rejects_bad_slug_and_too_many_tabs` | proven |
| AC-7 lead form unchanged | `LeadTest` passes; form markup untouched; **not submitted manually** | partly proven |
| AC-10 build | build output above | proven |
| AC-1 hero (1009 px, ar) | browser screenshot: headline, 2 CTAs, chips, venue pills, phone with floating chips; no horizontal scroll (`scrollWidth` = `clientWidth` = 1009) | seen manually |
| AC-2 mobile 375 px (en) | browser: no horizontal scroll (375/375); hero, phone and chips readable. A grid overflow in the phone's second column was fixed after this check and **not re-viewed** | partly seen |
| AC-3 language toggle | browser: toggle flips `dir` rtl→ltr and `lang` en; Arabic and English heroes seen | seen manually |
| AC-6 demo tabs | logic written, compiles; **not exercised** (dev content has no tabs; the tab bar needs ≥ 2 tabs saved) | **not verified** |
| AC-8 keyboard/contrast | arrow-key handler and `aria-*` written; **not tested**; contrast not measured | **not verified** |
| AC-9 reduced motion | `prefers-reduced-motion` rule added for chip animation; global rule already existed; **not tested** | **not verified** |
| AC-11 analytics events | handlers untouched; **network not checked** | **not verified** |

## Observations
- The demo QR image returns 404 in the dev database (demo restaurant missing); the QR card hides itself as designed (`.hp-qr` absent). Console shows one 404 for that request.
- Showcase text rendered unstyled until the shared heading classes were mirrored into the component (scoped CSS does not reach children); fixed and re-viewed.
- Dev and production databases were not touched; no migration exists or was run.

## Not tested / needs a person
Demo tabs with real data, keyboard-only pass, contrast measurement, dark mode (landing is light only, **UNVERIFIED**), real devices, Arabic mobile, production-like CDN/cache, Lighthouse.

## Review round (2026-10-31, read-only `code-reviewer` agent, then fixes)
Findings fixed: `hero.primary_link/secondary_link/login_link` now require `http(s)://`, `/` or `#` (blocks `javascript:`); `demo.restaurant_slug` and tab slugs require `[a-z0-9-]`; unused `showcase.mobile` content and four unused i18n keys removed; tab panel ARIA (`aria-controls`, `role=tabpanel`) added; tabs keyed by index; null-safe `why_us` items; inherited hard-coded `alt="QR"` made decorative (`alt=""`).
New test: `test_hero_links_and_demo_slugs_reject_unsafe_values`.
Re-run: `phpunit --filter 'LandingContent|LeadTest'` 22 passed / 161 assertions; full `php -d memory_limit=1G vendor/bin/phpunit` **1158 passed / 5719 assertions**; landing build ok; page reloads with all sections, no horizontal scroll at 1009 px. The only console errors are four 404s for the demo QR (`/api/public/restaurants/mahsoub-restaurnt/qr`; that restaurant is absent from the dev database).
Still unproven (unchanged): AC-6 demo tabs, AC-8 keyboard/contrast, AC-9, AC-11, AC-1 at 1440 px, AC-2 in Arabic and the 375 px state after the grid fix; tap targets not measured.
Left for the owner: Login link stays hidden until `hero.login_link` is set via API (no admin field yet); BR-3 claims (multi-branch chip, contactless copy) not checked against the feature inventory.
