# Ladder Xorder's plans by ordering channel, then tills

Research window: notes gathered 2026-11-04 (prices "seen 2026-11-04" unless stated). Xorder facts come from the brief supplied with this task (code and live admin data checked 2026-11-04) and from `docs/domain/FOOD_SERVICE_DOMAIN.md`. Labels used throughout: **UNVERIFIED** = figure from an aggregator, review, search snippet or vendor claim that was not confirmed on a primary page; **(inference)** = a recommendation or calculation derived from the evidence, not stated by any source. EGP→USD conversions use **52.4 EGP/USD** (rate seen for 2026-10-09; CBE closing about 52.3 on 2026-10-01 and 52.46 on 2026-10-10). The pound was reported **"below 57" on 2026-10-27** ([Dostor](https://dostor.org/5751062)); at 57 every USD figure below is about 8% lower. No November 2026 CBE rate was found.

Egyptian restaurant software sells on a clear ladder: pure QR menus at **EGP 150-300 a month**, QR plus WhatsApp or table ordering at **EGP 800-1,000 a month**, local all-in-one POS at **EGP 500-3,000 a month**, and the regional leader Foodics at **EGP 2,850-3,960 per branch per month**, which is roughly half its Gulf price in dollars. Nearly every ordering vendor charges a flat subscription with 0% commission. The branch is the billing unit for POS. Extra tills, branches and inventory are the standard paid add-ons. Xorder covers both ordering and POS, so it should sell four public tiers defined by ordering channel: **Menu (منيو) at about EGP 199-299**, **WhatsApp (واتساب) at about EGP 599-899**, **Restaurant (المطعم, recommended) at about EGP 1,290-1,690**, and **Business (الأعمال) at about EGP 2,690-3,490 for up to three branches**. Extra POS terminals, extra branches, purchasing and the future ETA e-receipt should be add-ons. The owner decided on 2026-11-04 not to offer a POS-only plan: POS is sold only inside Restaurant and Business. All of these prices are inference anchored on competitor prices; none has been tested with buyers. The current plan set breaks this logic: the plan marked recommended, "المحترف", has POS and purchasing but no ordering at all, and its name is nearly the same as "باقة الاحتراف". Both can be fixed by editing the two plans while no prices are set, because only the demo restaurant and one trial restaurant are affected. One engineering fact limits every add-on: **features come only from the plan**. Until Xorder has per-restaurant entitlements, an "add-on" can only be built as a plan variant or a limit, and every active plan is shown on the public pricing page.

## Egypt prices sit at about half the Gulf for the same tier

Foodics, the regional leader, prices Egypt in pounds at a steep discount. Its Egypt page shows only two bundles, **Basic at EGP 2,848.95 or 3,019.89 a month and Advanced at EGP 3,733.67 or 3,957.69**, labelled "Billed Annually" under a Quarterly/Yearly toggle that does not say which figure is which ([Foodics Egypt](https://www.foodics.com/foodics-pricing-egypt/)). The same tiers cost **SAR 414-450 (USD 110-120) per branch in Saudi Arabia** ([Foodics KSA](https://www.foodics.com/foodics-pricing-ksa/)) and **AED 375 (USD 102) in the UAE** ([Foodics UAE](https://www.foodics.com/foodics-pricing-uae/)). Egypt therefore pays about **0.45-0.55 of the Gulf dollar price** (inference, calculated). Below Foodics, local vendors fill the market from about EGP 500 a month for a full POS, and QR-menu startups sell from about EGP 200. A third-party listing showing Foodics Egypt at "EGP 219-556" is almost certainly AED prices mislabelled and should be ignored ([FitGap](https://us.fitgap.com/products/foodics), contradicted by the Foodics Egypt page).

### Egypt competitors (EGP excl. VAT unless stated; seen 2026-11-04)

| Vendor | Tiers and published price | ≈ USD/mo at 52.4 | Billing basis | Status |
|---|---|---|---|---|
| Foodics Egypt ([page](https://www.foodics.com/foodics-pricing-egypt/)) | Basic 2,848.95 / 3,019.89 per month; Advanced 3,733.67 / 3,957.69. No Starter in Egypt. Basic: POS, inventory, tables, coupons, delivery zones. Advanced adds loyalty, API, web ordering, aggregators, BI. "Digital Receipts", Web Cashier and multi-brand Cloud Kitchen are unpriced add-ons | 54-58; 71-76 | Probably per branch (stated on KSA page, not Egypt page); which figure is yearly is unclear | Primary, ambiguous |
| Solo POS ([page](https://www.getsolopos.com/)) | Basic 499 (POS online/offline, KDS); Pro 999 (+ inventory, suppliers, CRM, tables); Mega 1,499 (+ online ordering for tables, pickup, delivery; waiter and driver apps); Empire 2,999 (+ multi-branch, one extra branch free). 5% quarterly, 10% semi-annual, 20% annual discount | 9.5; 19.1; 28.6; 57.2 | Per account; device pricing not stated | Primary |
| Daftra ([plans](https://www.daftra.com/plans)) | Basic 733 monthly / 489.50 yearly-billed; Advanced 1,225 / 977.58; Comprehensive 2,448 / 1,960. Add-ons: extra branch 1,293.60 / 980; extra offline POS device 637 / 490; extra user 392 / 294 | 9.3-14.0; 18.7-23.4; 37.4-46.7 | Per account plus per-unit add-ons; cloud POS devices unlimited, offline POS counted | Primary |
| Ordable Egypt store ([page](https://www.itsordable.com/ar/egypt/pricing)) | Starter 28,000/yr (2 branches); Growth 45,000/yr (5 branches, loyalty). "No commission on any plan" | 44.5; 71.6 | Per account, branch cap, annual | Primary |
| Ordable Egypt QR ([page](https://itsordable.com/en/egypt/product/qr-menu)) | Just QR 16,675/yr; With Ordering 22,425/yr (ordering, payments, call-a-waiter, white label); Unlimited price not shown | 26.5; 35.7 | Annual; branch count inconsistent (1 or 2) | Primary |
| Egypt Menus ([page](https://egyptmenus.com/pricing)) | Pro 299/mo or 2,990/yr (1 branch, 150 items); Max 999 or 9,990 (4 branches, 300 items); Business 1,999 or 19,990 (10 branches, 1,000 items). No order commission; paid by InstaPay or wallet | 5.7; 19.1; 38.1 | Per account, branch and item caps | Primary; earlier snippet showed lower prices |
| Taaj Menu ([page](https://taaj.me/?lang=en)) | Digital Menu 2,990/yr; Order and Pay 9,999/yr; Enterprise 15,000/yr. WhatsApp ordering in every plan, 0% commission | 4.8; 15.9; 23.9 | Annual, 1 branch | Primary |
| OrOMenu ([page](https://oromenu.com/en/)) | 199 for 1 month; 1,799 for 12 months; or 1 EGP per 5 views | 3.8; 2.9 | Per business | Primary; snippet showed half these prices |
| Talb ([blog, 2026-08-05](https://trytalb.com/blog/create-digital-menu-egypt-990-egp)) | 990/mo, no commission; POS installation 1,500 one-time; 28-day trial | 18.9 | Per account | Vendor blog |
| Queno ([page](https://www.queno.org/)) | No subscription; unpublished flat fee per completed order | n/a | Per order | Primary |
| Zyda ([page](https://www.zyda.com/pricing)) | No EGP prices; Kuwait Starter KWD 240/yr (2 branches), Growth KWD 430/yr (5). In Egypt the Ring call-centre add-on takes 3% of every order | ≈ 65; ≈ 117 (KWD rate UNVERIFIED) | Per account, branch cap | Primary (Kuwait) |
| Cloud Markit, Deyafa POS | "From EGP 149" ([Cloud Markit](https://cloudmarkit.pages.dev/about)); "from EGP 500" ([Slashdot](https://slashdot.org/software/p/Deyafa-POS/)) | 2.8; 9.5 | Period not stated | UNVERIFIED |

### Gulf and regional comparators (seen 2026-11-04)

| Vendor | Tiers and published price | ≈ USD/mo | Status |
|---|---|---|---|
| Foodics KSA ([page](https://www.foodics.com/foodics-pricing-ksa/)) | Starter SAR 248 monthly / 228 annual; Basic 450 / 414; Advanced 765 / 704. "Per branch", "No upfront payments. Hardware Included." Web ordering only in Advanced | 61-66; 110-120; 188-204 | Primary |
| Foodics UAE ([page](https://www.foodics.com/foodics-pricing-uae/)) | AED 199 / 375 / 556 billed annually | 54; 102; 151 | Primary |
| Rewaa KSA ([page](https://rewaa.com/pricing)) | Starter SAR 275 (1 branch, 1 register); Growth 367 (2 registers); Premium 708 (2 branches, 3 registers). Annual or 2-year only. Extra register SAR 149-249, period unlabelled | 73; 98; 189 | Primary; add-on period UNVERIFIED |
| Relish / 6lb.menu ([page](https://landing.6lb.menu/en/)) | Basic SAR 573.85/yr (menu); Advanced 1,033.85/yr (WhatsApp ordering); Professional 1,378.85/yr (table ordering, cashier receipt). VAT included | 12.8; 23.0; 30.6 | Primary |
| Talb KSA ([blog, 2026-08-06](https://trytalb.com/blog/digital-menu-99-sar-monthly)) | SAR 99/mo: delivery, pickup and table orders, no commission | 26.4 | Vendor blog |
| Mnasati ([page](https://mnasati.com/en/pricing)) | QR free; Basic SAR 299/mo or 3,500/yr; Premium 399/mo or 4,500/yr (adds POS, loyalty) | 78-80; 100-106 | Primary but internally inconsistent; low confidence |
| Sapaad ([TrustRadius](https://www.trustradius.com/products/sapaad/pricing)) | USD 58.99 for 1 outlet, 155.99 for 3, 234.99 for 5 | 59 per outlet | UNVERIFIED |

### Global benchmarks (USD unless stated; seen 2026-11-04)

| Vendor | Packaging | Status |
|---|---|---|
| Square UK ([page](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)) | Free £0 (pay processing only), Plus £69 per location with unlimited devices. KDS £15 per device, kiosk £35 per device, MarketMan inventory £79 per location, loyalty from £25 per location | Primary |
| Square US ([page](https://squareup.com/us/en/point-of-sale/restaurants/pricing)) | Free / Plus / Premium; coursing and seat management only in Premium. KDS $30 (Plus) or $20 (Premium) per device; kiosk $99. Base prices did not render (Plus quoted $49-69 elsewhere, UNVERIFIED) | Primary for add-ons |
| Lightspeed ([page](https://www.lightspeedhq.com/pos/restaurant/pricing/)) | Starter $69, Essential $189, Premium $399; KDS $30 per screen; negotiated payment rates from Essential | Primary |
| TouchBistro ([page](https://www.touchbistro.com/pricing/)) | POS from $69; Essentials bundle with payments and hardware from $119; every add-on "Get a Quote" | Primary |
| Toast | Starter Kit $0 software (reported 2-terminal cap), POS $69, KDS $35 ([UpMenu](https://www.upmenu.com/blog/toast-pricing), [Owner.com](https://www.owner.com/blog/toast-pricing)) | UNVERIFIED |
| Owner.com ([page](https://www.owner.com/pricing)) | Flex $249 + 5% per order, or Flat $499 with no restaurant fee; diners pay a 5% fee on both | Primary |
| MenuTiger ([page](https://www.menutiger.com/pricing)) | Free (75 orders/mo, 1 store), $17 (500 orders, 2 stores), $46 (2,000 orders, 5 stores, KDS), $119 (unlimited, POS, tables, white label). POS add-on $30; annual saves 15%; 0% commission | Primary |
| Sunday ([page](https://sundayapp.com/pricing)) | Pay-at-table: Standard $199, Premium $299 per month | Primary |
| Loyverse ([page](https://loyverse.com/pricing)) | POS free including KDS and multi-store; advanced inventory $25 per store, sales history $5 per store, employee management $5 per employee | Primary |

## Five packaging patterns decide where each Xorder feature belongs

**The branch is the billing unit for POS, and tills ride inside it.** Foodics charges "per branch" ([Foodics KSA](https://www.foodics.com/foodics-pricing-ksa/)), Rewaa caps registers per branch and sells extra ones ([Rewaa](https://rewaa.com/pricing)), and Square UK Plus includes **unlimited devices per location** ([Square UK](https://squareup.com/gb/en/point-of-sale/restaurants/pricing)). Per-device charges appear for secondary screens: **KDS at $15-35 a month** across Square, Lightspeed and Toast, and **Daftra's offline POS device at EGP 490-637 a month**, the closest local analogue to Xorder's per-device desktop licence ([Daftra](https://www.daftra.com/plans)). A pure per-device POS price is unusual in this region, so Xorder should include one terminal in each POS tier and charge only for extra terminals (inference).

**Ordering vendors sell a flat fee and promise 0% commission.** Ordable states it takes no commission on any plan ([Ordable](https://www.itsordable.com/ar/egypt/pricing)); Egypt Menus, Taaj, Talb, MenuTiger, Mnasati and Zyda's website plans say the same. The only Egyptian exceptions are Queno's per-order fee with no subscription ([Queno](https://www.queno.org/)) and Zyda's 3% Ring call-centre charge ([Zyda](https://www.zyda.com/pricing)). The value story is the aggregator commission avoided: Talabat is said to take **15-25% of the bill** in Egypt ([Menuviel](https://blog.menuviel.com/talabat-fees-and-commissions-for-restaurants/), **UNVERIFIED**, no published merchant terms), so a venue moving EGP 100,000 a month through an app pays about EGP 15,000-25,000, at least ten times any tier proposed here (inference). Talabat's Egypt business grew about 50% a year in 2025 ([EnterpriseAM](https://enterpriseam.com/logistics/2025/11/11/talabat-flynas-saudi-ground-services-see-bottom-line-top-line-growth-in-3q-2025/)), so the direct-channel argument is getting stronger, not weaker.

**Ordering depth, not features, separates the QR tiers.** Saudi seller 6lb.menu goes from menu only, to WhatsApp ordering, to table ordering with cashier receipt ([6lb.menu](https://landing.6lb.menu/en/)), and MenuTiger reserves table management and POS for its top tier ([MenuTiger](https://www.menutiger.com/pricing)). Branch, item and staff caps are the other common trigger: Egypt Menus steps from 1 to 4 to 10 branches and 150 to 1,000 items ([Egypt Menus](https://egyptmenus.com/pricing)). In POS products, **inventory and purchasing are the mid-tier upgrade** (Foodics Basic, Solo Pro, Rewaa Starter), while aggregators, loyalty, BI and API sit at the top. Square places coursing and seat management at its top tier ([Square US](https://squareup.com/us/en/point-of-sale/restaurants/pricing)). Xorder's flags line up with this ladder almost exactly, which is why channel is the right axis for its tiers (inference).

**Annual billing is the norm, with a modest discount.** Ordable and Taaj sell annual only and Rewaa sells one- or two-year terms. Discounts cluster at **15-20%**: Solo 20%, MenuTiger 15%, Egypt Menus about 17%, Loyverse "two months" ([Loyverse](https://loyverse.com/pricing)); Foodics KSA gives only about 8% and Daftra about 33%. Egyptian inflation was **12.8-14.5% in August-September 2026** ([Rio Times](https://www.riotimesonline.com/egypt-economy-2026-imf-pound-inflation/)), so a deep prepay discount locks in a falling real price for a year. "Two months free" (annual = 10 × monthly) plus a stated annual price review fits both the market and the inflation risk (inference). A **14-day trial without a card** is standard (Daftra, Solo POS). Local list prices end in 9 (199, 299, 499, 999, 1,499, 2,999), and Egypt Menus and OrOMenu live prices were 33-100% above their search-engine snippets (undated, so the rise happened recently), so any comparison must be rechecked before launch.

**Free POS tiers exist only where the vendor owns payments; ETA compliance is a paid extra.** Square Free and Toast's Starter Kit are funded by processing margin; Toast's payments take rate was about **48 bps** in Q4 2025 ([Motley Fool](https://www.fool.com/earnings/call-transcripts/2026/02/12/toast-tost-q4-2025-earnings-call-transcript)). Xorder has no card processing, so its software must carry the revenue and it should not copy a free POS (inference). A free **menu-only** tier is a different matter, since MenuTiger, Mnasati and Menux offer one and Egyptian freelancers sell one-off QR menus from **USD 15-50** ([Khamsat](https://khamsat.com/programming/custom-website-development/3998951-%D9%86%D8%B8%D8%A7%D9%85-%D8%B7%D9%84%D8%A8%D8%A7%D8%AA-%D8%B7%D8%B9%D8%A7%D9%85-%D9%85%D8%AA%D9%83%D8%A7%D9%85%D9%84-%D9%85%D9%86%D9%8A%D9%88-%D8%A5%D9%84%D9%83%D8%AA%D8%B1%D9%88%D9%86%D9%8A-%D9%85%D8%AA%D8%B9%D8%AF%D8%AF-%D8%A7%D9%84%D9%85%D8%B7%D8%A7%D8%B9%D9%85-%D9%85%D8%B9-qr)). On compliance, Foodics lists "Digital Receipts" as an unpriced add-on in Egypt, Odoo needs third-party ETA modules costing **USD 349-455** plus partner setup ([ECOSIRE](https://docs.ecosire.com/odoo-modules/egypt-eta-einvoicing)), and eDariba sells a device-free e-receipt subscription at **EGP 300 a month** ([eDariba](https://edariba.com/blog/%D8%B3%D8%B9%D8%B1-%D8%AC%D9%87%D8%A7%D8%B2-%D9%86%D9%82%D8%A7%D8%B7-%D8%A7%D9%84%D8%A8%D9%8A%D8%B9/), **UNVERIFIED** vendor blog). ETA brings taxpayers into e-receipts by named lists, most recently Decision 361/2025 effective 2025-11-15 ([Al Bawaba News](https://www.albawabhnews.com/5268187)), not by sector or turnover. One Odoo partner says the requirement covers restaurant bills ([2b-cs](https://www.2b-cs.com/blog/2b-1/egypt-b2c-invoicing-48)), but no list naming restaurants as a category was found. A named venue cannot keep using a non-integrated till, so ETA support decides POS deals with larger venues, while most small cafés and trucks are not yet obliged to comply.

## The recommended lineup: four public tiers

The recommended tiers follow the ordering channel because Xorder has no venue-type field and because **the admin plan form allows exactly one ordering mode, WhatsApp or System**, never both (the domain handbook records the same rule from `OrderingMode.php`). Everything in this section is **inference** built on the competitor anchors above. The flag prerequisites hold in every column: bill_requests requires table_management, which requires dine_in.

### Feature flags and limits per tier

| Flag / limit | منيو Menu | واتساب WhatsApp | المطعم Restaurant ★ | الأعمال Business |
|---|---|---|---|---|
| qr_menu | ✓ | ✓ | ✓ | ✓ |
| whatsapp_ordering | | ✓ | | |
| system_ordering | | | ✓ | ✓ |
| dine_in | | | ✓ | ✓ |
| table_management | | | ✓ | ✓ |
| bill_requests | | | ✓ | ✓ |
| pickup | | ✓ | ✓ | ✓ |
| delivery | | ✓ | ✓ | ✓ |
| customer_tracking | | | ✓ | ✓ |
| internal_reviews | | ✓ (verify it works without system orders) | ✓ | ✓ |
| product_analytics | | | ✓ | ✓ |
| multi_branch | | | | ✓ |
| pos | | | ✓ | ✓ |
| purchasing | | | add-on | ✓ |
| max_branches | 1 | 1 | 1 | 3 |
| max_items | 150 | 300 | 1,000 | 3,000 |
| max_categories | 20 | 40 | 100 | 300 |
| max_staff | 2 | 3 | 10 | 30 |
| max_terminals | 0 | 0 | 1 | 3 |

The caps copy the local market's steps (Egypt Menus 150 / 300 / 1,000 items; Rewaa one register per branch) and should be checked against the menus of real Xorder customers before publishing. Whether a limit can express "unlimited", and how each limit is enforced, was not verified for this report. Xorder has no orders-per-month limit, so MenuTiger-style volume metering is not available today.

### Prices (EGP excl. 14% VAT; annual = 10 × monthly)

| Tier | Monthly EGP | Suggested launch price | Annual EGP | ≈ USD/mo at 52.4 / at 57 | Anchors |
|---|---|---|---|---|---|
| منيو Menu | 199-299 | 249 | 1,990-2,990 | 3.8-5.7 / 3.5-5.2 | OrOMenu 199/mo and 1,799/yr; Egypt Menus Pro 299/mo and 2,990/yr; Taaj 2,990/yr |
| واتساب WhatsApp | 599-899 | 749 | 5,990-8,990 | 11.4-17.2 / 10.5-15.8 | Taaj Order and Pay 9,999/yr; Egypt Menus Max 999; Talb 990; 6lb WhatsApp tier ≈ USD 23 in KSA, about half that in Egypt |
| المطعم Restaurant ★ | 1,290-1,690 | 1,490 | 12,900-16,900 | 24.6-32.3 / 22.6-29.6 | Solo Mega 1,499 (POS plus ordering); Ordable QR with ordering 22,425/yr (≈ 1,869/mo); Egypt Menus Business 1,999 |
| الأعمال Business (3 branches) | 2,690-3,490 | 2,990 | 26,900-34,900 | 51.3-66.6 / 47.2-61.2 | Foodics Basic 2,849 per single branch; Solo Empire 2,999; Ordable Growth 45,000/yr for 5 branches |

Restaurant is deliberately priced near Solo Mega and well under Foodics, because Xorder lacks the ETA e-receipt, KDS, loyalty and aggregator integrations that Foodics Advanced includes. Business costs about the same as one Foodics Basic branch but covers three branches with ordering and purchasing, which is the multi-branch argument. The step from WhatsApp to Restaurant is about two times, matching the gap local vendors leave between WhatsApp-only and table ordering. For a later MENA price book, multiply the Egypt USD equivalent by about two for KSA and the UAE, the ratio Foodics uses. That puts Restaurant at about **SAR 185-240 a month**, between Talb KSA at SAR 99 and Mnasati Basic at SAR 299. These are starting hypotheses. A pricing page in Egypt also needs a clear choice on VAT display and a written rule for raising EGP prices every 6-12 months.

### Add-ons

| Add-on | Available on | Price (inference) | Anchor | What it needs in Xorder |
|---|---|---|---|---|
| Extra POS terminal | Restaurant, Business | EGP 290-490 per device per month | Daftra offline POS 490-637; Lightspeed KDS $30; Square UK KDS £15 | How POS licences are billed and how they relate to max_terminals was not verified |
| Extra branch | Business | EGP 790-1,190 per branch per month | Daftra extra branch 980-1,294; Zyda dine-in extra branch KWD 50/yr | A per-restaurant limit override; today only a plan variant can change max_branches |
| Purchasing | Restaurant (included in Business) | EGP 390-590 per branch per month | Solo POS Basic→Pro step of +500; Loyverse advanced inventory $25 per store; Square MarketMan £79 | A per-restaurant entitlement. The owner decided on 2026-09-12 that purchasing can be sold with no till (domain handbook) |
| ETA e-receipt (after it is built) | Restaurant; included in Business | EGP 250-400 per branch per month | eDariba 300/mo (UNVERIFIED); Foodics "Digital Receipts" add-on; Odoo modules USD 349-455 one-time | Not built |
| On-site POS setup (optional) | Any POS tier | EGP 1,000-2,000 one-time | Talb POS installation 1,500 | Service, not a flag |
| Hardware | Any POS tier | Resold or quoted separately | Single terminal EGP 8,000-17,000 ([2b-cs](https://www.2b-cs.com/blog/2b-1/odoo-arabic-pos-egypt-55)) | None |

The binding constraint is that **features come only from the plan**. Until per-restaurant entitlements exist, purchasing can only be sold inside Business, extra branches can only come from a separate higher-cap plan, and extra terminals depend on how the separate POS licences already work. Every active plan is listed on the public pricing page, so each variant created for one customer would appear publicly unless it is made inactive. Whether an inactive plan can still be assigned and keep working was not verified. Building a small add-on entitlement model (restaurant + add-on + quantity) is the prerequisite for the add-on column; it is a product and engineering decision for the owner (inference).

## Venue types map to channels, not to plan names

Because a venue is defined only by its plan's flags, the tiers must be described by what they let a venue do, and venue types appear only in marketing copy. Restaurants are the model Xorder serves best today; cloud kitchens are the weakest, because aggregator integrations, a kitchen display and multi-brand support are all missing while purchasing is ready (domain handbook, section 3).

| Venue model | Usual starting tier | Grows into | Gaps to say out loud when selling |
|---|---|---|---|
| Café (counter, pay first) | WhatsApp for pickup pre-orders, or Restaurant to use dine-in ordering without tables | Restaurant with POS | No tips, no loyalty; Restaurant includes tables a café may never use |
| Restaurant (tables, pay last) | Restaurant: table ordering, bill requests, POS | Business at the second branch; purchasing add-on | ETA e-receipt for venues on an ETA list; no KDS |
| Food truck (window, weak signal) | Menu, or WhatsApp for pre-orders | Restaurant, if it needs the offline POS | How a moving truck maps to a branch and its QR menu is undefined |
| Cloud kitchen (delivery only) | WhatsApp or Restaurant with only delivery used, plus purchasing | Business for several kitchens | No aggregator integration, no multi-brand, no KDS. Do not market a cloud-kitchen plan until these exist |
| Multi-branch chain | Business | Business plus extra branches | Per-branch add-ons need entitlements first |

One gap matters across models: a plan cannot combine WhatsApp ordering with system ordering. Taaj includes WhatsApp ordering in every plan and 6lb.menu adds table ordering on top of WhatsApp ordering, so a café that wants WhatsApp delivery and table QR ordering at the same time can get both from those vendors but not from Xorder.

## Fixing the plan marked recommended that sells POS without ordering

Today's recommended plan, "المحترف", carries qr_menu, internal_reviews, product_analytics, multi_branch, pos and purchasing, and no ordering flag. A visitor who chooses the highlighted plan gets a till and a static menu, while the plan that actually takes orders, "باقة الاحتراف", is not highlighted and has a near-identical name. No plan has a price yet and only two restaurants use them, so the fix is cheap now and expensive later. The sequence below is a proposal (inference); any change to production plans needs the owner's approval and should be done through the admin UI, not by migration.

First, record the current flags and limits of all four plans in `docs/` so the change can be reversed. Then edit **"المحترف" into الأعمال (Business)**: add system_ordering, dine_in, table_management, bill_requests, pickup, delivery and customer_tracking; keep multi_branch, pos, purchasing, internal_reviews and product_analytics; set the Business limits; and remove the recommended mark. The demo restaurant stays on it and becomes a demo of the full product, which is what a sales demo should show. Check before and after that the demo restaurant's existing POS licences remain valid, since how licence validity depends on plan fields was not verified. Next, edit **"باقة الاحتراف" into المطعم (Restaurant)**: add pos with max_terminals 1, set the recommended mark, and remove multi_branch only after confirming that the trial restaurant has one branch. If it already runs more than one branch, move it to Business for the rest of its trial instead of taking the feature away. Rename **"باقة البداية" to منيو (Menu)** and **"باقة المتقدمة" to واتساب (WhatsApp)**, keeping their flags, adding the limits, and adding internal_reviews to WhatsApp only if reviews work without system orders. Finally, set prices on all four public plans at the same time. A plan edit reaches a restaurant only when that restaurant is saved again in the admin portal (see the code notes below), so after each step save the affected restaurant and check its dashboard and POS.

### Verified in code after this report was written (2026-11-04)

Two facts from the xorder-cloud source (production commit 1c686e5) change how the fix above must be carried out:

- **Editing a plan does not update restaurants already on it.** `Admin\PlanController::update` only saves the plan. A restaurant's flags are re-derived from its plan only when that restaurant is saved in the admin portal (restaurant edit form or Subscription section, both call `PlanEntitlementService::sync`), or when the `restaurants:sync-entitlements` command is run on the server. After each plan edit, open each affected restaurant in the admin portal and save it, then check its dashboard.
- **Renaming a plan disconnects its restaurants.** Restaurants store the plan's name in `subscription_plan`, and `PlanEntitlementService` finds the plan with `Plan::where('name', ...)`. Nothing updates restaurants when a plan is renamed, so after a rename their next sync finds no plan and silently keeps the old flags. Rename a plan only if, straight after, every restaurant on it is moved to the new name in its Subscription section. The safer order is to edit flags and limits first, then rename, then reassign.

## Open questions for the owner

| # | Question | Why it matters |
|---|---|---|
| 1 | Should Menu be free forever with tight caps, or paid with a 14-day trial? | Free menus are common regionally and freelancers sell one-off QR menus for USD 15-50; a free tier buys leads but costs support |
| 2 | How will restaurants pay: InstaPay, wallet, Fawry reference code or card? | No data was found on how Egyptian SMBs pay SaaS; Egypt Menus takes InstaPay and wallets |
| 3 | Quote prices excluding or including the 14% VAT? | B2B buyers reclaim VAT, but small unregistered venues do not; Egyptian convention was not confirmed |
| 4 | How are POS licences priced today, and does max_terminals cap the licences a restaurant can hold? | Decides whether "extra terminal" is a licence sale or a plan change |
| 5 | Can an inactive plan be assigned to a restaurant and keep working? | Needed for legacy and custom plans without showing them publicly |
| 6 | Should one plan be allowed WhatsApp and system ordering together? | Competitors stack both; Xorder forces a choice |
| 7 | When will per-restaurant add-on entitlements and ETA e-receipt be built? | Purchasing, extra branches and extra terminals as add-ons depend on them |
| 8 | How often will EGP prices be reviewed, and in which currency will the MENA price book be set? | The pound moved from about 47.7 to about 52-57 per dollar during 2026 |
| 9 | Does the trial restaurant use more than one branch, and how many items do real menus have? | Decides the Restaurant branch rule and whether the item caps fit |

## Conclusion

Xorder's flags already form the ladder the region uses: menu, then WhatsApp ordering, then table ordering with a till, then branches and purchasing. The current plans scrambled it by highlighting the one plan that cannot take an order. The commercial risk is not that Xorder is priced too high or too low, since every tier proposed here sits inside a band where Egyptian vendors already sell. The risk is selling the till before it can issue an ETA e-receipt and before add-ons can be sold one restaurant at a time. That points to an order of work: fix and price the four public plans now, sell Restaurant as the default, and treat per-restaurant entitlements and ETA e-receipt as the two builds that unlock the POS revenue.

Two numbers deserve watching more than any competitor. The pound went from about 52.4 to the dollar on 2026-10-09 to reports of "below 57" on 2026-10-27, a fall of up to about 8% within one month, so an EGP price list loses real value quickly and needs a review clause from day one. And Foodics already prices Egypt at about half its Gulf level, which suggests the MENA expansion should launch with a separate Gulf price book at roughly twice the Egypt dollar equivalent, not a single regional list.
