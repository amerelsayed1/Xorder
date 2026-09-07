import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/cloud/bootstrap_bundle.dart';

/// A representative bundle, shaped exactly as the agreed POS-BE-023 contract
/// serialises it. If the backend changes a key, this fixture is where the
/// disagreement surfaces — before a till in a restaurant does.
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
      expect(bundle.restaurant!.id, 42);
      expect(bundle.restaurant!.slug, 'demo');
      expect(bundle.restaurant!.currency, 'EGP');
      expect(bundle.restaurant!.exponent, 2);
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

    test('clamps a zero-seat table instead of tripping the CHECK constraint', () {
      expect(bundle.tables, hasLength(2));
      expect(bundle.tables.last.seats, 2);
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
  });
}
