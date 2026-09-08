import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/domain/services/eta_serialization.dart';

/// The bytes Egypt's tax authority hashes.
///
/// Every one of these is a rule from ETA's published serialization approach,
/// and each is the kind that fails silently: get the uppercasing, the repeated
/// array name or the verbatim values wrong and nothing breaks locally — the
/// receipt just comes back rejected with a signature error that says nothing
/// about which rule was missed.
void main() {
  String canonical(EtaObject document) => EtaSerializer.canonical(document);

  group('the algorithm', () {
    test('a property name is uppercased and quoted', () {
      expect(
        canonical(const EtaObject([('receiptNumber', EtaText('INV-1'))])),
        '"RECEIPTNUMBER""INV-1"',
      );
    });

    test('values are not uppercased', () {
      // The name is theirs; the value is the restaurant's.
      expect(
        canonical(const EtaObject([('name', EtaText('Koshari'))])),
        '"NAME""Koshari"',
      );
    });

    test('a value is emitted verbatim — 0.0 does not become 0', () {
      // Their spec calls this out by name. A number that went through a Dart
      // `double` on the way here would arrive as `0.0` or `0` unpredictably,
      // and the hash would differ from the one the authority computes.
      expect(
        canonical(const EtaObject([('a', EtaText('0.0'))])),
        '"A""0.0"',
      );
      expect(
        canonical(const EtaObject([('a', EtaText('0.00'))])),
        '"A""0.00"',
      );
    });

    test('nested objects recurse with the same rules', () {
      expect(
        canonical(
          const EtaObject([
            (
              'seller',
              EtaObject([('rin', EtaText('123456789'))]),
            ),
          ]),
        ),
        '"SELLER""RIN""123456789"',
      );
    });

    test('an array names itself once, then again before each element', () {
      // The rule that is easiest to get wrong and hardest to notice. Without
      // the repeat, a one-element array serialises identically to the bare
      // object it contains.
      expect(
        canonical(
          const EtaObject([
            (
              'itemData',
              EtaArray([
                EtaObject([('description', EtaText('A'))]),
                EtaObject([('description', EtaText('B'))]),
              ]),
            ),
          ]),
        ),
        '"ITEMDATA"'
        '"ITEMDATA""DESCRIPTION""A"'
        '"ITEMDATA""DESCRIPTION""B"',
      );
    });

    test('a one-element array is distinguishable from the bare object', () {
      final wrapped = canonical(
        const EtaObject([
          (
            'itemData',
            EtaArray([
              EtaObject([('description', EtaText('A'))]),
            ]),
          ),
        ]),
      );
      final bare = canonical(
        const EtaObject([
          (
            'itemData',
            EtaObject([('description', EtaText('A'))]),
          ),
        ]),
      );
      expect(wrapped, isNot(bare));
    });

    test('an empty array contributes its name and nothing else', () {
      expect(
        canonical(const EtaObject([('taxTotals', EtaArray([]))])),
        '"TAXTOTALS"',
      );
    });

    test('the output is one line — no whitespace anywhere', () {
      final text = canonical(
        const EtaObject([
          ('a', EtaText('1')),
          (
            'b',
            EtaObject([('c', EtaText('2'))]),
          ),
        ]),
      );
      expect(text, isNot(contains(' ')));
      expect(text, isNot(contains('\n')));
    });

    test('field order is part of the document, not incidental', () {
      final one = canonical(
        const EtaObject([('a', EtaText('1')), ('b', EtaText('2'))]),
      );
      final other = canonical(
        const EtaObject([('b', EtaText('2')), ('a', EtaText('1'))]),
      );
      expect(one, isNot(other));
    });

    test('an array of arrays is refused rather than guessed at', () {
      // Not reachable from any receipt shape ETA publishes. A silent wrong
      // answer here would be a rejected signature with nothing to point at.
      expect(
        () => canonical(
          const EtaObject([
            (
              'a',
              EtaArray([
                EtaArray([EtaText('x')]),
              ]),
            ),
          ]),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('the uuid', () {
    EtaObject receipt({String uuid = ''}) => EtaObject([
      (
        'header',
        EtaObject([
          ('receiptNumber', const EtaText('INV-1')),
          ('uuid', EtaText(uuid)),
          ('previousUUID', const EtaText('')),
        ]),
      ),
      ('totalAmount', const EtaText('45.00')),
    ]);

    test('is sixty-four lowercase hex characters', () {
      final uuid = EtaSerializer.uuidOf(receipt());
      expect(uuid, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(uuid), isTrue);
    });

    test('is the SHA-256 of the canonical text without the uuid field', () {
      final document = receipt();
      final withoutUuid = EtaObject([
        (
          'header',
          EtaObject([
            ('receiptNumber', const EtaText('INV-1')),
            ('previousUUID', const EtaText('')),
          ]),
        ),
        ('totalAmount', const EtaText('45.00')),
      ]);

      expect(
        EtaSerializer.uuidOf(document),
        sha256.convert(utf8.encode(canonical(withoutUuid))).toString(),
      );
    });

    test('does not depend on what the uuid field already held', () {
      // A value cannot be part of what it is derived from. If it were, a
      // recomputation would never reach a fixed point.
      expect(
        EtaSerializer.uuidOf(receipt()),
        EtaSerializer.uuidOf(receipt(uuid: 'whatever-was-there')),
      );
    });

    test('changing any other field changes it', () {
      final one = EtaSerializer.uuidOf(receipt());
      final other = EtaSerializer.uuidOf(
        EtaObject([
          (
            'header',
            EtaObject([
              ('receiptNumber', const EtaText('INV-2')),
              ('uuid', const EtaText('')),
              ('previousUUID', const EtaText('')),
            ]),
          ),
          ('totalAmount', const EtaText('45.00')),
        ]),
      );
      expect(one, isNot(other));
    });
  });

  group('the JSON that is submitted', () {
    test('comes from the same tree that was hashed', () {
      // The point of the whole design. Two builders would drift by one field
      // and every signature would be rejected, with an error that says
      // nothing about which half is stale.
      const document = EtaObject([
        (
          'header',
          EtaObject([('receiptNumber', EtaText('INV-1'))]),
        ),
        (
          'itemData',
          EtaArray([
            EtaObject([('description', EtaText('Koshari'))]),
          ]),
        ),
      ]);

      expect(EtaSerializer.toJson(document), {
        'header': {'receiptNumber': 'INV-1'},
        'itemData': [
          {'description': 'Koshari'},
        ],
      });
    });

    test('keeps property names in their original case', () {
      // Uppercase is for the hash only. Sending `RECEIPTNUMBER` would be
      // rejected as an unknown field.
      final json =
          EtaSerializer.toJson(
                const EtaObject([('previousUUID', EtaText(''))]),
              )
              as Map<String, Object?>;
      expect(json.keys.single, 'previousUUID');
    });

    test('encodes as JSON without surprises', () {
      const document = EtaObject([('name', EtaText('Koshari "Abou" Tarek'))]);
      expect(
        jsonEncode(EtaSerializer.toJson(document)),
        r'{"name":"Koshari \"Abou\" Tarek"}',
      );
    });
  });

  group('editing a document', () {
    const document = EtaObject([('a', EtaText('1')), ('b', EtaText('2'))]);

    test('with_ replaces in place, keeping the order', () {
      final edited = document.with_('a', const EtaText('9'));
      expect(canonical(edited), '"A""9""B""2"');
    });

    test('with_ appends when the field is new', () {
      final edited = document.with_('c', const EtaText('3'));
      expect(canonical(edited), '"A""1""B""2""C""3"');
    });

    test('without removes one field', () {
      expect(canonical(document.without('a')), '"B""2"');
    });

    test('EtaObject.of drops nulls, so an absent field is absent', () {
      // Not present and empty — ETA reads those differently.
      final object = EtaObject.of([
        ('a', const EtaText('1')),
        ('b', null),
      ]);
      expect(canonical(object), '"A""1"');
    });
  });
}
