import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/postgres/local_bootstrap.dart';

/// What a till's database role is allowed to do, asserted on the statements
/// themselves so it holds without a server.
///
/// The finding behind this file: the till role was granted INSERT/UPDATE on
/// `pos_staff` and INSERT/UPDATE/DELETE on the whole catalogue, unconditionally.
/// That is what `BootstrapSeeder` needs to replace the local cache with the
/// platform's copy, and on a cloud till it is defensible — the cache is not
/// authoritative, every order is re-priced server-side, so rewriting the
/// display buys an attacker nothing at settlement.
///
/// An offline till has no server-side second opinion. Its database IS the
/// restaurant. The same grants there mean a till password recovered from the
/// machine (or off the LAN) can reprice the menu for real, and can point a
/// staff row at the owner role — reaching Management without ever knowing the
/// administrator's password. The seeder never runs offline, so the grants were
/// pure attack surface.
void main() {
  List<String> grants({required bool cloudSeeding}) => LocalBootstrap.tillGrants(
    database: 'xorder_pos',
    role: 'pos_till',
    cloudSeeding: cloudSeeding,
  );

  /// Statements that HAND [table] anything other than SELECT. `REVOKE …` is
  /// excluded deliberately — it names the same verbs while doing the opposite,
  /// and counting it as a write is how this file would pass while the grant
  /// list handed out everything it claims to withhold.
  Iterable<String> writesTo(List<String> statements, String table) =>
      statements.where(
        (s) =>
            s.startsWith('GRANT') &&
            s.contains(table) &&
            (s.contains('INSERT') ||
                s.contains('UPDATE') ||
                s.contains('DELETE')),
      );

  Iterable<String> revokes(List<String> statements) =>
      statements.where((s) => s.startsWith('REVOKE'));

  group('an offline till', () {
    final offline = grants(cloudSeeding: false);

    test('cannot write the menu', () {
      for (final table in [
        'pos_categories',
        'pos_products',
        'pos_modifier_groups',
        'pos_modifiers',
        'pos_product_modifier_groups',
        'pos_modifier_group_categories',
      ]) {
        expect(
          writesTo(offline, table),
          isEmpty,
          reason: '$table is authored over the ADMIN credential, not this one',
        );
      }
    });

    test('cannot write staff, which is how it would reach Management', () {
      expect(writesTo(offline, 'pos_staff'), isEmpty);
    });

    test('cannot write the restaurant or its branches', () {
      expect(writesTo(offline, 'pos_restaurants'), isEmpty);
      expect(writesTo(offline, 'pos_branches'), isEmpty);
    });

    test('still reads everything a sale screen needs', () {
      expect(
        offline.any(
          (s) => s.startsWith('GRANT SELECT ON pos_restaurants, pos_branches'),
        ),
        isTrue,
      );
    });

    test('still sells: orders, payments, shifts and the invoice counter', () {
      expect(
        writesTo(offline, 'pos_orders'),
        isNotEmpty,
        reason: 'a till that cannot insert an order is not a till',
      );
      expect(writesTo(offline, 'pos_order_payments'), isNotEmpty);
      expect(writesTo(offline, 'pos_shifts'), isNotEmpty);
      expect(writesTo(offline, 'pos_invoice_sequences'), isNotEmpty);
      expect(
        writesTo(offline, 'pos_parked_tickets'),
        isNotEmpty,
        reason: 'seating and settling a table both write here',
      );
    });

    test('can read back every table order history joins', () {
      // History is a read, but it is a read across six tables. A missing SELECT
      // on any one of them is a screen that throws a permission error at
      // whoever opened it — and it would not show up in a suite run as the
      // superuser, because a superuser needs no grant at all.
      Iterable<String> readsOf(String table) => offline.where(
        (s) =>
            s.startsWith('GRANT') && s.contains('SELECT') && s.contains(table),
      );

      for (final table in [
        'pos_orders',
        'pos_order_lines',
        'pos_order_payments',
        'pos_order_discounts',
        'pos_reason_codes',
        'pos_staff',
      ]) {
        expect(readsOf(table), isNotEmpty, reason: 'history joins $table');
      }
    });

    test('can record a refund, and cannot touch either counter', () {
      // The refund tables need INSERT. The two counters do NOT: migration 12
      // maintains them from a SECURITY DEFINER trigger, so the number and the
      // refund row it summarises cannot disagree. A grant here would put that
      // back under the till's own hand.
      expect(writesTo(offline, 'pos_refunds'), isNotEmpty);
      expect(writesTo(offline, 'pos_refund_lines'), isNotEmpty);
      expect(writesTo(offline, 'pos_refund_payments'), isNotEmpty);

      final orderUpdates = offline.where(
        (s) => s.startsWith('GRANT UPDATE') && s.contains('pos_orders'),
      );
      for (final grant in orderUpdates) {
        expect(
          grant.contains('refunded_minor'),
          isFalse,
          reason: 'the trigger owns this counter, not the till',
        );
      }

      final lineUpdates = offline.where(
        (s) => s.startsWith('GRANT UPDATE') && s.contains('pos_order_lines'),
      );
      for (final grant in lineUpdates) {
        expect(grant.contains('refunded_quantity'), isFalse);
      }
    });

    test('never gets UPDATE or DELETE on a refund', () {
      // A refund already given is a record of money that left the drawer.
      // Correcting one is a second refund, not an edit of the first.
      for (final table in [
        'pos_refunds',
        'pos_refund_lines',
        'pos_refund_payments',
      ]) {
        final grants = offline.where(
          (s) => s.startsWith('GRANT') && s.contains(table),
        );
        for (final grant in grants) {
          expect(grant.contains('UPDATE'), isFalse, reason: table);
          expect(grant.contains('DELETE'), isFalse, reason: table);
        }
      }
    });

    test('takes the writes away from an install that already had them', () {
      // Upgrade, not just a new default. Every offline branch server built
      // before the split was granted the seeding block; a list that only ever
      // adds would leave them permissive forever.
      final taken = revokes(offline);
      expect(taken, isNotEmpty);
      expect(
        taken.any((s) => s.contains('pos_staff') && s.contains('pos_products')),
        isTrue,
      );
      expect(
        revokes(grants(cloudSeeding: true)),
        isEmpty,
        reason: 'a cloud till needs them; taking them back would break sync',
      );
    });

    test('never gets DELETE on a sale or on the audit ledger', () {
      for (final statement in offline.where(
        (s) => s.startsWith('GRANT') && s.contains('DELETE'),
      )) {
        expect(
          statement,
          contains('pos_parked_tickets'),
          reason: 'the parked ticket is the only row a till may remove',
        );
      }
      expect(
        offline.any((s) => s.contains('UPDATE') && s.contains('pos_audit_events')),
        isFalse,
      );
    });
  });

  group('a cloud till', () {
    final cloud = grants(cloudSeeding: true);

    test('gets the seeding writes, because BootstrapSeeder needs them', () {
      expect(writesTo(cloud, 'pos_products'), isNotEmpty);
      expect(writesTo(cloud, 'pos_staff'), isNotEmpty);
      expect(writesTo(cloud, 'pos_categories'), isNotEmpty);
      // Granted with the rest of the catalogue so the seeder can be taught to
      // write it, though today it only goes by cascade — see `_seedCatalog`.
      expect(writesTo(cloud, 'pos_modifier_group_categories'), isNotEmpty);
    });

    test('holds every grant the offline set holds, and more', () {
      final offlineGrants =
          grants(cloudSeeding: false).where((s) => s.startsWith('GRANT'));
      expect(cloud, containsAll(offlineGrants));
      expect(cloud.length, greaterThan(offlineGrants.length));
    });
  });

  test('the safe answer is the default', () {
    // Anybody adding a third caller and forgetting the parameter gets the
    // offline set, which cannot escalate. The opposite default would make an
    // omission silently permissive.
    expect(
      LocalBootstrap.tillGrants(database: 'xorder_pos', role: 'pos_till'),
      grants(cloudSeeding: false),
    );
  });
}
