import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Windows installer is three files in two languages that must agree, on a
/// platform none of this suite runs on. So they are read as text and checked
/// against each other: the one kind of break that would otherwise only show up
/// on a restaurant's machine.
void main() {
  final ps1 = File('installer/provision.ps1').readAsStringSync();

  /// The script with its comments taken out: what it RUNS. The comments say
  /// why "Administrators" and `trust` are avoided, and must not count as uses.
  final ps1Code = ps1
      .replaceAll(RegExp(r'<#.*?#>', dotAll: true), '')
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .map((line) => line.replaceFirst(RegExp(r'\s#\s.*$'), ''))
      .join('\n');
  final iss = File('installer/xorder-pos.iss').readAsStringSync();
  final migrate = File('bin/pos_migrate.dart').readAsStringSync();
  final pgTools = File('lib/data/backup/pg_tools.dart').readAsStringSync();

  test('every flag the provisioning script passes, pos_migrate accepts', () {
    final flags = {
      for (final m in RegExp(r"'--([a-z-]+)'").allMatches(ps1)) m.group(1)!,
    };
    expect(flags, containsAll(['create-roles', 'owner', 'no-migrate']));
    for (final flag in flags) {
      expect(
        migrate,
        contains("'$flag'"),
        reason: 'provision.ps1 passes --$flag; pos_migrate would refuse it',
      );
    }
  });

  test('the service the installer stops is the one the script registers', () {
    final iss_ = RegExp(r'#define DbService "([^"]+)"').firstMatch(iss)!;
    final ps1_ = RegExp(r"\$Service\s*=\s*'([^']+)'").firstMatch(ps1)!;
    expect(ps1_.group(1), iss_.group(1));
  });

  test('the files land where the script and the Backup screen look', () {
    // provision.ps1 runs pgsql\bin and tools\pos_migrate.exe under {app};
    // PgTools looks beside the executable for pgsql/bin first.
    expect(iss, contains(r'DestDir: "{app}\pgsql"'));
    expect(iss, contains(r'DestDir: "{app}\tools"'));
    expect(ps1, contains(r"'pgsql\bin'"));
    expect(ps1, contains(r"'tools\pos_migrate.exe'"));
    expect(pgTools, contains(r'pgsql${Platform.pathSeparator}bin'));
  });

  test('the upgrade identity never changes', () {
    // Windows knows a later installer is an upgrade by this id alone. A new
    // one would install a second copy beside the first.
    expect(iss, contains('AppId={{6B0C8F3E-2B6A-4F43-9C8D-58E4A1B7D9C2}'));
  });

  test('passwords reach pos_migrate through the environment, never argv', () {
    expect(ps1, isNot(contains("'--password'")));
    for (final name in [
      'POS_PG_PASSWORD',
      'POS_ADMIN_PASSWORD',
      'POS_TILL_PASSWORD',
      'POS_BACKUP_PASSWORD',
    ]) {
      expect(ps1, contains('\$env:$name'));
      expect(migrate, contains(name));
    }
  });

  test('permissions by security id, so an Arabic Windows is not a surprise',
      () {
    expect(ps1Code, contains('S-1-5-32-544'));
    expect(ps1Code, isNot(contains('Administrators:')));
    expect(ps1Code, isNot(contains("'Administrators'")));
  });

  test('never trust authentication', () {
    expect(ps1Code, contains("'scram-sha-256'"));
    expect(ps1Code, isNot(contains('trust')));
  });
}
