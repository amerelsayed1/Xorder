import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/data/backup/backup_service.dart';
import 'package:xorder_pos/data/backup/pg_tools.dart';
import 'package:xorder_pos/domain/models/backup.dart';

/// The parts of the backup that need no database and no screen.
///
/// **No `POS_PG_HOST` guard here, deliberately**, unlike the round-trip suite
/// next to it. Parsing `pg_restore --list` and deciding where copies go are the
/// two pieces most likely to be quietly broken by a client upgrade or a port to
/// Windows, and a check that only runs on a machine with PostgreSQL installed is
/// a check that does not run on the machine that breaks it.
void main() {
  group('reading a table of contents', () {
    // Verbatim from `pg_restore --list` on a real dump of this schema. Kept as
    // a fixture rather than generated, because the thing under test IS the
    // shape of PostgreSQL's output and generating it from our own assumptions
    // would test nothing.
    const toc = '''
;
; Archive created at 2026-09-09 01:14:07 EEST
;     dbName: xorder_pos
;     TOC Entries: 312
;
;
; Selected TOC Entries:
;
215; 1259 16419 TABLE public pos_orders amerelsayed
216; 1259 16430 TABLE public pos_order_lines amerelsayed
217; 1259 16441 SEQUENCE public pos_orders_id_seq amerelsayed
3462; 0 16419 TABLE DATA public pos_orders amerelsayed
3463; 0 16430 TABLE DATA public pos_order_lines amerelsayed
3470; 2606 16500 CONSTRAINT public pos_orders pos_orders_pkey amerelsayed
3471; 1259 16512 INDEX public pos_orders_tenant_idx amerelsayed
''';

    test('it finds the tables, and is not fooled by the data entries', () {
      final tables = BackupService.tablesIn(toc);

      expect(tables, contains('pos_orders'));
      expect(tables, contains('pos_order_lines'));
      // `TABLE DATA public pos_orders` must resolve to the table, not to the
      // word "public" — which is what a regex that stopped at the first token
      // after TABLE would give, and it would have made every archive look
      // like it contained one table called `public`.
      expect(tables, isNot(contains('public')));
      expect(tables, isNot(contains('DATA')));
    });

    test('a sequence, a constraint and an index are not tables', () {
      final tables = BackupService.tablesIn(toc);
      expect(tables, isNot(contains('pos_orders_id_seq')));
      expect(tables, isNot(contains('pos_orders_pkey')));
      expect(tables, isNot(contains('pos_orders_tenant_idx')));
    });

    test('an empty or unreadable listing yields nothing, rather than throwing',
        () {
      // The caller treats "no tables" as "not a backup". Throwing here would
      // turn a bad archive into a crash at midnight.
      expect(BackupService.tablesIn(''), isEmpty);
      expect(BackupService.tablesIn('pg_restore: error: bad magic'), isEmpty);
    });
  });

  group('the tables verification insists on', () {
    test('they are the ones a restaurant could not trade without', () {
      // Not every table — the question is whether the restaurant could trade
      // and answer a tax audit from this file.
      expect(
        BackupService.essentialTables,
        containsAll(<String>[
          'pos_orders',
          'pos_order_payments',
          'pos_shifts',
          'pos_audit_events',
        ]),
      );
    });
  });

  group('where copies go', () {
    test('the default is absolute, and it is a backups folder', () {
      final path = BackupPaths.defaultDirectory();
      expect(path, endsWith('backups'));
      expect(
        path,
        Platform.isWindows ? contains(':\\') : startsWith('/'),
      );
    });

    test('a configured folder wins', () {
      expect(
        BackupPaths.resolve(const BackupPolicy(directory: '/mnt/usb/copies')),
        '/mnt/usb/copies',
      );
    });

    test('and a blank one falls back rather than writing to nowhere', () {
      // `''` as a directory would put the dump in the process's working
      // directory, which on a packaged Windows build is Program Files.
      expect(
        BackupPaths.resolve(const BackupPolicy(directory: '   ')),
        BackupPaths.defaultDirectory(),
      );
      expect(
        BackupPaths.resolve(BackupPolicy.defaults),
        BackupPaths.defaultDirectory(),
      );
    });
  });

  group('finding pg_dump', () {
    test('the search list is PATH plus the places an installer actually uses',
        () {
      final places = PgTools.searchPath();
      expect(places, isNotEmpty);
      expect(
        places.where((p) => p.trim().isEmpty),
        isEmpty,
        reason: 'an empty PATH entry means the current directory',
      );

      // Per-OS, and the point of the list is that it goes beyond PATH: a
      // Windows install puts pg_dump in Program Files and never on PATH.
      final expected = Platform.isWindows
          ? r'PostgreSQL\17\bin'
          : (Platform.isMacOS ? 'postgresql@17' : '/usr/lib/postgresql/17/bin');
      expect(places.where((p) => p.contains(expected)), isNotEmpty);
    });
  });
}
