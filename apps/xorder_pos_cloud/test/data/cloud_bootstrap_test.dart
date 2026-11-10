import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos_cloud/data/cloud/bootstrap_bundle.dart';
import 'package:shared_module/domain/models/tender_method.dart';

/// A representative bundle, shaped exactly as the agreed POS-BE-023 contract
/// serialises it. If the backend changes a key, this fixture is where the
/// disagreement surfaces — before a till in a business does.
const _fixture = '''
{
  "config_version": 7,
  "synced_at": "2026-09-02T10:00:00Z",
  "server_time": "2026-09-02T10:00:01Z",
  "restaurant": {
    "id": 42, "name": "Demo Grill", "name_ar": "مطعم ديمو", "slug": "demo",
    "tax_registration_number": "123-456-789",
    "currency": "EGP", "exponent": 2, "timezone": "Africa/Cairo"
  },
  "terminal": {
    "id": "0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10", "name": "Bar 1",
    "branch_id": 3, "deployment_mode": "cloud", "sync_policy": "manual"
  },
  "branches": [
    { "id": 3, "code": "MAADI", "name": "Maadi",
      "supported_order_types": ["dine_in", "takeaway"] },
    { "id": 9, "code": null, "name": "Zamalek", "supported_order_types": [] }
  ],
  "catalog": {
    "categories": { "data": [
      { "id": 11, "name_en": "Burgers", "name_ar": "برجر", "slug": "burgers",
        "sort_order": 1, "is_active": true }
    ], "deleted_ids": [], "complete": true },
    "items": { "data": [
      { "id": 101, "category_id": 11, "name_en": "Classic Burger",
        "name_ar": "برجر كلاسيك", "price_minor": 9500,
        "discounted_price_minor": null, "sku": "BRG-001",
        "barcode": "6221031492818", "is_available": true, "sort_order": 1,
        "option_group_ids": [7] },
      { "id": 102, "category_id": 11, "name_en": "Bad Price Burger",
        "price_minor": 12.5 }
    ], "deleted_ids": [], "complete": true },
    "option_groups": { "data": [
      { "id": 7, "name_en": "Extras", "is_required": false, "max_select": 3,
        "is_variant": false, "sort_order": 1, "options": [
          { "id": 71, "name_en": "Cheese", "price_delta_minor": 1500,
            "is_available": true, "sort_order": 1 },
          { "id": 72, "name_en": "No onions", "price_delta_minor": 0 }
        ] }
    ], "deleted_ids": [], "complete": false }
  },
  "tables": [
    { "id": 12, "branch_id": 3, "label": "T1", "seats": 4, "is_active": true },
    { "id": 13, "branch_id": 3, "label": "T2", "seats": 0 }
  ],
  "staff": [
    { "id": 9, "name": "Sara Aly", "username": "sara", "is_active": true,
      "capabilities": ["pos.operate", "pos.shift_open", "pos.reprint"],
      "pin": { "algorithm": "pbkdf2_sha256", "iterations": 120000,
               "salt": "c2FsdHNhbHRzYWx0c2E=", "hash": "aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaGhhc2g=" } },
    { "id": 10, "name": "No Pin", "username": "nopin", "pin": null }
  ],
  "receipt_profiles": [
    { "branch_id": 3,
      "trade_name": "Koshary House LLC",
      "registration_number": "123456789",
      "activity_code": "5610",
      "branch_code": "0042",
      "country": "EG",
      "governate": "Cairo",
      "region_city": "Maadi",
      "street": "Road 9",
      "building_number": "12",
      "postal_code": "", "floor": "", "room": "", "landmark": "",
      "additional_info": "",
      "phone": "+201000000001",
      "header_note": "Welcome",
      "footer_note": "Wifi: guest",
      "revision": 3 },
    { "branch_id": 9,
      "trade_name": "Demo Grill",
      "registration_number": "123456789",
      "activity_code": "", "branch_code": "",
      "country": "EG",
      "governate": "", "region_city": "", "street": "", "building_number": "",
      "postal_code": "", "floor": "", "room": "", "landmark": "",
      "additional_info": "", "phone": "",
      "header_note": null, "footer_note": null,
      "revision": 0 },
    { "trade_name": "Nobody's Branch", "revision": 4 }
  ],
  "money": {
    "tax_rules": [ { "id": 1, "name": "VAT", "rate_bp": 1400, "mode": "exclusive" } ],
    "charges": [], "tender_types": [ { "id": 1, "name": "Cash", "kind": "cash" } ]
  },
  "invoice": { "prefix_source": "branch_code", "padding": 6, "reset": "yearly" },
  "licence": { "payload": "cGF5bG9hZA", "signature": "c2ln", "key_id": "v1" }
}
''';

void main() {
  group('BootstrapBundle.tryParse', () {
    final bundle = BootstrapBundle.tryParse(jsonDecode(_fixture))!;

    test('reads the identity block and the precedence signal', () {
      expect(bundle.configVersion, 7);
      expect(bundle.business!.id, 42);
      expect(bundle.business!.slug, 'demo');
      expect(bundle.business!.currency, 'EGP');
      expect(bundle.business!.exponent, 2);
      expect(bundle.terminal!.id, '0c9adf1e-9e3f-4a2e-b8a5-6a1f6f0f2f10');
      expect(bundle.terminal!.branchId, 3);
      expect(bundle.seedable, isTrue);
    });

    test('reads branches, tolerating a null code', () {
      expect(bundle.branches, hasLength(2));
      expect(bundle.branches.first.code, 'MAADI');
      expect(bundle.branches.first.supportedOrderTypes, ['dine_in', 'takeaway']);
      expect(bundle.branches.last.code, isNull);
    });

    test('drops a product whose price is a JSON float, keeps the rest', () {
      // 12.5 is the exact bug class D1 exists to prevent. The product is
      // dropped whole; a wrong price is worse than a missing tile.
      expect(bundle.products, hasLength(1));
      expect(bundle.products.single.id, 101);
      expect(bundle.products.single.priceMinor, 9500);
      expect(bundle.products.single.optionGroupIds, [7]);
    });

    test('reads option groups with nested options', () {
      final group = bundle.optionGroups.single;
      expect(group.id, 7);
      expect(group.maxSelect, 3);
      expect(group.options, hasLength(2));
      expect(group.options.first.priceDeltaMinor, 1500);
    });

    test('reads a zero-seat table as "not stated" instead of tripping the CHECK constraint', () {
      expect(bundle.tables, hasLength(2));
      expect(bundle.tables.last.seats, isNull);
    });

    test('reads staff PIN verifiers and tolerates their absence', () {
      final sara = bundle.staff.first;
      expect(sara.pin, isNotNull);
      expect(sara.pin!.iterations, 120000);
      expect(sara.capabilities, contains('pos.shift_open'));
      expect(bundle.staff.last.pin, isNull);
    });

    test('carries money and licence blocks through unparsed', () {
      expect((bundle.money['tax_rules'] as List), hasLength(1));
      expect(bundle.licence!['key_id'], 'v1');
    });

    test('reads a receipt profile per branch, and drops the row with no branch',
        () {
      // A3's contract: one row per ACTIVE branch, authored or not. The third
      // fixture row names no branch, which is the one field nothing can be
      // keyed on — dropped, and the other two kept.
      expect(bundle.receiptProfiles.map((p) => p.branchId), [3, 9]);

      final maadi = bundle.receiptProfiles.first;
      expect(maadi.tradeName, 'Koshary House LLC');
      expect(maadi.registrationNumber, '123456789');
      expect(maadi.activityCode, '5610');
      // ETA's branch code, not the invoice prefix: `branches[0].code` is
      // 'MAADI' in the same fixture and this is '0042'. Reading the wrong one
      // would file every receipt under a branch the authority never issued.
      expect(maadi.branchCode, '0042');
      expect(maadi.address.governate, 'Cairo');
      expect(maadi.address.regionCity, 'Maadi');
      expect(maadi.address.street, 'Road 9');
      expect(maadi.address.buildingNumber, '12');
      expect(maadi.phone, '+201000000001');
      expect(maadi.headerNote, 'Welcome');
      expect(maadi.footerNote, 'Wifi: guest');
      expect(maadi.revision, 3);
      expect(maadi.canFile, isTrue, reason: 'the till still judges this');
    });

    test('an unauthored branch arrives as a projection, not as nothing', () {
      // The bug this key closes: a missing row sent that till back to
      // `ReceiptProfile(branchId: 0)` and printed compiled-in defaults.
      final zamalek = bundle.receiptProfiles.last;
      expect(zamalek.revision, 0, reason: 'nobody has authored this branch');
      expect(zamalek.tradeName, 'Demo Grill');
      expect(zamalek.canPrint, isTrue, reason: 'enough to hand somebody paper');
      expect(zamalek.canFile, isFalse);
      // Empty strings on the way in, nulls on the two notes — the columns'
      // own shapes, so the seeder needs no translation.
      expect(zamalek.address.street, '');
      expect(zamalek.headerNote, isNull);
      expect(zamalek.footerNote, isNull);
      expect(zamalek.address.postalCode, isNull);
    });

    test('reads the payment methods out of the money block', () {
      final cash = bundle.tenderTypes.single;
      expect(cash.id, 1);
      expect(cash.name, 'Cash');
      expect(cash.kind, PlatformTenderKind.cash);
      expect(cash.isActive, isTrue, reason: 'absent means active');
    });
  });

  group('payment methods', () {
    test('tolerate what the platform may send and drop what they cannot', () {
      final bundle = BootstrapBundle(
        configVersion: 1,
        money: {
          'tender_types': [
            {'id': 5, 'name': 'Bank terminal', 'kind': 'external',
             'is_active': false, 'sort_order': 3},
            {'id': 6, 'name': 'Crypto', 'kind': 'crypto'},
            {'id': '7', 'kind': 'card'},
            {'id': 8, 'name': 'InstaPay', 'kind': 'wallet'},
            {'name': 'No id', 'kind': 'cash'},
            'not a map',
          ],
        },
      );
      final tenders = bundle.tenderTypes;
      expect(tenders.map((t) => t.id), [5, 6, 7, 8],
          reason: 'no id is the one thing nothing can be keyed on');
      expect(tenders[0].kind, PlatformTenderKind.external);
      expect(tenders[0].isActive, isFalse);
      expect(tenders[0].sortOrder, 3);
      expect(tenders[1].kind, isNull, reason: 'unknown, and still takeable');
      expect(tenders[2].name, 'Payment method 7');
      expect(tenders[3].kind, PlatformTenderKind.wallet,
          reason: 'the platform has a wallet kind (2026-10-26)');
      expect(tenders[3].kind!.tillKind, TenderKind.wallet);
    });

    test('a bundle without them has none, and does not throw', () {
      expect(const BootstrapBundle(configVersion: 1).tenderTypes, isEmpty);
      expect(
        const BootstrapBundle(
          configVersion: 1,
          money: {'tender_types': 'nonsense'},
        ).tenderTypes,
        isEmpty,
      );
    });
  });

  group('tolerance', () {
    test('an empty document parses to an empty, unseedable bundle', () {
      final bundle = BootstrapBundle.tryParse(const <String, Object?>{})!;
      expect(bundle.seedable, isFalse);
      expect(bundle.configVersion, 0);
      expect(bundle.products, isEmpty);
      expect(bundle.staff, isEmpty);
    });

    test('a non-map body is null, never a throw', () {
      expect(BootstrapBundle.tryParse('nonsense'), isNull);
      expect(BootstrapBundle.tryParse(null), isNull);
      expect(BootstrapBundle.tryParse([1, 2, 3]), isNull);
    });

    test('a platform that predates receipt profiles sends none, and parses',
        () {
      // Every deployment before 22 Sep 2026 sends no `receipt_profiles` key at
      // all, and garbage must read the same way: empty, so the seeder leaves
      // the table it already printed from alone.
      final absent = BootstrapBundle.tryParse({'config_version': 1})!;
      expect(absent.receiptProfiles, isEmpty);

      final rubbish = BootstrapBundle.tryParse({
        'config_version': 1,
        'receipt_profiles': 'nonsense',
      })!;
      expect(rubbish.receiptProfiles, isEmpty);

      final mixed = BootstrapBundle.tryParse({
        'config_version': 1,
        'receipt_profiles': [
          'not a map',
          {'branch_id': 'four', 'trade_name': 'Unkeyable'},
          {'branch_id': '5', 'country': null, 'revision': 'two'},
        ],
      })!;
      // A numeric string branch id is tolerated (the same PHP path the rest of
      // the bundle allows for); an unparseable one is not.
      expect(mixed.receiptProfiles.single.branchId, 5);
      expect(
        mixed.receiptProfiles.single.address.country,
        'EG',
        reason: 'a blank country is never the right answer',
      );
      expect(mixed.receiptProfiles.single.revision, 0);
    });

    test('catalog collections parse from a bare list too', () {
      // The delta-sync envelope and a plain array must both work, so the
      // bundle and the standalone catalog endpoints can share one reader.
      final bundle = BootstrapBundle.tryParse({
        'config_version': 1,
        'catalog': {
          'categories': [
            {'id': 1, 'name_en': 'Drinks'},
          ],
        },
      })!;
      expect(bundle.categories.single.nameEn, 'Drinks');
    });

    test('a menu named in Arabic only is a menu, not nothing', () {
      // The platform lets a business name its menu in one language; the
      // dashboard and the diner's menu resolve by locale and fall back. The
      // till required `name_en` and dropped every row without one — every
      // category, then every item under them — and opened its sale screen on
      // "no matching items" over a menu of forty-six (Good Cafe, 16 Oct 2026).
      final bundle = BootstrapBundle.tryParse({
        'config_version': 1,
        'catalog': {
          'categories': {
            'data': [
              {'id': 73, 'name_en': null, 'name_ar': 'Iced Coffee'},
              {'id': 74, 'name_ar': 'فرابتشينو'},
              // Nameless in both: the one row nothing can be sold under.
              {'id': 75, 'name_en': null, 'name_ar': ''},
            ],
          },
          'items': {
            'data': [
              {'id': 1, 'category_id': 73, 'name_ar': 'كراميل', 'price_minor': 13000},
            ],
          },
          'option_groups': {
            'data': [
              {
                'id': 7,
                'name_ar': 'الحجم',
                'options': [
                  {'id': 71, 'name_ar': 'كبير', 'price_delta_minor': 1000},
                ],
              },
            ],
          },
        },
      })!;

      expect(bundle.categories.map((c) => c.id), [73, 74]);
      expect(bundle.categories.first.nameEn, 'Iced Coffee');
      expect(bundle.categories.first.nameAr, 'Iced Coffee');
      expect(bundle.categories.last.nameEn, 'فرابتشينو');
      expect(bundle.products.single.nameEn, 'كراميل');
      expect(bundle.optionGroups.single.nameEn, 'الحجم');
      expect(bundle.optionGroups.single.options.single.nameEn, 'كبير');
    });
  });
}
