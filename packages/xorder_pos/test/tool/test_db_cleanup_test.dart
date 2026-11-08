import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_db_cleanup.dart';
import '../data/pg_fixture.dart';

/// The rules behind `tool/drop_test_databases.dart`, which runs `DROP DATABASE`.
/// Every claim is about a name it must NOT touch, because a wrong match here
/// cannot be undone.
void main() {
  const tag = '47ecbf8e';

  group('which databases it may drop', () {
    test('this checkout\'s per-suite and shared test databases', () {
      for (final name in [
        'xorder_pos_refunds_$tag',
        'xorder_pos_cloud_receipt_profile_$tag',
        'xorder_pos_eta_filer_$tag',
        'xorder_pos_test_$tag',
        'xorder_pos_pg_archive_source_$tag',
      ]) {
        expect(isTestDatabase(name, tag), isTrue, reason: name);
      }
    });

    test('never the real till database, or anything without this tag', () {
      for (final name in [
        'xorder_pos', // the real one: the source of the backup
        'xorder_pos_$tag', // no suite: not what the fixture builds
        'aziz_db',
        'postgres',
        'template1',
        'xorder_pos_refunds_9309f7c3', // another checkout
        'xorder_pos_refunds_${tag}x',
        'xorder_pos_refunds_${tag.toUpperCase()}',
        'my_xorder_pos_refunds_$tag',
        'xorder_pos_refunds_$tag; DROP DATABASE aziz_db',
        'xorder_pos_refunds_$tag-old',
        '',
      ]) {
        expect(isTestDatabase(name, tag), isFalse, reason: name);
      }
    });

    test('another checkout\'s tag is its own, never a wildcard', () {
      expect(isTestDatabase('xorder_pos_refunds_9309f7c3', '9309f7c3'), isTrue);
      expect(isTestDatabase('xorder_pos_refunds_$tag', '9309f7c3'), isFalse);
    });

    test('a malformed tag matches nothing', () {
      for (final bad in [
        '',
        '.*',
        '47ecbf8',
        '47ecbf8e9',
        '47ECBF8E',
        'zzzzzzzz',
      ]) {
        expect(isCheckoutTag(bad), isFalse, reason: bad);
        expect(isTestDatabase('xorder_pos_refunds_$tag', bad), isFalse);
        expect(isTestRole('xorder_test_install_admin_$tag', bad), isFalse);
      }
    });
  });

  group('which roles it may drop', () {
    test('this checkout\'s test roles only', () {
      expect(isTestRole('xorder_test_install_admin_$tag', tag), isTrue);
      for (final name in [
        'pos_till',
        'postgres',
        'amerelsayed',
        'xorder_test_install_admin_9309f7c3',
        'xorder_test_$tag',
        'xorder_pos_refunds_$tag',
      ]) {
        expect(isTestRole(name, tag), isFalse, reason: name);
      }
    });
  });

  group('where it may run', () {
    test('this machine is local, a named server is not', () {
      for (final host in [
        '127.0.0.1',
        'localhost',
        '::1',
        '[::1]',
        ' LOCALHOST ',
      ]) {
        expect(isLocalHost(host), isTrue, reason: host);
      }
      for (final host in ['10.0.0.5', 'db.example.com', '192.168.1.20', '']) {
        expect(isLocalHost(host), isFalse, reason: host);
      }
    });

    test('identifiers it will quote are plain', () {
      expect(isPlainIdentifier('xorder_pos_refunds_$tag'), isTrue);
      for (final bad in ['a"b', 'a b', 'a;b', 'A', '', 'x' * 64]) {
        expect(isPlainIdentifier(bad), isFalse, reason: bad);
      }
    });
  });

  test('its tag is the fixture\'s tag, so it finds what the suites made', () {
    // PgFixture hashes the same working directory; if either algorithm drifts
    // this fails instead of the cleanup silently matching nothing (or, worse,
    // something else).
    expect(
      'xorder_pos_test_${checkoutTag(Directory.current.path)}',
      PgFixture.sharedName,
    );
  });
}
