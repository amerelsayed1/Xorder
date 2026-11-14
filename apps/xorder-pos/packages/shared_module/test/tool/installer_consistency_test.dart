import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Windows installer is three files in two languages that must agree, on a
/// platform none of this suite runs on. So they are read as text and checked
/// against each other: the one kind of break that would otherwise only show up
/// on a business's machine.
void main() {
  final ps1 = File('../../installer/provision.ps1').readAsStringSync();

  /// The script with its comments taken out: what it RUNS. The comments say
  /// why "Administrators" and `trust` are avoided, and must not count as uses.
  final ps1Code = ps1
      .replaceAll(RegExp(r'<#.*?#>', dotAll: true), '')
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('#'))
      .map((line) => line.replaceFirst(RegExp(r'\s#\s.*$'), ''))
      .join('\n');
  final iss = File('../../installer/xorder-pos.iss').readAsStringSync();
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

  test('the till-only marker is the file the app reads, saying what it reads', () {
    final role = File('lib/data/config/installed_role.dart').readAsStringSync();
    final deployment = File('lib/core/config/deployment.dart').readAsStringSync();

    // Same file, same directory as the credentials, on both sides.
    expect(iss, contains(r'\XOrder POS\install-role.json'));
    expect(role, contains("fileName = 'install-role.json'"));
    // The value is the wire form of TerminalRole.child, verbatim.
    expect(iss, contains('{"role": "client_terminal"}'));
    expect(deployment, contains("child('client_terminal')"));
    // Written by a till-only install only, and removed by a server install.
    expect(iss, contains("if not WizardIsComponentSelected('database') then"));
    expect(iss, contains('DeleteFile(RoleFile)'));
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
    // one would install a second copy beside the first. One id per app since
    // pos-split-apps (D6); the single app's old id is only ever looked for, so
    // the new installers can refuse to go in beside it (D5).
    const offline = '541470B8-9655-4C8B-B613-BDE215C517D6';
    const cloud = 'CFE3951B-E0DC-4C64-908C-5BCAB02681F5';
    const legacy = '6B0C8F3E-2B6A-4F43-9C8D-58E4A1B7D9C2';
    expect(iss, contains('#define OfflineGuid "$offline"'));
    expect(iss, contains('#define CloudGuid "$cloud"'));
    expect(iss, contains('#define LegacyGuid "$legacy"'));
    expect(iss, contains('AppId={#AppIdSetup}'));
    expect(iss, isNot(contains('AppId={{$legacy')));

    // The workflow repeats the three for its refusal check; one changed in
    // only one of the two files would test the wrong key.
    final workflow = File(
      '../../../../.github/workflows/pos-windows-installer.yml',
    ).readAsStringSync();
    expect(workflow, contains("OFFLINE_GUID: '$offline'"));
    expect(workflow, contains("CLOUD_GUID: '$cloud'"));
    expect(workflow, contains("LEGACY_GUID: '$legacy'"));
  });

  // pos-cloud-single-till-sqlite: the Cloud app keeps its data in an
  // encrypted SQLite file it makes itself. Its installer must carry no
  // PostgreSQL, no pos_migrate, no provisioning, and no "till only" type.
  group('the Cloud installer has no database to install', () {
    /// The `#if` that [needle]'s first line sits inside, or null.
    String? enclosingIf(String text, String needle) {
      final at = text.indexOf(needle);
      expect(at, greaterThanOrEqualTo(0), reason: 'not found: $needle');
      var depth = 0;
      final before = text.substring(0, at).split('\n').reversed;
      for (final line in before) {
        final l = line.trim();
        if (l.startsWith('#endif')) depth++;
        if (l.startsWith('#if') && !l.startsWith('#ifdef') &&
            !l.startsWith('#ifndef')) {
          if (depth == 0) return l;
          depth--;
        }
      }
      return null;
    }

    test('every database part of the script is Offline only', () {
      for (final part in [
        r'Source: "{#PgDir}',
        r'pos_migrate.exe"; DestDir',
        r'Source: "provision.ps1"',
        'Name: "database"',
        'Name: "till"',
        'Name: "lan"',
        '[UninstallRun]',
        'function PrepareToInstall',
        'procedure CurStepChanged',
      ]) {
        expect(
          enclosingIf(iss, part),
          '#if Flavor == "Offline"',
          reason: '$part must not reach the Cloud installer',
        );
      }
      // The app itself is in both, outside any flavor block.
      expect(enclosingIf(iss, r'Source: "{#AppDir}'), isNull);
    });

    test('the workflow fetches and checks PostgreSQL for Offline only', () {
      final workflow = File(
        '../../../../.github/workflows/pos-windows-installer.yml',
      ).readAsStringSync();
      for (final step in [
        '- name: Build pos_migrate.exe',
        '- name: Cache the PostgreSQL archive',
        '- name: PostgreSQL binaries',
        '- name: Install, check, upgrade, check again\n',
      ]) {
        final at = workflow.indexOf(step);
        expect(at, greaterThanOrEqualTo(0), reason: step);
        final next = workflow.indexOf('- name:', at + step.length);
        expect(
          workflow.substring(at, next),
          contains("if: matrix.flavor == 'Offline'"),
          reason: step,
        );
      }
      expect(
        workflow,
        contains("if (Test-Path (Join-Path \$app 'pgsql')) { throw"),
        reason: 'the Cloud leg proves it shipped no PostgreSQL',
      );
    });
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

  group('the LAN is encrypted (ADR-006 slice C)', () {
    test('the private ranges are hostssl unless a technician said otherwise',
        () {
      for (final range in ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']) {
        expect(ps1Code, contains('\$kind all all $range scram-sha-256'));
      }
      expect(ps1Code, contains("if (\$plaintextLan) { 'host' } else { 'hostssl' }"));
      // No plain `host` line for a LAN range is written unconditionally.
      expect(ps1Code, isNot(contains('"host all all 10.')));
      expect(ps1Code, isNot(contains("'host all all 192.")));
    });

    test('ssl is switched on with the files the script writes', () {
      expect(ps1Code, contains("ssl = on"));
      expect(ps1Code, contains("ssl_cert_file = 'server.crt'"));
      expect(ps1Code, contains("ssl_key_file = 'server.key'"));
      expect(ps1Code, contains("Join-Path \$DataDir 'server.crt'"));
      expect(ps1Code, contains("Join-Path \$DataDir 'server.key'"));
    });

    test('the LAN is opened only when the certificate was made', () {
      expect(ps1Code, contains("\$listen = if (\$lanOpen) { '*' }"));
      expect(ps1Code, contains('if (\$lanOpen) {\n    New-NetFirewallRule'));
    });

    test('the key file is locked down before the key is written into it', () {
      final write = RegExp(
        r'function Write-PrivateKey.*?\n}',
        dotAll: true,
      ).firstMatch(ps1Code)!.group(0)!;
      expect(
        write.indexOf('Set-Owners'),
        lessThan(write.indexOf('WriteAllText')),
      );
    });

    test('the published certificate is the file the app reads', () {
      final tls = File('lib/data/postgres/pos_tls.dart').readAsStringSync();
      expect(ps1, contains("Join-Path \$Root 'server-certificate.pem'"));
      expect(tls, contains("fileName = 'server-certificate.pem'"));
      expect(tls, contains("directoryName = 'XOrder POS'"));
    });

    test('every exit code the script documents, the installer answers', () {
      for (final code in ['exit 2', 'exit 3', 'exit 4']) {
        expect(ps1Code, contains(code));
      }
      expect(iss, contains('0, 3, 4:'));
      expect(iss, contains("CustomMessage('LanTlsFailed')"));
    });

    test('every new installer message is in both languages', () {
      for (final key in [
        'LanSecured',
        'LanTlsFailed',
        'CertificateRenewed',
        'LanCarriedOver',
      ]) {
        expect(iss, contains('english.$key='), reason: key);
        expect(iss, contains('arabic.$key='), reason: key);
      }
    });
  });
}
