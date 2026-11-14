# Global restaurant SaaS plan packaging and pricing benchmarks (for Xorder tier design)

Research date: 2026-11-04 (all "seen" dates below = 2026-11-04 unless stated). Prices are USD unless stated.
Labels: **PRIMARY** = read on the vendor's own pricing page this session. **UNVERIFIED** = only from third-party review/aggregator/competitor sites (often competitors of the vendor, e.g. Owner.com, UpMenu, GetSauce, which have an incentive to frame rivals as expensive); treat as indicative only.
Fetch failures this session (403 or DNS): pos.toasttab.com (pricing page and Toast's own pricing blog), chownow.com/pricing, nerdwallet.com, menu.app (DNS not found). clover.com/pricing returned no pricing content. squareup.com/us restaurant pricing page rendered without base prices (template placeholders). So Toast, Clover, ChowNow, BentoBox, Olo, Popmenu figures are all UNVERIFIED.

## Q1. Vendor-by-vendor: tier names, prices, inclusions, add-ons, per-location vs per-device, payments-subsidised, commission vs flat

### Takeaway
POS vendors (Square, Toast, Lightspeed, TouchBistro, Clover) use 3-4 tiers priced per location with a $0 or low-cost entry tier subsidised by mandatory integrated payment processing, then charge per-device for extra screens (KDS ~$15-35/screen/month, kiosk $35-99/device/month) and sell marketing/loyalty/inventory as per-location add-ons. Online-ordering/marketing vendors (Owner.com, ChowNow, Popmenu, BentoBox) sell flat monthly subscriptions ($119-$499/location) with 0% restaurant commission, often shifting a per-order fee to the diner; QR-menu SaaS (MenuTiger) uses cheap tiers gated by orders/month and store count; pay-at-table (me&u, Sunday) charges diners per-order fees or venues a flat monthly fee.

### Cited Findings

**Square for Restaurants (PRIMARY for UK; US partial)**
- US page lists tiers Free, Plus ("Best value"), Premium, and Square Pro (custom, "contact sales if you process over $250,000 per year"). Free includes item/menu management, pickup and local delivery, branded online ordering page; Plus adds integrated inventory tracking and close-of-day reports; Premium adds coursing and seat management. Base prices did not render on the page. — [Square US restaurant pricing](https://squareup.com/us/en/point-of-sale/restaurants/pricing) (seen 2026-11-04)
- US per-device add-ons, monthly: Square KDS app $30 on Plus / $20 on Premium; Square Kiosk $99 on both; Kiosk Lite (iOS) $50 on Plus / $30 on Premium. (Note: add-on per-device price drops on the higher tier — a tier-upgrade incentive for multi-device venues.) — [Square US restaurant pricing](https://squareup.com/us/en/point-of-sale/restaurants/pricing)
- US Plus base price is UNVERIFIED and conflicting: $60/location (CostBench restaurant page), $49/month (CostBench general page, verified Feb 2026), $69/location (Owner.com); Premium $149/location (Capterra, CostBench). Korona reports Square consolidated 18 separate subscriptions (incl. Square for Restaurants, Retail) into Free/Plus/Premium in October 2025. — [CostBench](https://www.costbench.com/software/restaurant-pos/square-for-restaurants/); [Capterra](https://www.capterra.com/p/175628/Square-Point-of-Sale/pricing/); [Owner.com](https://www.owner.com/blog/square-pos-system-cost); [Korona](https://koronapos.com/blog/square-pos-fees/)
- UK (PRIMARY): Free £0/month, pay processing only, **unlimited devices and locations**, support Mon-Fri 9-17. Plus £69/month **per location**, unlimited devices, 30-day free trial, 24/7 support. Premium custom for businesses processing more than £200,000/year. — [Square UK restaurant pricing](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)
- UK processing (same across Free/Plus; Premium may be custom): in person 1.75%; online UK cards 1.4% + 25p; online non-UK 2.5% + 25p; manual/card-on-file 2.5%. — [Square UK](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)
- UK add-ons: KDS £15/month per KDS device (FAQ says unlimited KDS devices at no extra cost on Plus); kiosk £35/month per device; Restaurant Inventory by MarketMan +£79/month per location (not available on Free); Team Plus £20/month (included in Plus/Premium); Shifts £3/month per employee after five; Loyalty from £25/month per location; Marketing from £9/month per location; Online Ordering free tier included on all plans. Hardware: stand £99+VAT, terminal £149+VAT, register £699+VAT, 21.5" KDS screen £549+VAT. — [Square UK](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)

**Toast (all UNVERIFIED — Toast site returned 403)**
- Tiers: Starter Kit $0/month software (reported limit of 2 terminals; processing reported 3.09% + 15¢, one source says 3.5% + 15¢ pay-as-you-go; reported 2-year contract), Point of Sale $69/month (one source says Toast's page advertises "as low as $79/month per terminal"; processing cited 2.49% + 15¢), Build Your Own custom. — [UpMenu](https://www.upmenu.com/blog/toast-pricing); [G2](https://www.g2.com/products/toast/pricing); [Startupowl](https://startupowl.com/reviews/toast); [CostBench](https://www.costbench.com/software/restaurant-pos/toast-pos/)
- Add-ons reported from an Owner.com demo call (May 2025): Marketing Essentials $185/month (gift cards, loyalty, basic email/SMS); Digital Storefront Essentials $75/month (online ordering, Local by Toast, Toast Delivery Service integrations); KDS $35/month; DoorDash integration $30/month. Hardware example $2,645 one-time; onboarding $849 for 1-2 tablets + $100 digital ordering + $100 gift-card conversion. Article contains internal arithmetic inconsistencies. — [Owner.com Toast pricing](https://www.owner.com/blog/toast-pricing)
- CostBench estimates most restaurants pay $300-$700/month all-in once processing, online ordering, KDS and other add-ons are included (estimate, not a vendor figure). — [CostBench](https://www.costbench.com/software/restaurant-pos/toast-pos/)
- Toast's economics are payments-led: Q4 2025 call summary puts fintech net take rate at 58 bps, payments take rate 48 bps; management cites mid-single-digit SaaS ARPU growth. — [Motley Fool Q4 2025 transcript](https://www.fool.com/earnings/call-transcripts/2026/02/12/toast-tost-q4-2025-earnings-call-transcript); earlier quarter 51 bps payments / 61 bps fintech per [SaaStr](https://www.saastr.com/5-interesting-learnings-from-toast-at-billion-in-arr/)

**Lightspeed Restaurant (PRIMARY, US)**
- Starter $69, Essential $189, Premium $399, Enterprise custom (billing period not labelled on page; presumably monthly). Starter uses "Integrated payments (Default)", Essential/Premium "Integrated payments (Custom)" — i.e. negotiated processing is a higher-tier benefit. Lightspeed Tasks is an add-on on Starter, included in Essential/Premium. Enterprise adds personalised software+hardware package, unlimited launch/consultation, dedicated CSM. — [Lightspeed restaurant pricing](https://www.lightspeedhq.com/pos/restaurant/pricing/)
- KDS $30 per screen per month on all three paid plans. — [Lightspeed](https://www.lightspeedhq.com/pos/restaurant/pricing/)
- The page lists a broad common feature set on all plans (menu manager, floor plans, Advanced Insights, online ordering, multi-location management, advanced inventory, raw API), but also lists contactless ordering, order-and-pay-at-table, advanced inventory, reservations and third-party delivery integrations as add-ons (no prices). Page notes "Prices may vary depending on the nature of the business and the industry." — [Lightspeed](https://www.lightspeedhq.com/pos/restaurant/pricing/)

**TouchBistro (PRIMARY)**
- Point of Sale from $69/month (hardware required; "Hardware, payment processing, and additional fees apply"); Essentials Bundle from $119/month (adds integrated payments + restaurant-grade hardware); Custom Setup quote. — [TouchBistro pricing](https://www.touchbistro.com/pricing/)
- Every add-on is "Get a Quote": TouchBistro One, Payments, Customer Facing Display, Inventory, Labor Management, KDS, Profit Management, Online Ordering, Reservations, Loyalty, Marketing, Gift Cards. Hardware financing offered "for venues with two or more terminals." Per-terminal pricing not shown. — [TouchBistro pricing](https://www.touchbistro.com/pricing/)

**Clover (UNVERIFIED — sources conflict because some include financed hardware)**
- Reported restaurant bundles split by service model: Quick Service Starter $135/month or $849 + $89.95/month; Full Service Standard $225/month or $1,799 + $99.90/month; Full Service Advanced $354/month or $3,448 + $134.85/month (36-month financing). — [Merchant Insiders](https://merchantinsiders.com/blogs/clover-fees/)
- Other reported figures: Starter $79 / Standard $149 ([UpMenu](https://www.upmenu.com/blog/clover-pos-pricing)); full-service Starter $160 / Standard $210 / Advanced $310 incl. Station ([Merchant Maverick](https://www.merchantmaverick.com/?p=22365)); "per seat" Starter Restaurant $105/seat/month, Standard $145 ([Sonary](https://sonary.com/reviews/clover/)). Additional device $14.95/month cited by several sources; restaurant in-person processing 2.3% + 10¢, keyed 3.5% + 10¢. — [CostBench](https://costbench.com/software/restaurant-pos/clover/)

**Owner.com (PRIMARY)**
- Flex $249/month + 5% restaurant fee per order; Flat Rate $499/month, no restaurant fees (recommended for $5k+/month online sales). On both plans guests pay a 5% "order support fee". Month-to-month, no cancellation fees, switch freely; multi-location Flat Rate gets "special rates" (no figures). All plans include website, online ordering, branded app, SEO pages, loyalty, AI email/SMS marketing, catering orders, setup/migration, chargeback protection, 24/7 support. — [Owner.com pricing](https://www.owner.com/pricing)

**ChowNow (UNVERIFIED — official page 403)**
- Reported tiers Hub $119/month, Pro $229/month, Premier $328/month, setup $119-$499; no per-order commission on direct orders; processing 2.95% + $0.29. Older/conflicting figures: $149/month + $399 setup, or $119/month + $199 setup annual; Pro $199 annual. — [GetSauce](https://www.getsauce.com/post/chownow-pricing-and-fees); [Business Insider NL](https://businessinsider.nl/what-is-chownow-how-the-food-ordering-service-differs-from-its-competition); [fitgap](https://us.fitgap.com/products/004485/chownow-for-restaurants)

**Popmenu (UNVERIFIED)**
- Starter $179/month ($159 annual prepay), Essentials $299 ($269), Premier $499 ($449), Enterprise custom. Upgrade path is marketing depth: Essentials adds mass email, social posting, SMS (500); Premier adds SMS (5,000), segmentation, waitlist & reservations. Online ordering, Boost (paid ads) and AI phone answering are add-ons; ordering reported ~$50/month/location + $1/order charged to customers; AI phone answering from $149/month. — [fitgap](https://us.fitgap.com/products/023664/popmenu); [Popmenu pricing (official, not fetched)](https://get.popmenu.com/pricing); [GetSauce](https://www.getsauce.com/post/popmenu-pricing-fees)

**BentoBox (UNVERIFIED — no public price list)**
- Reported ~$119/month (preset website) and ~$199/month (custom website + e-commerce); Dine-In Ordering $49/month per license; Reservations $199/month per location; online ordering add-on $79/month/location + $500 setup; one source reports $0.99/order + 3% card fee on takeout/delivery. — [GetSauce](https://www.getsauce.com/post/bentobox-pricing-fees); [UpMenu](https://www.upmenu.com/bentobox)

**Olo (UNVERIFIED — enterprise, sales-led)**
- Filings describe a subscription line (Ordering, Switchboard, Kiosk modules, priced per location per month) plus a transaction line (Rails, Dispatch, Olo Pay); some customers buy a monthly block of orders for a fixed fee and pay per order beyond it; Rails charges per-transaction fees to both restaurant and delivery provider. — [Olo 10-Q via relayto](https://olo.relayto.com/e/q1-2022-10q-7ettdo547gs3x/q4l98veC28); [Olo 10-K via relayto](https://olo.relayto.com/e/2022-10k-fecwfw2f0df1a/oOx8gosN90)

**MenuTiger (QR menu + ordering SaaS) (PRIMARY)**
- Free $0: 75 orders/month, 1 store. Regular $17/month: 500 orders/month, up to 2 stores, unlimited menu items. Advanced $46/month: 2,000 orders/month, up to 5 stores, includes KDS. Premium $119/month: unlimited orders and stores, includes POS, printer management, full table management, white label (custom domain), priority support. POS add-on $30/month and printer management $20/month on Regular/Advanced; white-label domain $29/month. 0% commission per order. Annual billing saves 15%. Customer warned at 80% of order limit with an unspecified grace allowance at 100%. — [MenuTiger pricing](https://www.menutiger.com/pricing)

**Menu.app** — could not be checked (DNS failure on menu.app); no data.

**me&u / Mr Yum (PRIMARY help-centre)**
- Platform fee charged **to the diner, per order**, tiered by order value: $0.01-24.99 → $0.20; $25-49.99 → $0.60; $50-74.99 → $1.20; $75-149.99 → $2.00; $150+ → $2.90 (cap). Venue surcharges separate. — [me&u help: platform fee](https://help.meandu.com/hc/en-us/articles/17561701058703-Understanding-the-me-u-platform-fee)

**Sunday (QR pay at table) (PRIMARY)**
- Standard $199/month (single or multi-location; Payment, Ordering, online reputation/reviews, guest data collection, dashboard & reports); Premium $299/month (adds loyalty integrations and Enterprise Pack); Guest platform custom. QR codes $5 each; optional physical onboarding $299. Page does not state processing rates or who pays them. — [Sunday pricing](https://sundayapp.com/pricing)
- Earlier positioning (press): no subscription/setup fee, usage-based processing, claimed ~0.5% cost per transaction to operators (company claim). Diner reviews report per-payment fees such as £1.99 per payer (anecdotal). — [Fintech Futures](https://fintechfutures.com/?p=15227424); [Trustpilot](https://pl.trustpilot.com/review/sundayapp.com?page=2)

### Inferences
- Three distinct pricing archetypes exist: (a) POS: per-location subscription + per-device extras + payments margin; (b) own-channel ordering/marketing: flat per-location subscription with 0% restaurant commission, sometimes a diner-paid fee (Owner.com 5%, Popmenu $1/order, me&u tiered fee); (c) QR menu SaaS: low-price tiers metered by orders/month and number of stores. Xorder spans all three, so it can borrow per-location base + per-device POS + order-volume caps.
- Free/near-free entry tiers (Square Free, Toast Starter Kit $0) are only economic because the vendor owns processing; without owning payments in Egypt, Xorder probably cannot copy a $0 POS tier and should instead gate its free tier by volume (MenuTiger-style).
- Sunday's move from pure transaction pricing to $199/$299 subscriptions (inferred from comparing the press description with the current page) suggests pure pay-at-table transaction pricing was not sufficient on its own; this is an inference, not a stated reason.

### Gaps
- Toast, Clover, ChowNow, BentoBox, Olo prices could not be confirmed on a primary source (403/no public list). Square US base prices did not render.
- No data for Menu.app; other QR SaaS (e.g. GloriaFood, Restolabs) not checked due to time budget.

## Q2. Which features are the upgrade triggers between tiers?

### Takeaway
The recurring upgrade triggers are: table-service depth (coursing, seat management, floor plans), inventory, advanced/close-of-day reporting, multi-location/enterprise tooling, 24/7 support, negotiated payment rates, loyalty/marketing volume (SMS counts), and order-volume or store-count caps for QR SaaS. Online ordering is increasingly included in base tiers rather than used as a trigger.

### Cited Findings
- Square: Free→Plus adds integrated inventory and close-of-day reports (US) and 24/7 support (UK); Plus→Premium adds coursing and seat management; KDS/kiosk per-device fees are lower on Premium. Online ordering is in Free. — [Square US](https://squareup.com/us/en/point-of-sale/restaurants/pricing); [Square UK](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)
- Lightspeed: Starter→Essential trigger is custom (negotiated) payment rates and included Lightspeed Tasks; Enterprise adds CSM, unlimited onboarding. Online ordering and multi-location management listed on all plans. — [Lightspeed](https://www.lightspeedhq.com/pos/restaurant/pricing/)
- TouchBistro: POS→Essentials trigger is bundled payments + hardware. — [TouchBistro](https://www.touchbistro.com/pricing/)
- Popmenu: triggers are marketing volume (SMS 500 → 5,000), segmentation, waitlist/reservations (UNVERIFIED). — [fitgap](https://us.fitgap.com/products/023664/popmenu)
- MenuTiger: triggers are orders/month (75 → 500 → 2,000 → unlimited), stores (1 → 2 → 5 → unlimited), KDS (Advanced), POS/table management/white label (Premium). — [MenuTiger](https://www.menutiger.com/pricing)
- Sunday: Standard→Premium trigger is loyalty integrations + enterprise tools. — [Sunday](https://sundayapp.com/pricing)
- Owner.com: trigger between Flex and Flat is online sales volume (~$5k+/month makes Flat cheaper). — [Owner.com](https://www.owner.com/pricing)
- Toast Starter Kit reportedly capped at 2 terminals (device count as trigger) (UNVERIFIED). — [UpMenu](https://www.upmenu.com/blog/toast-pricing)

### Inferences
- For Xorder: QR menu + basic ordering belong in the entry tier (they are table stakes at Square Free / MenuTiger Free); inventory/purchasing, advanced analytics, table/floor service, multi-branch consolidation and loyalty/marketing are the conventional paid triggers.
- A volume trigger (orders/month) is the most transparent trigger for a QR-ordering product without payment margin.

### Gaps
- No public data on which trigger actually converts best (conversion rates by trigger) for any vendor.

## Q3. How are additional devices/terminals and additional locations priced?

### Takeaway
Base subscription is almost universally per location; front-of-house POS devices are often unlimited per location at mid-tier (Square), while secondary devices (KDS, kiosk, customer display) are charged per device per month. Multi-location discounts are quote-based.

### Cited Findings
- Square UK Plus £69/month per location with unlimited devices; Free also unlimited devices and locations; KDS £15/device, kiosk £35/device; inventory, loyalty, marketing add-ons priced per location. — [Square UK](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)
- Square US KDS $30/$20 per device (Plus/Premium), Kiosk $99/device, Kiosk Lite $50/$30. — [Square US](https://squareup.com/us/en/point-of-sale/restaurants/pricing)
- Lightspeed KDS $30 per screen per month on all plans. — [Lightspeed](https://www.lightspeedhq.com/pos/restaurant/pricing/)
- Clover additional device $14.95/month (UNVERIFIED); Sonary reports per-seat pricing (UNVERIFIED). — [CostBench](https://costbench.com/software/restaurant-pos/clover/); [Sonary](https://sonary.com/reviews/clover/)
- Toast: reported as per-terminal pricing ("as low as $79/month per terminal") and Starter Kit limited to 2 terminals (UNVERIFIED). — [UpMenu](https://www.upmenu.com/blog/toast-pricing)
- Toast KDS $35/month (UNVERIFIED). — [Owner.com](https://www.owner.com/blog/toast-pricing)
- MenuTiger: stores included per tier (1/2/5/unlimited) rather than per-location fee; POS is a $30/month add-on below Premium. — [MenuTiger](https://www.menutiger.com/pricing)
- Owner.com: multi-location Flat Rate "special rates" (no figures). — [Owner.com](https://www.owner.com/pricing)
- Sunday: Standard covers "single or multi-location" at $199/month; QR codes $5 each. — [Sunday](https://sundayapp.com/pricing)
- Olo: per location per month for core modules (UNVERIFIED). — [businessmodelcanvastemplate](https://businessmodelcanvastemplate.com/blogs/how-it-works/olo-how-it-works)

### Inferences
- Market reference points for an extra device: ~$15-35/month for KDS/secondary screens, ~$35-99 for kiosks. Xorder's per-device POS licence should be benchmarked against these secondary-device prices rather than full plan prices, and adjusted for Egyptian purchasing power (out of scope here).
- Square's "unlimited POS devices per location" on Plus is a strong competitive anchor; per-device POS pricing is defensible mainly where the POS is the primary product (Toast-style) or where devices carry marginal support cost.

### Gaps
- No primary source for Toast per-terminal or Clover per-device fees. No published volume-discount curves for multi-location.

## Q4. Packaging by venue type (café/QSR, full service, ghost kitchen, food truck)

### Takeaway
Explicit vertical plans are rare; most vendors use one tier ladder where full-service features (coursing, seats, floor plans, pay-at-table) sit higher. Clover is the clearest case of service-model packaging (Quick Service vs Full Service bundles), and Toast markets programmes by restaurant type rather than separate price lists.

### Cited Findings
- Square places coursing and seat management only in Premium (full-service features at top tier); Free covers pickup/local delivery (QSR/café). — [Square US](https://squareup.com/us/en/point-of-sale/restaurants/pricing)
- Clover restaurant bundles named "Quick Service Starter", "Full Service Standard", "Full Service Advanced" (UNVERIFIED). — [Merchant Insiders](https://merchantinsiders.com/blogs/clover-fees/)
- Toast offers programmes designed around restaurant types including food truck (UNVERIFIED); Owner.com suggests the Starter Kit for food trucks, pop-ups, single-location cafés. — [Business.org](https://www.business.org/software/point-of-sale/toast-pos-system-review/); [Owner.com](https://www.owner.com/blog/toast-pricing)
- Lightspeed lists "multiple revenue center support for hotels" and pre-auth bar mode on all plans (bar/hotel features not tiered). — [Lightspeed](https://www.lightspeedhq.com/pos/restaurant/pricing/)
- No vendor in this sample published a ghost-kitchen-specific plan; Otter targets ghost kitchens/delivery-heavy concepts as a product focus (not a plan). — [Otter blog](https://www.tryotter.com/blog/otter-products/otter-vs-toast)

### Inferences
- For Xorder (which has no venue-type field), feature-flag-based tiers map naturally: café/food truck = entry tier (QR menu, pickup, 1-2 devices); full-service = mid/top tier (tables, rounds, splits, pay-at-table); cloud kitchen = delivery + multi-channel + multi-brand (a known Xorder gap). Avoid making table features mandatory in lower tiers.

### Gaps
- No primary-source vertical price lists found; ghost-kitchen and food-truck packaging evidence is thin and secondary.

## Q5. Evidence on what packaging works (strategy writeups)

### Takeaway
Practitioner guidance (OpenView, Simon-Kucher) favours good-better-best as the default, with few add-ons per initial purchase and features sorted into leaders/fillers/bundle-killers per segment; restaurant-tech-specific evidence is mostly about payments being the real revenue engine. No rigorous restaurant-specific packaging study was found.

### Cited Findings
- OpenView (Kyle Poyar): GBB is the de facto starting point; average customer should not need more than one or two add-ons at initial purchase; categorise features into "leaders", "fillers", "bundle killers" per segment (Simon-Kucher practice). — [OpenView: better SaaS packaging](https://openviewpartners.com/blog/better-saas-packaging/) (search-snippet based; direct fetch returned the homepage, so wording UNVERIFIED); [OpenView: insights from 100 SaaS companies](https://openviewpartners.com/blog/insights-from-100-saas-companies-why-its-time-to-rethink-your-packaging-strategy/)
- A Simon-Kucher partner notes GBB doesn't fit every company (no single land-and-expand path). — [Monetizely roundup](https://www.getmonetizely.com/blogs/three-pricing-bigwigs-weigh-in-on-the-good-better-best-packaging-approach)
- Toast's monetisation is fintech-led: payments take rate ~48-51 bps and fintech net take rate ~58-61 bps vs mid-single-digit SaaS ARPU growth. — [Motley Fool](https://www.fool.com/earnings/call-transcripts/2026/02/12/toast-tost-q4-2025-earnings-call-transcript); [SaaStr](https://www.saastr.com/5-interesting-learnings-from-toast-at-billion-in-arr/)
- a16z claim that embedded fintech raises revenue per customer 2-5x is cited only via a vendor blog (UNVERIFIED). — [Apideck](https://www.apideck.com/blog/embedded-finance-vertical-saas.md)
- Owner.com's dual Flex/Flat structure lets the customer self-select between commission-like and flat pricing by volume — a working example of offering both value metrics. — [Owner.com](https://www.owner.com/pricing)

### Inferences
- In a market where Xorder does not (yet) earn payment margin, software must carry the revenue, so the value metric matters more: per-branch base + per-POS-device + order-volume caps, with a small number of add-ons.
- Offering an optional "commission/low-fixed" vs "flat" choice (Owner.com pattern) may help small Egyptian venues with low volume while retaining larger ones.

### Gaps
- No Price Intelligently/Paddle or Simon-Kucher study specific to restaurant tech was found; widely circulated statistics (e.g. "30% revenue growth from GBB") could not be traced to originals and are excluded.
