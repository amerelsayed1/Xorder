import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xorder_pos/data/backup/pg_archive.dart';
import 'package:xorder_pos/data/backup/pg_tools.dart';

/// The rules a copy has to keep before anybody trusts it with a restaurant's
/// only record of its trading. Run against a fake `pg_dump`, so they hold on a
/// machine with no PostgreSQL; `pg_archive_restore_test.dart` runs the real
/// tools end to end.
void main() {
  const tools = PgToolset(
    pgDump: '/pg/pg_dump',
    pgRestore: '/pg/pg_restore',
    version: '16.11',
  );
  const reader = BackupConnection(
    host: 'localhost',
    port: 5432,
    database: 'kashri_altahrir',
    user: 'pos_backup',
    password: 's3cret-backup',
    verifyTls: false,
  );

  late Directory folder;
  setUp(() async => folder = await Directory.systemTemp.createTemp('archive'));
  tearDown(() async {
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  /// A fake `pg_dump` / `pg_restore`: records every call, writes the file
  /// `pg_dump` was asked for, and answers the two reads as a sound archive
  /// would — unless told otherwise.
  ({List<(String, List<String>, Map<String, String>?)> calls, ProcessRunner run})
  fake({
    int dumpExit = 0,
    int listExit = 0,
    int readExit = 0,
    int restoreExit = 0,
    bool missingBinary = false,
  }) {
    final calls = <(String, List<String>, Map<String, String>?)>[];
    Future<ProcessResult> run(
      String exe,
      List<String> args, {
      Map<String, String>? environment,
    }) async {
      calls.add((exe, args, environment));
      if (missingBinary) throw ProcessException(exe, args, 'not found', 2);
      if (exe == tools.pgDump) {
        if (dumpExit == 0) {
          await File(args[args.indexOf('--file') + 1]).writeAsString('PGDMP..');
        }
        return ProcessResult(1, dumpExit, '', dumpExit == 0 ? '' : 'auth failed');
      }
      if (args.contains('--list')) {
        return ProcessResult(
          1,
          listExit,
          listExit == 0 ? '3; 0 16390 TABLE DATA public pos_orders' : '',
          listExit == 0 ? '' : 'not a valid archive',
        );
      }
      if (!args.contains('--dbname')) {
        // The read-back: the whole archive converted and thrown away.
        return ProcessResult(1, readExit, '', readExit == 0 ? '' : 'EOF');
      }
      return ProcessResult(1, restoreExit, '', restoreExit == 0 ? '' : 'boom');
    }

    return (calls: calls, run: run);
  }

  File target() => File(p.join(folder.path, 'kashri_altahrir-20260911-213045.dump'));
  List<String> names() =>
      folder.listSync().map((f) => p.basename(f.path)).toList()..sort();
  Matcher failsWith(ArchiveFailureKind kind) =>
      throwsA(isA<ArchiveFailure>().having((e) => e.kind, 'kind', kind));

  group('taking a copy', () {
    test('the password travels in the environment, never on the command line',
        () async {
      final f = fake();
      await PgArchive(tools, run: f.run).dump(from: reader, to: target());

      final (_, args, env) = f.calls.first;
      // The process table is readable by every account on the machine.
      expect(args.join(' '), isNot(contains('s3cret-backup')));
      expect(env!['PGPASSWORD'], 's3cret-backup');
      // A wrong password fails at once rather than waiting on a prompt.
      expect(args, contains('--no-password'));
      expect(args, contains('--format=custom'));
    });

    test('no password is no PGPASSWORD — an empty one is a wrong one', () {
      const trusted = BackupConnection(
        host: 'localhost',
        port: 5432,
        database: 'x',
        user: 'pos_backup',
        password: '',
        verifyTls: false,
      );
      expect(trusted.environment.containsKey('PGPASSWORD'), isFalse);
    });

    test('encryption follows the till: off only where the till has it off',
        () {
      expect(reader.environment['PGSSLMODE'], 'disable');
      const remote = BackupConnection(
        host: 'db.example',
        port: 5432,
        database: 'x',
        user: 'u',
        verifyTls: true,
      );
      expect(remote.environment['PGSSLMODE'], 'verify-full');
    });

    test('a sound dump is kept under its finished name, and nothing else',
        () async {
      final f = fake();
      final contents = await PgArchive(tools, run: f.run)
          .dump(from: reader, to: target());

      expect(names(), ['kashri_altahrir-20260911-213045.dump']);
      expect(contents, contains('TABLE DATA'));
      // Read back in full before it was given the finished name.
      expect(f.calls[1].$2, ['--list', endsWith('.part')]);
      expect(f.calls[2].$2, ['--file', anything, endsWith('.part')]);
    });

    test('a failed dump leaves nothing that looks like a backup', () async {
      await expectLater(
        PgArchive(tools, run: fake(dumpExit: 1).run)
            .dump(from: reader, to: target()),
        failsWith(ArchiveFailureKind.dumpFailed),
      );
      expect(names(), isEmpty);
    });

    test('a dump pg_restore cannot list is thrown away, not kept', () async {
      // pg_dump said yes and wrote a file. A file nothing can restore from is
      // the most dangerous backup there is: it looks exactly like a good one.
      await expectLater(
        PgArchive(tools, run: fake(listExit: 1).run)
            .dump(from: reader, to: target()),
        failsWith(ArchiveFailureKind.unreadable),
      );
      expect(names(), isEmpty, reason: 'no .dump and no .part left behind');
    });

    test('so is one that lists but does not read to its end', () async {
      // Missing its last few bytes: `--list` is happy with that (measured).
      // Only reading every block finds the missing end.
      final failure = await PgArchive(tools, run: fake(readExit: 1).run)
          .dump(from: reader, to: target())
          .then<ArchiveFailure?>((_) => null, onError: (Object e) => e as ArchiveFailure);

      expect(failure?.kind, ArchiveFailureKind.unreadable);
      expect(failure?.sizeBytes, greaterThan(0), reason: 'what was discarded');
      expect(names(), isEmpty);
    });

    test('tools that will not start are a failure, not a crash', () async {
      await expectLater(
        PgArchive(tools, run: fake(missingBinary: true).run)
            .dump(from: reader, to: target()),
        failsWith(ArchiveFailureKind.dumpFailed),
      );
    });
  });

  group('putting one back', () {
    test('all or nothing, as the owner, over what is there', () async {
      final f = fake();
      final file = target()..writeAsStringSync('PGDMP');

      await PgArchive(tools, run: f.run).restore(from: file, into: reader);

      final (_, args, env) = f.calls.last;
      expect(
        args,
        containsAll([
          '--clean',
          '--if-exists',
          '--no-owner',
          '--single-transaction',
        ]),
      );
      expect(args.last, file.path);
      expect(env!['PGPASSWORD'], 's3cret-backup');
    });

    test('a file that does not list is refused before the database is touched',
        () async {
      final f = fake(listExit: 1);
      final file = target()..writeAsStringSync('junk');

      await expectLater(
        PgArchive(tools, run: f.run).restore(from: file, into: reader),
        failsWith(ArchiveFailureKind.unreadable),
      );
      expect(f.calls.where((c) => c.$2.contains('--dbname')), isEmpty);
    });

    test('so is one that lists but does not read to its end', () async {
      final f = fake(readExit: 1);
      final file = target()..writeAsStringSync('cut');

      await expectLater(
        PgArchive(tools, run: f.run).restore(from: file, into: reader),
        failsWith(ArchiveFailureKind.unreadable),
      );
      expect(f.calls.where((c) => c.$2.contains('--dbname')), isEmpty);
    });

    test('a restore that fails says so', () async {
      final file = target()..writeAsStringSync('PGDMP');
      await expectLater(
        PgArchive(tools, run: fake(restoreExit: 1).run)
            .restore(from: file, into: reader),
        failsWith(ArchiveFailureKind.restoreFailed),
      );
    });
  });

  group('the folder', () {
    test("keeps the newest fourteen of ours and nobody else's", () {
      for (var day = 1; day <= 16; day++) {
        final dd = day.toString().padLeft(2, '0');
        File(p.join(folder.path, 'kashri_altahrir-202608$dd-230000.dump'))
            .writeAsStringSync('old');
      }
      // Another branch's copies share the folder; so do the menu photos.
      File(p.join(folder.path, 'kashri_altahrir_2-20260801-230000.dump'))
          .writeAsStringSync('theirs');
      File(p.join(folder.path, 'menu-photo.jpg')).writeAsStringSync('jpg');

      final gone = PgArchive.prune(
        folder,
        prefix: 'kashri_altahrir-',
        keep: 14,
      );

      expect([for (final f in gone) p.basename(f.path)]..sort(), [
        'kashri_altahrir-20260801-230000.dump',
        'kashri_altahrir-20260802-230000.dump',
      ]);
      expect(names(), contains('kashri_altahrir_2-20260801-230000.dump'));
      expect(names(), contains('menu-photo.jpg'));
      expect(names().where((n) => n.startsWith('kashri_altahrir-')), hasLength(14));
    });

    test('a folder that is not there is nothing to prune', () {
      expect(
        PgArchive.prune(
          Directory(p.join(folder.path, 'nope')),
          prefix: 'x-',
          keep: 14,
        ),
        isEmpty,
      );
    });
  });
}
