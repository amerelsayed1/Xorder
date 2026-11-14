# Landing page redesign in the style of easy-menu.org — landing-redesign-easymenu

Status: implemented, not yet reviewed or shipped · 2026-10-31 · Source: user request "I like landing page here https://easy-menu.org/ — Think to make our like this" · Verified against: xorder-cloud 775bf0f (working tree has unrelated uncommitted changes in `apps/api` and `apps/web`, none in `apps/landing`), xorder-pos c67c754 (not affected)

## 1. Summary
Rework the public marketing page (`apps/xorder-cloud/apps/landing`, served at xorder.io) so it looks and flows like easy-menu.org: a warm hero with a phone mockup of a real menu and floating feature chips, a "who is it for" grid, a tabbed live demo, a clear feature grid, a 4-step flow, dashboard and WhatsApp-order showcases, a "why us vs printed menus" block and a strong final call to action. Xorder keeps its own brand, bilingual AR/EN with RTL, the super-admin-managed content API and the lead form.

## 2. Why
easy-menu.org is the reference the owner likes: a visitor understands the product in one screen (phone + chips + QR), sees real menus before signing up, and meets a single obvious next step. Our page today explains well in text but shows an abstract dashboard drawing instead of the product a diner actually uses, so the first impression is weaker for café and restaurant owners who are our buyers.

## 3. Goal and success
- A first-time visitor sees, above the fold, what Xorder is, a phone showing a real menu, the QR, the trust chips and the primary CTA.
- Lead-form submissions and demo-menu opens (existing analytics events) do not drop after the change. Baseline is **UNVERIFIED** (no analytics read in this task); capture it before release.
- Lighthouse accessibility stays ≥ the current score; the existing WCAG AA colour work (`--lp-amber`, `--lp-muted`) is kept.

## 4. Users, roles and permissions
Anonymous visitors only. Super Admin edits content through the existing `PUT /api/admin/landing-content` (`apps/api/routes/api.php:238`); no new permission identifiers. Not applicable: tenant roles.

## 5. Today (verified in source)
| Area | Current | Evidence |
|---|---|---|
| Stack | One Vue SFC, 941 lines, plus `app.css`; shared tokens from `packages/ui/src/theme.css`; Tajawal self-hosted | `apps/landing/src/LandingView.vue`, `src/app.css:5-11` |
| Content | Fetched from `GET /api/public/landing-content` (public), edited by `GET/PUT /api/admin/landing-content`; defaults in the `LandingContent` model with keys `hero, proof, features, demo, steps, pricing, industries, faq, whatsapp, seo, contact, footer` | `src/lib/content.js:6`, `routes/api.php:237-238,857`, `app/Models/LandingContent.php:83-407` |
| Sections | header, hero, features, how+demo, packages, industries, faq, lead form, footer | `LandingView.vue:261-601` |
| Hero visual | Decorative SVG "dashboard" with emoji cards, not a phone and not a real menu | `LandingView.vue:322-389` |
| Nav | Anchor links, CTA button, language toggle, mobile drawer; **no Login link** | `LandingView.vue:261-304` |
| Colours | Already warm cream + amber (`--accent #f89a06`, AA-safe `--lp-amber #9c5c02`), close to easy-menu's palette | `LandingView.vue:633-635` |
| Floating WhatsApp | Supported by content flags `floating_enabled`, `hero_enabled`; number empty by default | `LandingContent.php:372-381` |
| Live demo | Single QR + button to one demo menu, inside the "how" section | `LandingView.vue:435-446` |
| Tests | `LandingContentTest.php`, `LeadTest.php` (API only). No JS tests exist for the SPA (workspace rule: do not add tooling without approval) | `apps/api/tests/Feature/` |
| Docs | `landing-content` row in the feature inventory is `pending`, **UNVERIFIED**; no `docs/features/landing*` folder existed | `docs/FEATURE_INVENTORY.md:97` |

## 6. Section-by-section comparison and decision
| easy-menu.org section | Ours today | Decision |
|---|---|---|
| Sticky nav + language switch + Login + "start free" | Nav + CTA + language | **Adopt** Login link (to the dashboard sign-in) and keep our anchors; blog link only if a blog exists (it does not: skip) |
| Hero: badge, big headline, 2 CTAs, trust chips | Badge, headline, 2 CTAs, stats | **Adopt** trust chips row under the CTAs (from `proof`/new chip list) |
| Hero visual: phone with real menu, floating chips, QR card | Abstract SVG dashboard | **Adopt**: phone mockup of the real Xorder menu look, floating chips (instant update, multi-language, WhatsApp orders, multi-branch), QR card |
| Business-type pills under hero | none | **Adopt** as a small pill row (café, restaurant, food truck, cloud kitchen) |
| "Suitable for every business" grid | `industries` chips | **Adopt** as a card grid with icon/photo, one line each; Xorder wording, food-service only |
| Clients logos | none | **Conditional**: only with real, permitted client logos; otherwise omit (see open question 2) |
| Live demo with tabs per business type + QR | One demo QR | **Adopt** tabs (café / restaurant / …) each opening a real demo menu; extend `demo` content |
| Features grid (9 cards) | Feature grid from `features.items` | **Keep and restyle**; add POS, tables and kitchen where they are true today (verify each against inventory) |
| 4 steps | `steps` | **Keep** (restyle) |
| Mobile experience carousel | none | **Adopt** a short phone-screens showcase using real menu screenshots |
| Dashboard showcase | SVG only | **Adopt** a real dashboard screenshot with callouts |
| WhatsApp order mockup | none | **Adopt** a chat-bubble mockup of an incoming order |
| Pricing = "free trial" CTA only | Three plan cards (`pricing`) | **Keep ours**: owner sells packages; do not remove prices |
| "Why us vs printed menus" | none | **Adopt** as a short benefits block (print cost, contactless, no paper) |
| FAQ | present | **Keep** (easy-menu has none) |
| Lead form | present | **Keep unchanged** |
| Final CTA band | CTA only inside sections | **Adopt** closing CTA band before the footer |
| Floating WhatsApp button | content-flag driven | **Keep** |

Xorder is also a POS and ordering platform, not only a QR menu; the page keeps that message, which easy-menu does not carry.

## 7. Scope
In: layout, visuals, copy slots and styling of `apps/landing`; new content keys needed for the added sections, with defaults in `LandingContent.php` and validation in `UpdateLandingContentRequest.php`; en and ar strings.
Out: the lead form, its API and fields; pricing logic; `apps/web`, `apps/menu`, POS; analytics event names; SEO meta values (reviewed, not rewritten); a blog; auth/login behaviour; copying easy-menu text, images, logo or brand assets.

## 8. Behavior and business rules
- BR-1: Every visible string is editable bilingual content or an i18n key, in both `en` and `ar`; RTL uses logical properties.
- BR-2: The page renders with the defaults when the API returns nothing for a new section key (older stored content lacks the new keys).
- BR-3: No claim on the page that the product cannot do today (verify each feature against the inventory before it is listed).
- BR-4: No invented customers, logos, testimonials or numbers. Demo menus shown are Xorder's own.
- BR-5: Colours come from theme CSS variables; the AA contrast values stay.
- BR-6: easy-menu.org's copy, imagery and brand are not reused; only the structure and visual approach.

## 9. Acceptance criteria
- AC-1 Given the home page at 1440 px, when it loads, then the hero shows headline, two CTAs, a chip row, a phone mockup with floating chips and a QR card, with no horizontal scroll. *(manual visual + browser check)*
- AC-2 Given a 375 px viewport in ar and in en, then every section is readable, tap targets ≥ 44 px, and no content overflows. *(manual, both locales)*
- AC-3 Given the language toggle, when switched, then direction flips (rtl/ltr) and no hard-coded left/right spacing breaks. *(manual)*
- AC-4 Given stored content from before this change (missing the new keys), when the page loads, then it renders with defaults and no console error. *(API feature test on the public endpoint + browser)*
- AC-5 Given Super Admin saves new section content, when validation fails or passes, then `PUT /api/admin/landing-content` rejects malformed payloads and the public endpoint returns the saved data. *(extend `LandingContentTest`)*
- AC-6 Given the demo tabs, when a tab is chosen, then the QR and the "open live menu" link switch to that demo menu, and a missing demo URL hides that tab. *(manual)*
- AC-7 Given the lead form, when submitted validly and invalidly, then behaviour and fields are unchanged. *(existing `LeadTest` passes; manual submit)*
- AC-8 Given keyboard-only use, then nav, tabs, drawer and form are reachable with visible focus; text contrast ≥ 4.5:1. *(manual + contrast check)*
- AC-9 Given reduced-motion preference, then decorative animation is disabled. *(manual)*
- AC-10 Given `pnpm --filter @xorder/landing build`, then it succeeds and the bundle stays within the current size by more than a stated budget (to set in the plan). *(build output)*
- AC-11 Given analytics, then existing events (`onRequestDemo`, `onViewDemo`, nav click) still fire. *(manual, network tab)*

## 10. Edge cases and failure modes
API down or slow (current load/error state kept); very long Arabic titles; Arabic-Indic vs Latin digits in prices as the content already stores them; empty `industries`, `faq` or demo tabs (section hides); missing images (fallback emoji or icon); WhatsApp number empty (button hidden, as today); slow mobile networks (lazy images, no heavy video); `prefers-reduced-motion`. Tenant isolation, offline POS, idempotency and plan limits: not applicable (public, read-only page).

## 11. Impact
- Repos: `xorder-cloud` only (`apps/landing`, plus `apps/api` for new content keys and tests). POS unaffected.
- API/contract: additive keys on `GET /api/public/landing-content`; existing keys unchanged. The POS does not consume it (no client found, **UNVERIFIED**).
- Data/migrations: expected none if content stays in the existing JSON field; **UNVERIFIED** until the plan reads the model's storage.
- Deploy: a push to `main` goes live on xorder.io and runs migrations. Needs `/release-check` and the owner's push; build and review locally first.
- Docs: add the feature to the inventory and run `/project-documentation update` after approval.

## 12. Dependencies, known gaps, risks
- Needs real assets: phone/dashboard screenshots, demo menus per venue type, client logos (if any). Without them the plan uses neutral illustrated placeholders.
- Domain lens (cafés, restaurants, food trucks, cloud kitchens): the page speaks to all four; avoid claims about tables, delivery addresses or KDS that are known gaps (`docs/domain/FOOD_SERVICE_DOMAIN.md` §3, §7); not re-read in this pass, **UNVERIFIED** against the latest version.
- Risk: pixel-level imitation of a competitor's design; mitigated by BR-6.
- Risk: a large visual rewrite of a 941-line SFC; split into components during implementation.
- No frontend test tooling exists, so most ACs are manual or build-level.

## 13. Decisions and open questions
Decided (2026-10-31): keep our brand, locales, content API, pricing cards, FAQ and lead form; take the structure and visual approach from easy-menu.org.
Open (recommended default first):
1. Hero visual: phone mockup of the real menu, with the dashboard moved to its own showcase section? **Default: yes.**
2. Clients strip: do we have permitted real client logos? **Default: omit until we do.**
3. Nav: add a Login link to the dashboard sign-in? **Default: yes.**
4. Demo tabs: which real demo menus exist per venue type (café, restaurant, food truck, cloud kitchen)? **Default: reuse the current demo menu until others exist.**
5. Language of focus: easy-menu is Arabic-first; keep ours default as today? **Default: unchanged.**

Next: `/implement landing-redesign-easymenu` — will need approval for: any content-schema change in `LandingContent.php`, new assets, and, separately, the push to `xorder-cloud` `main` (production).
